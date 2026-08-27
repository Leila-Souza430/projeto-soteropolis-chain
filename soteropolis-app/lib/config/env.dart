/// Compile-time configuration, read from `--dart-define` flags.
///
/// None of these are hardcoded: the FastAPI backend URL varies by
/// environment, and the Supabase/Web3Auth credentials don't exist yet (the
/// Web3Auth dashboard project and its Custom Authentication connection are
/// pending manual setup). See the project README for the full list of flags
/// and what to fill in once they do.
class Env {
  const Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // 10.0.2.2 is the Android emulator's alias for the host machine's own
    // localhost - only correct for local dev against a backend running on
    // this same machine. Override for a physical device or a deployed
    // backend.
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String web3authClientId = String.fromEnvironment(
    'WEB3AUTH_CLIENT_ID',
  );

  /// The Custom Authentication connection's id (older Web3Auth docs/dashboards
  /// call this a "verifier"), created in the Web3Auth dashboard.
  static const String web3authVerifier = String.fromEnvironment(
    'WEB3AUTH_VERIFIER',
    defaultValue: 'soteropolis-supabase-jwt',
  );

  /// AuthConnectionConfig.clientId for that same connection. The Web3Auth
  /// dashboard assigns this when the Custom Authentication connection is
  /// created - confirm its exact meaning there when wiring up real values.
  /// The SDK requires *some* non-null value for this field even for a
  /// JWKS-only custom connection.
  static const String web3authVerifierClientId = String.fromEnvironment(
    'WEB3AUTH_VERIFIER_CLIENT_ID',
  );

  /// Must exactly match the scheme and host attributes of the data element
  /// inside android/app/src/main/AndroidManifest.xml's second intent-filter.
  /// Not a dart-define: it's derived from the app's own applicationId, not
  /// a secret, and the two must never drift apart - see the comment above
  /// that intent-filter.
  static const String web3authRedirectUrl =
      'soteropolisapp://com.soteropolis.soteropolis_app';

  /// Email magic-link login callback (Supabase Auth). Passed as
  /// `emailRedirectTo` to `signInWithOtp` - AuthService.sendOtp does this
  /// for the email case only, since SMS has no redirect concept.
  ///
  /// Must exactly match the scheme and host attributes of the data element
  /// inside android/app/src/main/AndroidManifest.xml's third intent-filter,
  /// and must also be added as a Redirect URL in the Supabase dashboard
  /// (Authentication -> URL Configuration) - unlike web3authRedirectUrl,
  /// Supabase itself validates this URL against an allow-list before
  /// honoring it as a redirect target. Deliberately a different host than
  /// web3authRedirectUrl (both share the soteropolisapp:// scheme) so
  /// Android and Supabase's own deep-link session detector never confuse
  /// the two callbacks - see main.dart's detectSessionInUriPredicate.
  static const String supabaseAuthRedirectUrl =
      'soteropolisapp://supabase-auth-callback';
}
