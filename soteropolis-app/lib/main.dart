import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'config/theme.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_dashboard_screen.dart';

/// Lets ApiClient force navigation back to the login screen on a 401
/// (session expired/invalid) from anywhere in the widget tree, without
/// threading a BuildContext through every service call.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Shown on login when linkWalletForActiveSession fails after a signedIn
/// event (see onAuthStateChange below) - plain language, no "wallet" or
/// "Web3Auth" (this project's established no-jargon UI convention).
const _walletLinkFailedMessage =
    'Não foi possível configurar sua Carteira Digital. Tente novamente.';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Needed before any DateFormat(..., 'pt_BR') call (carteira_screen.dart) -
  // intl throws otherwise, even for fully-numeric patterns.
  await initializeDateFormatting('pt_BR', null);

  // publishableKey is supabase_flutter 2.17's renamed, non-deprecated
  // parameter for what's still the same value: the project's publishable
  // (anon) key from the Supabase dashboard - kept as SUPABASE_ANON_KEY in
  // Env to match soteropolis-backend/.env's naming for the identical key.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    // AuthClientOptions.authFlowType already defaults to
    // AuthFlowType.pkce (confirmed against the installed supabase_flutter
    // 2.17.2 / gotrue 2.27.2 source - this doesn't change behavior), but
    // it's set explicitly here so the choice is pinned and self-documented
    // rather than riding a library default that could change later. PKCE
    // is what Supabase recommends for mobile/deep-link auth: the magic
    // link's redirect carries a one-time-use `code` to exchange, instead
    // of putting raw access/refresh tokens directly in the deep-link URI
    // the way AuthFlowType.implicit would.
    //
    // detectSessionInUriPredicate is narrowed to our own callback host so
    // Supabase's deep-link session detector only ever reacts to
    // Env.supabaseAuthRedirectUrl. Without this, its default heuristic
    // (any incoming link carrying an access_token/code/error* param) would
    // also inspect Web3Auth's redirect - which shares this app's
    // soteropolisapp:// scheme, just a different host - and there'd be no
    // guarantee some future Web3Auth SDK version's own redirect params
    // never collide with that heuristic.
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUriPredicate: (uri) =>
          uri.host == 'supabase-auth-callback',
    ),
  );
  await AuthService.initWeb3Auth();

  final apiClient = ApiClient(
    onUnauthorized: () {
      rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    },
  );
  final authService = AuthService(apiClient);

  // Diagnostic only: confirms whether the OS delivers the magic-link deep
  // link to the app at all, independent of whether supabase_flutter's own
  // detectSessionInUriPredicate (above) accepts it. AppLinks() is a
  // singleton and uriLinkStream a broadcast stream (confirmed against the
  // installed app_links 7.2.1 source), so this listener is purely additive
  // - it cannot steal or interfere with supabase_flutter's own internal
  // subscription on the same stream.
  AppLinks().uriLinkStream.listen(
    (uri) => debugPrint('AppLinks uriLinkStream received: $uri'),
    onError: (Object error, StackTrace stackTrace) =>
        debugPrint('AppLinks uriLinkStream error: $error'),
  );

  // Single source of truth for "has this app instance already landed the
  // citizen on /home" - without it, a cold start where the deep link's
  // session resolves before tryRestoreSession() (below) gets a chance to
  // run would race two independent navigation decisions against each
  // other: initialRoute picking '/home' AND this listener's own
  // pushNamedAndRemoveUntil('/home') a few seconds later, once its slower
  // Web3Auth+backend chain finishes - replacing an already-settled route
  // stack (mid-flight on HomeDashboardScreen's own initState fetch) out
  // from under itself, which is what was corrupting the element tree on
  // cold start. Seeded from tryRestoreSession()'s result below, and reset
  // on sign-out so a later re-login (email, same app session) isn't
  // silently blocked by a stale `true`.
  var hasNavigatedHome = false;

  // Sends the citizen back to a fresh /login with a plain-language error
  // (see _walletLinkFailedMessage) when linkWalletForActiveSession fails
  // after a signedIn event. Guarded on hasNavigatedHome (read-only here,
  // same flag the success branch below both reads and writes) so a failure
  // that resolves after some other path already landed the citizen on
  // /home can't yank them back to login; left unset by this branch so a
  // later, distinct login attempt (citizen retries with a fresh email) is
  // never blocked from navigating home on success.
  void navigateToLoginWithError() {
    if (hasNavigatedHome) return;
    rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
      arguments: _walletLinkFailedMessage,
    );
  }

  // Email magic-link login completes asynchronously and has no screen
  // reliably mounted to await it (deep link can resolve after the app was
  // backgrounded, or relaunch it cold) - so, unlike phone/SMS's
  // verifyOtpAndLinkWallet, it's driven from here rather than from
  // login_screen.dart. Once supabase_flutter's own deep-link handling
  // (armed by detectSessionInUri, on by default) exchanges the incoming
  // soteropolisapp://supabase-auth-callback link for a session, this fires
  // and completes the same wallet-link chain phone/SMS runs inline.
  //
  // linkWalletForActiveSession is safe to call here even though phone/SMS
  // logins also raise signedIn (verifyOTP() triggers it too): it's a no-op
  // for a session verifyOtpAndLinkWallet already linked, so this only ever
  // does real work for a session nothing else has handled - which is also
  // why navigation below is gated on didLink (and hasNavigatedHome)
  // rather than unconditional.
  Supabase.instance.client.auth.onAuthStateChange.listen(
    (data) async {
      debugPrint('onAuthStateChange event: ${data.event}');
      if (data.event == AuthChangeEvent.signedOut) {
        hasNavigatedHome = false;
        return;
      }
      if (data.event != AuthChangeEvent.signedIn) return;
      try {
        final didLink = await authService.linkWalletForActiveSession();
        debugPrint('linkWalletForActiveSession didLink: $didLink');
        if (didLink && !hasNavigatedHome) {
          hasNavigatedHome = true;
          rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
          );
        }
      } on WalletDerivationException catch (e) {
        // login_screen.dart has no listener of its own to hand this to
        // (see its comment on the awaiting-email-link step) - this is a
        // rare failure (Web3Auth misconfigured/unreachable). Previously
        // this was only logged, leaving the citizen stuck on a frozen
        // "check your email" screen with no feedback (and was the actual
        // source of the repeated _elements.contains(element) crash) - now
        // it sends them back to a fresh login screen with a plain-language
        // error instead. e.message isn't shown (may carry Web3Auth
        // internals); the fixed, no-jargon message is used instead.
        debugPrint(
          'Falha ao vincular carteira apos login por link magico: ${e.message}',
        );
        navigateToLoginWithError();
      } catch (e) {
        // Fallback for anything else linkWalletForActiveSession can throw
        // (e.g. a backend/API error surfaced while linking) - same
        // treatment as above rather than leaving the citizen stuck
        // silently.
        debugPrint('Falha inesperada ao vincular carteira apos login: $e');
        navigateToLoginWithError();
      }
    },
    // Without this, a failed PKCE code exchange (expired/replayed link,
    // wrong code_verifier, rate limit hit mid-flow) fires as an error
    // event via GoTrueClient.notifyException - which this stream would
    // otherwise have no registered handler for on this listener.
    onError: (Object error, StackTrace stackTrace) {
      if (error is AuthException) {
        debugPrint(
          'onAuthStateChange AuthException: ${error.runtimeType} '
          'statusCode=${error.statusCode} code=${error.code} '
          'message=${error.message}',
        );
      } else {
        debugPrint('onAuthStateChange error: $error');
      }
    },
  );

  final isLoggedIn = await authService.tryRestoreSession();
  // If we're starting straight on /home via initialRoute below, the
  // listener above must not repeat that navigation for the same session's
  // signedIn event - see hasNavigatedHome's declaration comment.
  hasNavigatedHome = isLoggedIn;

  runApp(SoteropolisApp(authService: authService, startLoggedIn: isLoggedIn));
}

class SoteropolisApp extends StatelessWidget {
  const SoteropolisApp({
    super.key,
    required this.authService,
    required this.startLoggedIn,
  });

  final AuthService authService;
  final bool startLoggedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Soterópolis Chain',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      initialRoute: startLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => LoginScreen(
          authService: authService,
          onLoggedIn: () => rootNavigatorKey.currentState
              ?.pushNamedAndRemoveUntil('/home', (route) => false),
          // Set by navigateToLoginWithError's arguments above when routing
          // here after a post-login failure; null for every other
          // navigation to /login (initial route, ApiClient's 401 handler).
          initialErrorMessage:
              ModalRoute.of(context)?.settings.arguments as String?,
        ),
        '/home': (context) => HomeDashboardScreen(
          authService: authService,
          onLoggedOut: () => rootNavigatorKey.currentState
              ?.pushNamedAndRemoveUntil('/login', (route) => false),
        ),
      },
    );
  }
}
