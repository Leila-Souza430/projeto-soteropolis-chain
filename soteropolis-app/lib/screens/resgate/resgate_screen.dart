import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/resgate.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/idempotency_store.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_feedback.dart';

const String _flowName = 'resgate';

/// Resgate de Benefício: converts Green Tokens into a Coelba account
/// credit. Coelba-side validation (does this instalacao_coelba actually
/// exist, etc.) is explicitly out of scope here and server-side too - this
/// screen only calls POST /resgates as specified.
class ResgateScreen extends StatefulWidget {
  const ResgateScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<ResgateScreen> createState() => _ResgateScreenState();
}

class _ResgateScreenState extends State<ResgateScreen> {
  final _quantidadeController = TextEditingController();
  final _instalacaoController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  ResgateResponse? _result;

  @override
  void dispose() {
    _quantidadeController.dispose();
    _instalacaoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final quantidade = double.tryParse(
      _quantidadeController.text.replaceAll(',', '.'),
    );
    final instalacao = _instalacaoController.text.trim();
    if (quantidade == null || quantidade <= 0 || instalacao.isEmpty) {
      setState(
        () => _errorMessage =
            'Preencha a quantidade e a instalação Coelba corretamente.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final store = IdempotencyStore(await SharedPreferences.getInstance());

      // Reuse a still-pending request from a previous attempt that never
      // reached a terminal result, if one exists - otherwise this is a
      // fresh submission, so a new key+payload is created and persisted
      // before the network call below fires (SPEC #3).
      final pending =
          store.getPending(_flowName) ??
          await store.createPending(
            _flowName,
            ResgateRequest(
              quantidade: quantidade,
              instalacaoCoelba: instalacao,
            ).toJson(),
          );

      final response = await widget.authService.apiClient
          .post<Map<String, dynamic>>(
            '/resgates',
            data: pending.payload,
            headers: {'Idempotency-Key': pending.idempotencyKey},
          );

      await store.clearPending(_flowName); // 201: definitive success
      setState(() => _result = ResgateResponse.fromJson(response.data!));
    } on NetworkException catch (e) {
      // Outcome unknown server-side - key is kept so a retry replays safely.
      setState(() => _errorMessage = e.message);
    } on ApiException catch (e) {
      // Any other ApiException is a definitive, non-retryable server
      // answer for this exact payload - clear the key so the next tap
      // starts a genuinely new request instead of repeating a rejection.
      final store = IdempotencyStore(await SharedPreferences.getInstance());
      await store.clearPending(_flowName);
      setState(() => _errorMessage = e.message);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resgatar Benefício')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _result != null ? _buildSuccess(_result!) : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      children: [
        Text(
          'Troque seus Green Tokens por desconto na sua conta de energia Coelba.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _quantidadeController,
          enabled: !_isLoading,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantidade de Green Tokens',
            suffixText: 'GT',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _instalacaoController,
          enabled: !_isLoading,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Número da instalação Coelba',
          ),
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          StatusBanner.error(message: _errorMessage!),
          const SizedBox(height: 16),
        ],
        PrimaryButton(
          label: 'Resgatar',
          isLoading: _isLoading,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _buildSuccess(ResgateResponse result) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 96,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            '${result.quantidade.toStringAsFixed(2)} GT resgatados com sucesso!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'O desconto será aplicado na sua próxima conta Coelba.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            label: 'Voltar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
