import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/descarte.dart';
import '../../models/ecoponto.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/camera_service.dart';
import '../../services/idempotency_store.dart';
import '../../services/location_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_feedback.dart';

const String _flowName = 'descarte';

const List<String> _tiposResiduo = [
  'Plástico',
  'Papel',
  'Vidro',
  'Metal',
  'Eletrônico',
  'Óleo de Cozinha',
];

enum _Step {
  loading,
  permissionDenied,
  selectEcoponto,
  capture,
  submitting,
  result,
}

/// Câmera Antifraude: the app's only descarte-capture path.
///
/// Deliberately has NO gallery affordance anywhere in this screen's widget
/// tree (SPEC decision #2) - accepting an existing photo would defeat the
/// entire antifraude purpose, since the point is proof the citizen is
/// physically at the ecoponto right now. GPS + timestamp are read at the
/// shutter instant, not when the screen opens or the ecoponto is picked.
class CameraDescarteScreen extends StatefulWidget {
  const CameraDescarteScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<CameraDescarteScreen> createState() => _CameraDescarteScreenState();
}

class _CameraDescarteScreenState extends State<CameraDescarteScreen> {
  final _locationService = LocationService();
  final _cameraService = CameraService();

  _Step _step = _Step.loading;
  String? _permissionErrorMessage;
  bool _locationServiceDisabled = false;

  List<Ecoponto> _ecopontos = [];
  Position? _referencePosition; // for sorting/display only, not submitted
  Ecoponto? _selectedEcoponto;
  String _tipoResiduo = _tiposResiduo.first;
  final _pesoController = TextEditingController();

  bool _isSubmitting = false;
  String? _submitError;
  DescarteResponse? _result;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pesoController.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _step = _Step.loading);
    try {
      await _locationService.ensureReady();
    } on LocationServiceOffException {
      setState(() {
        _step = _Step.permissionDenied;
        _locationServiceDisabled = true;
        _permissionErrorMessage = 'O GPS do aparelho está desligado.';
      });
      return;
    } on LocationPermissionDeniedException {
      setState(() {
        _step = _Step.permissionDenied;
        _locationServiceDisabled = false;
        _permissionErrorMessage = 'Permissão de localização negada.';
      });
      return;
    }

    try {
      await _cameraService.initialize();
    } on CameraUnavailableException catch (e) {
      setState(() {
        _step = _Step.permissionDenied;
        _locationServiceDisabled = false;
        _permissionErrorMessage = e.message;
      });
      return;
    }

    await _loadEcopontos();
  }

  Future<void> _loadEcopontos() async {
    try {
      final position = await _locationService.getCurrentPosition();
      final response = await widget.authService.apiClient.get<List<dynamic>>(
        '/ecopontos',
      );
      final ecopontos =
          (response.data ?? [])
              .map((row) => Ecoponto.fromJson(row as Map<String, dynamic>))
              .toList()
            ..sort(
              (a, b) =>
                  Geolocator.distanceBetween(
                    position.latitude,
                    position.longitude,
                    a.latitude,
                    a.longitude,
                  ).compareTo(
                    Geolocator.distanceBetween(
                      position.latitude,
                      position.longitude,
                      b.latitude,
                      b.longitude,
                    ),
                  ),
            );

      setState(() {
        _referencePosition = position;
        _ecopontos = ecopontos;
        _step = _Step.selectEcoponto;
      });
    } catch (_) {
      setState(() {
        _step = _Step.permissionDenied;
        _permissionErrorMessage =
            'Não foi possível carregar os Ecopontos. Verifique sua conexão.';
      });
    }
  }

  void _selectEcoponto(Ecoponto ecoponto) {
    setState(() {
      _selectedEcoponto = ecoponto;
      _step = _Step.capture;
    });
  }

  Future<void> _captureAndSubmit() async {
    final ecoponto = _selectedEcoponto;
    if (ecoponto == null) return;

    setState(() {
      _step = _Step.submitting;
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      // Photo and GPS fix are both taken NOW, at the shutter instant - this
      // is the antifraude proof, not whatever position was read earlier for
      // sorting the ecoponto list.
      final photo = await _cameraService.capturePhoto();
      final position = await _locationService.getCurrentPosition();

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw const UnauthorizedException();
      }
      final fotoUrl = await _cameraService.uploadPhoto(photo, userId);

      final store = IdempotencyStore(await SharedPreferences.getInstance());
      final pending =
          store.getPending(_flowName) ??
          await store.createPending(
            _flowName,
            DescarteRequest(
              ecopontoId: ecoponto.id,
              latitude: position.latitude,
              longitude: position.longitude,
              tipoResiduo: _tipoResiduo,
              pesoEstimado: double.tryParse(
                _pesoController.text.replaceAll(',', '.'),
              ),
              fotoUrl: fotoUrl,
            ).toJson(),
          );

      final response = await widget.authService.apiClient
          .post<Map<String, dynamic>>(
            '/descartes',
            data: pending.payload,
            headers: {'Idempotency-Key': pending.idempotencyKey},
          );

      await store.clearPending(_flowName); // 201: definitive success
      setState(() {
        _result = DescarteResponse.fromJson(response.data!);
        _step = _Step.result;
      });
    } on NetworkException catch (e) {
      // Outcome unknown server-side - key stays, so the retry button below
      // reuses the same key+payload instead of starting a new attempt.
      setState(() {
        _submitError = e.message;
        _step = _Step.result;
      });
    } on ApiException catch (e) {
      final store = IdempotencyStore(await SharedPreferences.getInstance());
      await store.clearPending(
        _flowName,
      ); // definitive rejection - not retryable as-is
      setState(() {
        _submitError = e.message;
        _step = _Step.result;
      });
    } catch (_) {
      setState(() {
        _submitError = 'Algo deu errado. Tente novamente.';
        _step = _Step.result;
      });
    } finally {
      _isSubmitting = false;
    }
  }

  void _resetForNewDescarte() {
    setState(() {
      _result = null;
      _submitError = null;
      _selectedEcoponto = null;
      _pesoController.clear();
      _step = _Step.selectEcoponto;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Descarte')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.loading:
        return const LoadingState(label: 'Preparando câmera e localização...');
      case _Step.permissionDenied:
        return _buildPermissionDenied();
      case _Step.selectEcoponto:
        return _buildEcopontoList();
      case _Step.capture:
        return _buildCapture();
      case _Step.submitting:
        return const LoadingState(label: 'Enviando seu descarte...');
      case _Step.result:
        return _buildResult();
    }
  }

  Widget _buildPermissionDenied() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 72,
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
          Text(
            _permissionErrorMessage ?? 'Não foi possível continuar.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Para registrar um descarte, o app precisa de acesso à câmera e à '
            'localização. Toque abaixo para abrir as configurações e permitir o acesso, '
            'depois volte a esta tela.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: _locationServiceDisabled
                ? 'Abrir configurações de localização'
                : 'Abrir configurações',
            onPressed: () async {
              if (_locationServiceDisabled) {
                await Geolocator.openLocationSettings();
              } else {
                await Geolocator.openAppSettings();
              }
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _bootstrap,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEcopontoList() {
    if (_ecopontos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum Ecoponto ativo encontrado no momento.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _ecopontos.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            'Escolha o Ecoponto onde você está:',
            style: Theme.of(context).textTheme.titleLarge,
          );
        }
        final ecoponto = _ecopontos[index - 1];
        final distancia = _referencePosition == null
            ? null
            : Geolocator.distanceBetween(
                _referencePosition!.latitude,
                _referencePosition!.longitude,
                ecoponto.latitude,
                ecoponto.longitude,
              );
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const Icon(Icons.recycling, size: 32),
            title: Text(
              ecoponto.nome,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            subtitle: distancia == null
                ? null
                : Text('~${distancia.round()}m de distância'),
            onTap: () => _selectEcoponto(ecoponto),
          ),
        );
      },
    );
  }

  Widget _buildCapture() {
    final controller = _cameraService.controller;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ecoponto: ${_selectedEcoponto?.nome}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: controller != null && controller.value.isInitialized
              ? CameraPreview(controller)
              : const LoadingState(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _tipoResiduo,
                decoration: const InputDecoration(labelText: 'Tipo de resíduo'),
                items: _tiposResiduo
                    .map(
                      (tipo) =>
                          DropdownMenuItem(value: tipo, child: Text(tipo)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _tipoResiduo = value ?? _tipoResiduo),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pesoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Peso estimado (opcional)',
                  suffixText: 'kg',
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Tirar foto e enviar',
                icon: Icons.camera_alt,
                isLoading: _isSubmitting,
                onPressed: _captureAndSubmit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_submitError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusBanner.error(message: _submitError!),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Tentar novamente',
              onPressed: () => setState(() {
                _submitError = null;
                _step = _Step.capture;
              }),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar ao início'),
            ),
          ],
        ),
      );
    }

    final result = _result!;
    final tokens = result.quantidadeTokens;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: 96,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            tokens != null
                ? 'Você ganhou ${tokens.toStringAsFixed(2)} Green Tokens!'
                : 'Descarte registrado com sucesso!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Registrar outro descarte',
            onPressed: _resetForNewDescarte,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Voltar ao início'),
          ),
        ],
      ),
    );
  }
}
