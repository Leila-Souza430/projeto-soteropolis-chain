# Soterópolis Chain — App do Cidadão

Flutter app citizens use to register waste drop-offs (descartes) at Ecopontos,
earn Green Tokens, track their balance, and redeem tokens for a Coelba energy
bill discount.

Citizens never see a wallet address, private key, seed phrase, or the word
"blockchain" anywhere in the UI. Login is an ordinary email/SMS code; a
Solana keypair is derived silently behind that login (Web3Auth / MetaMask
Embedded Wallets) and used only server-side. All chain signing (minting on a
validated descarte, burning on a resgate) happens in soteropolis-backend -
this app only ever makes plain HTTP calls to it, plus two direct Supabase
client calls (balance, transaction history) under the citizen's own session.

## Required `--dart-define` flags

None of these are hardcoded in source. Without them the app still builds and
runs, but login/API calls will fail against empty credentials - fill these in
once the corresponding backend/dashboard setup exists.

| Flag | Required | Default | What it is |
|---|---|---|---|
| `API_BASE_URL` | recommended | `http://10.0.2.2:8000` | soteropolis-backend's base URL. The default only works for an Android emulator talking to a backend running on the same machine (`10.0.2.2` is the emulator's alias for host localhost) - override for a physical device or a deployed backend. |
| `SUPABASE_URL` | yes | *(empty)* | Same value as `SUPABASE_URL` in `soteropolis-backend/.env`. |
| `SUPABASE_ANON_KEY` | yes | *(empty)* | Supabase project's anon/public key (NOT the service role key - this app only ever uses the citizen's own session, never an elevated one). |
| `WEB3AUTH_CLIENT_ID` | yes | *(empty)* | Public client ID of the existing MetaMask Embedded Wallets project. Never use its Client Secret in the mobile app. |
| `WEB3AUTH_VERIFIER` | yes | `soteropolis-supabase-jwt` | The dashboard's Custom Authentication connection id (`AuthConnectionConfig.authConnectionId` - older Web3Auth docs call this a "verifier"). Must be created in the dashboard, configured to verify Supabase's JWT (issuer, JWKS/audience per Supabase's own asymmetric signing key setup). |
| `WEB3AUTH_VERIFIER_CLIENT_ID` | yes | *(empty)* | `AuthConnectionConfig.clientId` for the Supabase custom connection. The SDK requires a non-null value even for a JWKS-only connection; the correct value is still being confirmed with MetaMask. A local experimental value does not establish that the configuration is valid. |

### Primary: `--dart-define-from-file`

Create `dart_define.local.json` in this directory (same directory as this
README) with all six keys from the table above:

```json
{
  "API_BASE_URL": "http://10.0.2.2:8000",
  "SUPABASE_URL": "https://xxxxx.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "WEB3AUTH_CLIENT_ID": "BxYz...",
  "WEB3AUTH_VERIFIER": "soteropolis-supabase-jwt",
  "WEB3AUTH_VERIFIER_CLIENT_ID": "..."
}
```

This filename is gitignored (see `.gitignore`) - same spirit as
`soteropolis-backend/.env` being gitignored. It never gets tracked, even
once a git repo exists at the project root. Then run:

```sh
flutter run --dart-define-from-file=dart_define.local.json
```

Works the same way for a release build:
`flutter build apk --dart-define-from-file=dart_define.local.json`.
Requires Flutter 3.7+ (this project targets 3.47.1+).

### Fallback: flag-by-flag

Equivalent to the above, spelled out one `--dart-define` per flag - useful
for CI or a one-off run without creating a file:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=WEB3AUTH_CLIENT_ID=BxYz... \
  --dart-define=WEB3AUTH_VERIFIER=soteropolis-supabase-jwt \
  --dart-define=WEB3AUTH_VERIFIER_CLIENT_ID=...
```

For a release build, use `flutter build apk` with the same flags - see
`flutter build apk --help`.

The Web3Auth login redirect URL is **not** a dart-define: it's
`soteropolisapp://com.soteropolis.soteropolis_app`, hardcoded in
`lib/config/env.dart` and mirrored in the second `<intent-filter>` of
`android/app/src/main/AndroidManifest.xml`. It's derived from the app's own
Android applicationId, not a secret - if that ever changes, both places must
change together.

## What's still pending outside this app

These items remain unverified or incomplete outside this app:

- The current app build temporarily uses Supabase email/password for testing,
  so it does not send a login email. The Supabase sign-in appears to succeed,
  but the app then displays a wallet-configuration error. Diagnose the
  MetaMask/Web3Auth and backend steps independently; success of Supabase auth
  does not prove the wallet flow works.
- The MetaMask Embedded Wallets project and Supabase Custom Authentication
  connection exist. The connection is configured with the Supabase JWKS
  endpoint, issuer, and audience; a successful Web3Auth authentication has
  not yet been confirmed. The SDK-required custom connection `clientId` is
  still being verified.
- Supabase's default email template preview shows a magic link, and custom
  SMTP is disabled. The email link test returned an invalid/expired-token
  error. Free-plan sending limits are a possible constraint, not a confirmed
  explanation for that verification error. Do not enable custom SMTP unless
  a provider controlled by the project owner is available.
- Three migrations under `../migrations/` need to be pasted into the Supabase
  SQL Editor manually (no DDL access from this environment): the
  `on_auth_user_created` signup trigger, the `get_saldo_gt()` RPC, and the
  `descarte-fotos` storage upload policy. This app is coded assuming all
  three already exist.

## Architecture notes

- **No Solana RPC calls or transaction building in this app.** The `solana`
  package is used narrowly, for one thing:
  `Ed25519HDKeyPair.fromPrivateKeyBytes` in `lib/services/auth_service.dart`,
  to turn the ed25519 private key Web3Auth hands back into a base58 Solana
  address locally, once, right after login. Minting and burning both happen
  in soteropolis-backend.
- **`camera`, not `image_picker`.** No gallery affordance exists anywhere in
  `lib/screens/camera/camera_descarte_screen.dart`'s widget tree - accepting
  an existing photo would defeat the antifraude purpose of that screen.
- **Idempotency**: see the doc comment on `lib/services/idempotency_store.dart`
  for the full contract (why keys persist across retries but clear on
  terminal errors).
- **web3auth_flutter API note**: this app targets `web3auth_flutter: ^7.0.0`,
  whose actual shipped API (`Web3AuthFlutter.connectTo`, `AuthConnection`,
  `AuthConnectionConfig`, `Web3AuthNetwork`, `getEd25519PrivateKey`) differs
  from the examples in that package's own README, which is written against
  the older pre-7.0 API (`Web3AuthFlutter.login`, `Provider`, `LoginConfigItem`,
  `Network`, `getEd25519PrivKey`) and hadn't been updated to match at the time
  this app was built. `lib/services/auth_service.dart` was written against
  the package's actual `lib/*.dart` source, not its README.

## Running

```sh
flutter pub get
flutter run --dart-define-from-file=dart_define.local.json # see table above
```

No automated tests yet (explicitly deferred to a later phase).

## Authentication test status

The Android debug APK was built and installed on a physical device. Current
diagnostic sequence:

1. Supabase email-link verification has returned
   `Email link is invalid or has expired`; the reason is not yet established.
2. The app's temporary email/password flow reaches the wallet setup step but
   fails to configure the Carteira Digital. Check the app's sanitized local
   diagnostics and confirm the backend is running before retrying.
3. Validate Web3Auth custom authentication and wallet derivation before
   considering the sign-in flow complete.

Never commit `dart_define.local.json`, passwords, access tokens, Supabase
service-role keys, or the MetaMask Client Secret. Do not include full callback
URIs or query/fragment parameters in shared logs.
