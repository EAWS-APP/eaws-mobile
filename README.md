# EAWS Citizen App

EAWS is a Flutter/Dart citizen mobile app. This checkout does not include the staff dashboard or the production EAWS backend. The dashboard is maintained separately in the `eaws-web-dashboard` repository.

## Architecture and current integration

- **Mobile:** Flutter application in `lib/`.
- **Identity and profiles:** InsForge REST Auth, using email one-time codes and password login. Access and refresh tokens are persisted with `flutter_secure_storage`. Configure only a public/anonymous client key; never ship an InsForge admin key in the app.
- **EAWS application data:** `EawsApiClient` uses the separately hosted EAWS API for incidents, community posts/comments, alerts, safe zones, and incident media metadata. Its local TEST default is `http://127.0.0.1:5001/api`; set `EAWS_API_URL` to the API base URL. The EAWS production backend is not part of this repository, and its routes/policies are not verified here.
- **InsForge media:** Evidence bytes are uploaded to the `sos_evidence` InsForge bucket, then an attachment record is requested from the EAWS API. Bucket permissions, schema, and backend route compatibility need verification against an isolated test project.
- **Realtime and notifications:** There is no realtime subscription or push-notification integration in this checkout. The community feed polls its API every ten seconds. The in-app notifications control is not connected to a notification service.
- **Location and maps:** `geolocator` obtains device coordinates; Nominatim is used for reverse geocoding; `google_maps_flutter` displays maps. The Android and iOS native projects contain placeholder Google Maps API keys.
- **Dispatcher:** The separate Next.js dashboard runs at `http://localhost:3000/dashboard`. Its local TEST mode reads and dispatches synthetic incidents through the same loopback API as the mobile demo. The TEST incident chat is shared with the citizen demo, retained on disk, and available in the dashboard Messages inbox. No SMS, push, real responder units, or production backend flow is connected.
- **Local SOS/chat drill:** The demo app submits an SOS to the local dispatcher API using a stable client event key. Citizen and dispatcher messages share the incident thread, carry timestamps and TEST delivery/read states, and remain in the local state file after app/operator sign-out and API restart. Retry keys prevent duplicate messages after an uncertain response. This is test-only behavior, not a substitute for an authenticated production backend or durable event log.

## Configure and run

Install Flutter/Dart and fetch dependencies:

```sh
flutter pub get
```

Pass the InsForge endpoint, public client key, and EAWS API URL at runtime:

```sh
flutter run -d chrome \
  --dart-define=INSFORGE_BASE_URL=https://YOUR_INSFORGE_HOST \
  --dart-define=INSFORGE_ANON_KEY=YOUR_PUBLIC_CLIENT_KEY \
  --dart-define=EAWS_API_URL=https://YOUR_EAWS_API_HOST/api
```

Use an isolated test InsForge project and test EAWS API. The mobile client performs real writes when configured. Do not point it at production during QA. For an Android emulator, use `10.0.2.2` rather than `localhost` to reach a host-machine API; a physical device requires a reachable HTTPS host or host LAN address.

The InsForge project must have email OTP/password auth enabled, profile endpoints available, and a `sos_evidence` bucket configured with mobile upload permissions. The EAWS API must implement the routes consumed by this app, including incident, community, alert, safe-zone, and incident-media endpoints. No schema or server configuration has been created or validated in this checkout.

Replace the native Google Maps placeholders in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/AppDelegate.swift` with environment-specific Maps SDK keys before native map testing.

### Isolated local demo

In terminal 1, start the synthetic API (records persist locally across API restarts and operator/citizen sign-out):

```sh
node tooling/dev_dispatcher_server.mjs
```

In terminal 2, run the separate dashboard repository with its default local API URL:

```sh
cd /path/to/eaws-web-dashboard
npm run dev
```

Open `http://localhost:3000/dashboard`. It displays a persistent TEST MODE banner and disables calls, citizen messaging, and broadcasts. It polls the local incident feed and its TEST Dispatch action changes the same synthetic incident record.

In terminal 3, run the citizen app in explicit demo mode:

```sh
flutter run -d chrome \
  --dart-define=EAWS_DEMO_MODE=true \
  --dart-define=EAWS_API_URL=http://127.0.0.1:5001/api
```

Open the Flutter app at its local development URL and the operator dashboard at `http://localhost:3000/dashboard`. Both use the same local API. Use the app's **Messages** tab to reopen a prior TEST incident conversation; the active SOS screen also shows that incident's chat. Use the dashboard **Messages** button to open the dispatcher inbox. The API is bound to loopback by default. Its ignored `tooling/.data/dispatcher-state.json` file stores test incidents, reporter profiles, posts, comments, reactions, messages, notes, and audit history; `EAWS_TEST_STATE_FILE` can select a different local file. Only the explicit developer-only `/api/dev/reset` route replaces this test dataset. Do not change the server host to a public interface or substitute real contact numbers.

## Local checks

```sh
flutter test --no-pub
flutter analyze --no-pub
node --test tooling/dev_dispatcher_server.test.mjs
```

## Known integration gaps

The local harness and dashboard verify only the explicitly labeled synthetic REST flow. There is no deployable EAWS backend source in this checkout, so the local file store is not the production source of truth. Production realtime, push notifications, SMS fallback, authenticated role enforcement, medical-data masking/audit, zones, and multi-operator behavior remain unimplemented or unverified. The TEST API's synthetic client header is not production authentication. A successful local request only indicates that the TEST API recorded an action; it does not establish dispatch receipt or emergency response. Do not use this app for real emergency dispatch until those systems are implemented and tested together in an isolated environment. See [SYNC_DESIGN.md](./SYNC_DESIGN.md) and [TEST_FINDINGS.md](./TEST_FINDINGS.md) for the current contract and test evidence.
