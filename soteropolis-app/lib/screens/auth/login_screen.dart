import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web3auth_flutter/web3auth_flutter.dart';

import '../../services/auth_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_feedback.dart';

enum _LoginMethod { email, sms }

/// awaitingEmailLink replaces enterCode for the email method only: email
/// logs in via magic link now (AuthService.sendOtp/verifyOtpAndLinkWallet's
/// header comment), so there's no code for the citizen to type - SMS still
/// goes straight to enterCode exactly as before.
enum _LoginStep { enterContact, enterCode, awaitingEmailLink }

/// Citizen login: Supabase email/SMS OTP is the only identity check shown
/// here. The Web3Auth Carteira Digital exchange happens silently right
/// after OTP verification (AuthService.verifyOtpAndLinkWallet) - there is no
/// separate "connect wallet" step or screen, and no mention of "wallet,"
/// "chave privada," or "blockchain" anywhere in this UI (SPEC #6).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoggedIn,
    this.initialErrorMessage,
  });

  final AuthService authService;
  final VoidCallback onLoggedIn;

  /// Shown immediately on the enterContact step - set when main.dart routes
  /// here after a post-login failure (e.g. linkWalletForActiveSession
  /// throwing from the onAuthStateChange listener) that this screen wasn't
  /// mounted to catch itself. Null for a normal, error-free navigation to
  /// login.
  final String? initialErrorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _contactController = TextEditingController();
  final _codeController = TextEditingController();

  // Not reassigned: the Email/SMS toggle that used to set this is removed
  // from the UI (see _buildContactStep) - only email is presented right
  // now. AuthService's phone/SMS code paths are still intact behind this
  // field, so re-adding a toggle later just means making this mutable
  // again and restoring the SegmentedButton removed from that method.
  final _LoginMethod _method = _LoginMethod.email;
  _LoginStep _step = _LoginStep.enterContact;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errorMessage = widget.initialErrorMessage;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contactController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // Android-only quirk documented by web3auth_flutter: Chrome Custom Tabs
  // has no close-button callback, so the only way to detect the citizen
  // dismissing the Web3Auth step without finishing it is to notice the app
  // resuming foreground while a login is in flight. Without this,
  // Web3AuthFlutter.connectTo's Future would just hang forever instead of
  // throwing UserCancelledException.
  //
  // Gated on authService.isWeb3AuthConnecting so this only fires for a
  // resume that happens during an actual connect - not for every unrelated
  // AppLifecycleState.resumed event (cold start's own first resume, the app
  // being reopened after backgrounding for any other reason, etc).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.authService.isWeb3AuthConnecting) {
      Web3AuthFlutter.setCustomTabsClosed();
    }
  }

  String? get _email =>
      _method == _LoginMethod.email ? _contactController.text.trim() : null;
  String? get _phone =>
      _method == _LoginMethod.sms ? _contactController.text.trim() : null;

  Future<void> _sendOtp() async {
    if (_contactController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.sendOtp(email: _email, phone: _phone);
      setState(() {
        _step = _method == _LoginMethod.email
            ? _LoginStep.awaitingEmailLink
            : _LoginStep.enterCode;
      });
    } catch (e) {
      // sendOtp's failure was previously swallowed entirely - only a
      // generic message reached the UI, with no raw exception logged
      // anywhere. Supabase's rate limit (2 emails/hour on the default
      // email provider) and its "Email address not authorized" restriction
      // (recipient isn't a project team member) both surface here as an
      // AuthException; this is what makes either one diagnosable instead
      // of needing to reproduce blind.
      if (e is AuthException) {
        debugPrint(
          'sendOtp AuthException: ${e.runtimeType} statusCode=${e.statusCode} '
          'code=${e.code} message=${e.message}',
        );
      } else {
        debugPrint('sendOtp failed: $e');
      }
      setState(
        () => _errorMessage = _method == _LoginMethod.email
            ? 'Não foi possível enviar o link de acesso. Tente novamente.'
            : 'Não foi possível enviar o código. Tente novamente.',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.verifyOtpAndLinkWallet(
        email: _email,
        phone: _phone,
        token: _codeController.text.trim(),
      );
      widget.onLoggedIn();
    } on InvalidOtpException {
      setState(
        () => _errorMessage = 'Código incorreto ou expirado. Tente novamente.',
      );
    } on WalletDerivationException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Algo deu errado. Tente novamente.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.eco,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Soterópolis Chain',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entre para acompanhar seus Green Tokens',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  if (_step == _LoginStep.enterContact) ..._buildContactStep(),
                  if (_step == _LoginStep.enterCode) ..._buildCodeStep(),
                  if (_step == _LoginStep.awaitingEmailLink)
                    ..._buildAwaitingEmailLinkStep(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    StatusBanner.error(message: _errorMessage!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContactStep() {
    return [
      TextField(
        controller: _contactController,
        keyboardType: _method == _LoginMethod.email
            ? TextInputType.emailAddress
            : TextInputType.phone,
        decoration: InputDecoration(
          labelText: _method == _LoginMethod.email
              ? 'Seu e-mail'
              : 'Seu telefone (com DDD)',
        ),
      ),
      const SizedBox(height: 24),
      PrimaryButton(
        label: 'Enviar código',
        isLoading: _isLoading,
        onPressed: _sendOtp,
      ),
    ];
  }

  List<Widget> _buildCodeStep() {
    return [
      Text(
        'Digite o código enviado para ${_contactController.text.trim()}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, letterSpacing: 8),
        decoration: const InputDecoration(labelText: 'Código'),
      ),
      const SizedBox(height: 24),
      PrimaryButton(
        label: 'Confirmar',
        isLoading: _isLoading,
        onPressed: _verifyCode,
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _isLoading
            ? null
            : () => setState(() {
                _step = _LoginStep.enterContact;
                _codeController.clear();
                _errorMessage = null;
              }),
        child: const Text('Usar outro e-mail ou telefone'),
      ),
    ];
  }

  /// Email only. No code to type here - the citizen finishes login by
  /// tapping the link in their inbox, which hands off to the
  /// soteropolisapp://supabase-auth-callback deep link
  /// (AndroidManifest.xml). This screen doesn't itself watch for that:
  /// main.dart's onAuthStateChange listener does the wallet link and then
  /// replaces the whole navigation stack with '/home', which unmounts this
  /// screen the same way widget.onLoggedIn() does for phone/SMS - so
  /// nothing further is needed here for the success path.
  List<Widget> _buildAwaitingEmailLinkStep() {
    return [
      Icon(
        Icons.mark_email_read_outlined,
        size: 56,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 20),
      Text(
        'Verifique seu e-mail e toque no link de acesso enviado',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Text(
        'Enviamos um link para ${_contactController.text.trim()}. '
        'Abra seu e-mail e toque nele para continuar.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      const LoadingState(),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => setState(() {
          _step = _LoginStep.enterContact;
          _errorMessage = null;
        }),
        child: const Text('Usar outro e-mail'),
      ),
    ];
  }
}
