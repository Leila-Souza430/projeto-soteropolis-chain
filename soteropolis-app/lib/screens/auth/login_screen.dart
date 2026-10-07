import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web3auth_flutter/web3auth_flutter.dart';

import '../../services/auth_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_feedback.dart';

/// Test login uses a Supabase email/password account to avoid depending on
/// delivery of one-time email links. Web3Auth runs after Supabase sign-in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    this.initialErrorMessage,
  });

  final AuthService authService;

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
  final _passwordController = TextEditingController();
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
    _passwordController.dispose();
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

  Future<void> _signIn() async {
    if (_contactController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Informe seu e-mail e sua senha.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.signInWithPasswordAndLinkWallet(
        email: _contactController.text.trim(),
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      debugPrint(
        'Password sign-in AuthException: ${e.runtimeType} '
        'statusCode=${e.statusCode} code=${e.code} message=${e.message}',
      );
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Não foi possível entrar. Confira seus dados.',
      );
    } on WalletDerivationException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      debugPrint('Password sign-in failed: $e');
      if (!mounted) return;
      setState(() => _errorMessage = 'Algo deu errado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  ..._buildCredentialsForm(),
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

  List<Widget> _buildCredentialsForm() {
    return [
      TextField(
        controller: _contactController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.username, AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Seu e-mail'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Senha'),
      ),
      const SizedBox(height: 24),
      PrimaryButton(
        label: 'Entrar',
        isLoading: _isLoading,
        onPressed: _signIn,
      ),
    ];
  }
}
