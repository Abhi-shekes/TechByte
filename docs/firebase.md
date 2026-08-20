# Firebase

## Project

| | |
|---|---|
| Project ID | `techbyte-app` |
| Display name | TechByte |
| Android package | `com.techbyte.app` |
| App ID | `1:213851361054:android:c408bd7f48b2de6a75c30f` |
| Plan | Spark (free) |

**The plan must stay Spark.** Every service below runs inside the free tier.
Upgrading to Blaze is not a fix for anything in this project — see
[gemini.md](gemini.md).

## Services

| Service | Used for | Status |
|---|---|---|
| Authentication | Google Sign-In, the only provider | Requires manual enable |
| AI Logic | Gemini Developer API | Requires manual enable |
| Firestore | User data sync, curated content | Wired, not yet used |
| Analytics | Product events | Initialised, release only |
| Crashlytics | Crashes and fatal errors | Initialised, release only |
| App Check | Protects the shared quotas from abuse | Initialised |
| Cloud Messaging | Reminders | Not yet used |

Firestore is a **sync target only**. It is never on the swipe path, and the
feed never reads from it. That keeps document reads far below free limits and
keeps the app fast offline.

## Manual setup steps

Two things cannot be done from the CLI. Sign-in fails without the first.

### 1. Enable Google as a sign-in provider

[Authentication → Sign-in method](https://console.firebase.google.com/project/techbyte-app/authentication/providers)
→ Google → Enable → set a support email → Save.

Then **re-run `flutterfire configure`**. Enabling the provider creates the
OAuth web client, and `google-services.json` must be regenerated to include it.
On Android, `google_sign_in` reads that client id from the generated
`default_web_client_id` resource — which is why nothing is hardcoded in
`AuthRepository`.

### 2. Enable the Gemini Developer API

[Firebase AI Logic](https://console.firebase.google.com/project/techbyte-app/ailogic)
→ choose **Gemini Developer API**, not Vertex AI.

## SHA fingerprints

Google Sign-In on Android requires the signing certificate fingerprint to be
registered. The debug fingerprint for the original dev machine is registered:

```
C4:D9:69:9D:2D:38:82:B8:74:2E:8F:77:02:D1:B9:C4:C4:BB:98:F9
```

Every additional machine needs its own — debug keystores are per-machine, so
sign-in failing on a teammate's laptop is almost always this.

```bash
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android

firebase apps:android:sha:create \
  1:213851361054:android:c408bd7f48b2de6a75c30f <SHA1> \
  --project techbyte-app
```

The **release** keystore fingerprint must be added before shipping, and the
Play App Signing fingerprint too if Play re-signs the app.

## App Check

```dart
providerAndroid: kDebugMode
    ? AndroidDebugProvider(debugToken: /* APP_CHECK_DEBUG_TOKEN, or null */)
    : const AndroidPlayIntegrityProvider(),
```

Release builds attest through Play Integrity with nothing to configure beyond
the signing certificate's SHA-256 in the console. Debug builds have no Play
signature, so they present a registered token instead.

### Registering a debug token

Left to itself the SDK generates a **fresh random token on every install**, and
logs this on each launch until it is registered:

```
W/DebugAppCheckProvider: Failed to exchange debug token (2634a616-…).
```

Pin it instead, so a device is registered once and survives reinstalls:

```bash
# Any UUID you choose. Keep it out of git — it is a credential.
flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=$APP_CHECK_DEBUG_TOKEN
```

Then register that same UUID under
[App Check → Apps → Manage debug tokens](https://console.firebase.google.com/project/techbyte-app/appcheck/apps).

### Telling whether it worked

`activate` succeeding proves nothing: registering a provider is a local
operation that cannot fail for an unregistered device. So `FirebaseBootstrap`
mints one token at startup purely as a diagnostic, and on failure logs both the
cause and what to do about it:

```
App Check cannot attest this build, so every Firebase AI request will fail
with 403 "App attestation failed": ...
Debug builds present a randomly generated debug token. Find the line "Enter
this debug secret into the allow list" in `adb logcat -s
DebugAppCheckProvider`, register that UUID under App Check > Apps > Manage
debug tokens, then reinstall.
```

Without it the first symptom is a 403 thrown out of whichever feature happened
to ask for a token first, which reads as "the AI is broken" rather than "this
device is not on the allow list".

### What breaks while it fails

Activation failure is caught and logged rather than thrown — App Check must
never prevent the app from starting. But if enforcement is enabled, an
unregistered debug token means the backend rejects:

- Firestore reads and writes → progress sync silently fails
- Firebase AI Logic → deep dives, "explain differently", answer grading and
  debug scenarios all return unavailable

That last line is only true because `GeminiService._request` catches
`FirebaseException`. App Check throws from *another plugin* while the request
headers are being assembled, before Gemini is reached, and
`FirebaseAIException` is a separate hierarchy that does not cover it — so the
403 used to escape the service, escape the controller awaiting it, and surface
in the global error handler with the calling screen stuck on its skeleton.
Practice → Debugging was the visible casualty: it generates a scenario on
entry, so the screen never left its loading state.

**The feed keeps working**, because it reads only from SQLite. That is the
offline-first design doing its job: a broken attestation degrades the AI
extras and leaves the core product intact.

## Configuration files

Both are generated and **gitignored**:

- `android/app/google-services.json`
- `lib/firebase_options.dart`

Regenerate with:

```bash
flutterfire configure --project=techbyte-app \
  --platforms=android --android-package-name=com.techbyte.app
```

CI restores `google-services.json` from a base64 `GOOGLE_SERVICES_JSON` secret.

## Firestore

Rules in `firestore.rules`, indexes in `firestore.indexes.json`.

```bash
firebase deploy --only firestore:rules --project techbyte-app
```

The database itself has not been created yet — nothing writes to it in the
current phase. When creating it, pick a region close to users
(`asia-south1` for India) and note that **the region cannot be changed later**.

## Environments

Development, staging and production should be separate Firebase projects.
Only one exists today. When splitting, use Flutter build flavours with a
`firebase_options` file per flavour and keep `applicationIdSuffix` distinct so
builds can coexist on one device.
