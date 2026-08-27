import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web3auth_flutter/enums.dart';
import 'package:web3auth_flutter/input.dart';
import 'package:web3auth_flutter/web3auth_flutter.dart';

import '../config/env.dart';
import 'api_client.dart';

/// Supabase Auth's own OTP check failed to verify (wrong/expired code).
class InvalidOtpException implements Exception {}

/// Supabase OTP succeeded but Web3Auth couldn't turn that session into a
/// Solana keypair (dashboard misconfiguration, user cancelled the Web3Auth
/// step, network failure mid-handshake).
class WalletDerivationException implements Exception {
  final String message;
  const WalletDerivationException(this.message);
}

/// Drives the citizen's entire "invisible wallet" login.
///
/// Supabase Auth's email/SMS OTP is the actual identity check (SPEC:
/// CPF is explicitly NOT supported as a login field - Web3Auth's built-in
/// providers don't natively support it). Web3Auth then exchanges that
/// already-verified Supabase session for a non-custodial Solana keypair,
/// entirely behind the scenes: the citizen never sees a seed phrase,
/// private key, or even their own address.
class AuthService {
  AuthService(this._apiClient);

  final ApiClient _apiClient;

  /// Access token already run through linkWalletForActiveSession, so a
  /// second caller observing the same signedIn event (see that method's
  /// doc comment) can no-op instead of hitting Web3Auth/the backend again.
  String? _lastLinkedAccessToken;

  /// The in-progress link operation for [_lastLinkedAccessToken]'s
  /// successor, if any. _lastLinkedAccessToken alone only closes the race
  /// once the first caller's await chain finishes - two callers observing
  /// the same signedIn event back-to-back (main.dart's listener plus a
  /// duplicate deep-link delivery, or that same listener racing
  /// verifyOtpAndLinkWallet's own direct call) would otherwise both read
  /// _lastLinkedAccessToken as unset and both kick off their own Web3Auth
  /// exchange + backend PATCH. Caching the Future itself closes that gap:
  /// every caller for the same token awaits the one in-flight operation.
  Future<bool>? _linkInFlight;

  /// True only for the span of the Web3AuthFlutter.connectTo() call inside
  /// [_deriveWalletAddress] - lets LoginScreen's didChangeAppLifecycleState
  /// gate Web3AuthFlutter.setCustomTabsClosed() to app-resume events that
  /// happen while a connect is actually outstanding, instead of firing it
  /// on every unrelated resume (e.g. cold start's own first resumed event).
  bool _isWeb3AuthConnecting = false;

  bool get isWeb3AuthConnecting => _isWeb3AuthConnecting;

  /// Exposed so screens that need both auth actions and direct FastAPI
  /// calls (camera_descarte_screen.dart, resgate_screen.dart) can receive
  /// just one object from HomeDashboardScreen instead of two.
  ApiClient get apiClient => _apiClient;

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Called once at app startup (main.dart), before runApp. Registers the
  /// Web3Auth SDK's own config - this does not perform a login by itself.
  static Future<void> initWeb3Auth() async {
    await Web3AuthFlutter.init(
      Web3AuthOptions(
        clientId: Env.web3authClientId,
        redirectUrl: Env.web3authRedirectUrl,
        // Web3Auth's OWN key-management network (sapphire_devnet), unrelated
        // to Solana's devnet/mainnet - do not conflate the two. All actual
        // Solana chain interaction happens backend-side, on whichever
        // Solana cluster soteropolis-backend/.env points SOLANA_RPC_URL at.
        web3AuthNetwork: Web3AuthNetwork.sapphire_devnet,
        authConnectionConfig: [
          AuthConnectionConfig(
            authConnection: AuthConnection.custom,
            authConnectionId: Env.web3authVerifier,
            clientId: Env.web3authVerifierClientId,
          ),
        ],
      ),
    );
  }

  /// True if both Supabase and Web3Auth already have a live session (app
  /// reopened, nothing expired) - lets main.dart skip straight to the Home
  /// Dashboard instead of the login screen.
  ///
  /// Both must agree: if only one session survived (e.g. Web3Auth's native
  /// session got cleared independently of Supabase's), the derived wallet
  /// address can't be reconstructed without a fresh Web3Auth exchange, so
  /// this is treated as logged-out and a full re-login is required.
  Future<bool> tryRestoreSession() async {
    if (_supabase.auth.currentSession == null) return false;
    try {
      await Web3AuthFlutter.initialize();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Step 1 of login: Supabase sends the actual OTP. Exactly one of [email]
  /// or [phone] must be set.
  Future<void> sendOtp({String? email, String? phone}) {
    assert(
      (email == null) != (phone == null),
      'Pass exactly one of email/phone',
    );
    return _supabase.auth.signInWithOtp(
      email: email,
      phone: phone,
      // Email logs in via magic link now, not a typed code: this is where
      // the link in that email sends the citizen back into the app (must
      // match a third AndroidManifest.xml intent-filter and a Supabase
      // dashboard Redirect URL entry - see Env.supabaseAuthRedirectUrl).
      // No redirect concept for SMS, so left null there.
      emailRedirectTo: email != null ? Env.supabaseAuthRedirectUrl : null,
    );
  }

  /// Step 2: verifies the OTP the citizen typed in, then immediately chains
  /// into the Web3Auth exchange and wallet-address link (SPEC flow steps
  /// 3-7) so the caller gets one clean pass/fail result. Exactly one of
  /// [email]/[phone] must match what was passed to [sendOtp].
  ///
  /// Throws [InvalidOtpException] if the code itself is wrong, or
  /// [WalletDerivationException] if the OTP was fine but the Web3Auth
  /// hand-off failed.
  Future<void> verifyOtpAndLinkWallet({
    String? email,
    String? phone,
    required String token,
  }) async {
    assert(
      (email == null) != (phone == null),
      'Pass exactly one of email/phone',
    );

    final AuthResponse otpResponse;
    try {
      otpResponse = await _supabase.auth.verifyOTP(
        email: email,
        phone: phone,
        token: token,
        type: email != null ? OtpType.email : OtpType.sms,
      );
    } on AuthException {
      throw InvalidOtpException();
    }

    if (otpResponse.session == null) {
      throw InvalidOtpException();
    }

    await linkWalletForActiveSession();
  }

  /// Derives (or reuses) the Web3Auth wallet for whichever Supabase session
  /// is currently active, then PATCHes it to the backend (SPEC flow steps
  /// 3-7) - the second half of login, shared by two call sites:
  ///
  /// - [verifyOtpAndLinkWallet] above calls this synchronously right after
  ///   phone/SMS's verifyOTP() resolves.
  /// - main.dart's `onAuthStateChange` listener calls this for email's
  ///   magic-link login, which has no synchronous return value to hang the
  ///   wallet link off of - the session lands asynchronously whenever the
  ///   citizen taps the link and the app picks up the deep link.
  ///
  /// Both listen to the same Supabase client, so a single phone/SMS sign-in
  /// can reach both call sites for the *same* session (verifyOTP() itself
  /// also fires a signedIn event). Idempotent per access token so that
  /// race can't trigger a second Web3Auth exchange - which would pop a
  /// second Custom Tab and PATCH twice for no reason.
  ///
  /// Returns `true` if this call performed a fresh derivation+link, `false`
  /// if the active session was already linked (a no-op, not a failure) -
  /// callers that drive navigation on success should still treat `false`
  /// as success, and only skip whatever `true` alone should trigger (e.g.
  /// main.dart doesn't need to re-navigate for a link some other call site
  /// already completed).
  Future<bool> linkWalletForActiveSession() async {
    final accessToken = _supabase.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw const WalletDerivationException('Nenhuma sessão ativa.');
    }
    if (accessToken == _lastLinkedAccessToken) {
      return false;
    }
    return _linkInFlight ??= _linkWallet(accessToken);
  }

  Future<bool> _linkWallet(String accessToken) async {
    try {
      final walletAddress = await _deriveWalletAddress(accessToken);

      await _apiClient.patch(
        '/users/me',
        data: {'wallet_address': walletAddress},
      );
      _lastLinkedAccessToken = accessToken;
      return true;
    } finally {
      _linkInFlight = null;
    }
  }

  /// Exchanges the (already Supabase-verified) [supabaseAccessToken] for a
  /// Solana address via Web3Auth, without exposing any intermediate key
  /// material past this function.
  Future<String> _deriveWalletAddress(String supabaseAccessToken) async {
    try {
      _isWeb3AuthConnecting = true;
      try {
        // Diagnostic only: precise timestamp for when connectTo() actually
        // starts, to correlate against logcat's own timestamps for the
        // deep-link intent arriving and the eventual settle/exception - see
        // MEMORY/session notes on the UserCancelledException investigation.
        debugPrint('Web3AuthFlutter.connectTo: starting');
        await Web3AuthFlutter.connectTo(
          LoginParams(
            authConnection: AuthConnection.custom,
            authConnectionId: Env.web3authVerifier,
            // Both fields carry the same JWT: LoginParams.idToken is used by
            // some AuthConnection flows, ExtraLoginOptions.id_token by
            // Web3Auth's longer-documented "Custom Authentication" pattern.
            // Setting both is harmless (unused fields are ignored) and avoids
            // guessing which one the eventual dashboard connection expects -
            // confirm against the live Web3Auth dashboard setup once the
            // verifier/connection exists (Env.web3authVerifier).
            idToken: supabaseAccessToken,
            extraLoginOptions: ExtraLoginOptions(id_token: supabaseAccessToken),
          ),
        );
      } finally {
        _isWeb3AuthConnecting = false;
      }
      debugPrint('Web3AuthFlutter.connectTo: settled ok');

      // Must be the ed25519 getter (Solana) - NOT getPrivateKey(), which
      // returns the secp256k1 key for EVM chains. Easy mistake: Web3Auth
      // exposes both from the same login.
      final hexPrivateKey = await Web3AuthFlutter.getEd25519PrivateKey();
      if (hexPrivateKey.isEmpty) {
        throw const WalletDerivationException(
          'Web3Auth não retornou uma chave.',
        );
      }

      final keyPair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: _hexToBytes(hexPrivateKey),
      );
      return keyPair.publicKey.toBase58();
    } on WalletDerivationException {
      rethrow;
    } catch (e) {
      throw WalletDerivationException(
        'Falha ao configurar a Carteira Digital: $e',
      );
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    try {
      await Web3AuthFlutter.logout();
    } catch (_) {
      // No active Web3Auth session to log out of - fine, Supabase sign-out
      // above is what actually matters for access to the backend.
    }
  }

  bool get isLoggedIn => _supabase.auth.currentSession != null;
}

/// Web3Auth returns private keys as a hex string (no "0x" prefix); the
/// `solana` package's keypair constructor needs raw bytes.
Uint8List _hexToBytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  final bytes = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
