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
| `WEB3AUTH_CLIENT_ID` | yes | *(empty)* | From the Web3Auth dashboard (dashboard.web3auth.io) project - not created yet as of this build. |
| `WEB3AUTH_VERIFIER` | yes | `soteropolis-supabase-jwt` | The dashboard's Custom Authentication connection id (`AuthConnectionConfig.authConnectionId` - older Web3Auth docs call this a "verifier"). Must be created in the dashboard, configured to verify Supabase's JWT (issuer, JWKS/audience per Supabase's own asymmetric signing key setup). |
| `WEB3AUTH_VERIFIER_CLIENT_ID` | yes | *(empty)* | `AuthConnectionConfig.clientId` for that same connection. The Web3Auth dashboard assigns this when the connection is created; confirm its exact expected value there - the SDK requires a non-null value even for a JWKS-only custom connection. |

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

These are pre-existing gaps in other parts of the project (backend/database),
not something this app's code is missing:

- The Web3Auth dashboard project + Custom Authentication connection referenced
  above don't exist yet.
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
