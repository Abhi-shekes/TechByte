# Android build

Android is the only target. There is no iOS, web or desktop configuration, and
none should be added.

## Configuration

| | |
|---|---|
| Application ID | `com.techbyte.app` |
| Namespace | `com.techbyte.app` |
| minSdk | 31 (Android 12) |
| targetSdk | Flutter default |
| Java / Kotlin JVM target | 17 / 11 |
| Core library desugaring | Enabled |

minSdk 31 is set explicitly, not inherited. The product targets modern Android
only, and it keeps the dependency surface simple.

## Build

```bash
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release      # for Play
```

`dart run build_runner build --delete-conflicting-outputs` must have run first —
Drift's generated code is not committed.

## Permissions

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

`INTERNET` is declared explicitly and must stay. Flutter injects it into the
**debug** manifest automatically but not release, so omitting it produces a
release build where every network call fails while debug works fine.

No other permissions are requested.

## Signing

`android/app/build.gradle.kts` reads `android/key.properties` if present:

```properties
storePassword=…
keyPassword=…
keyAlias=…
storeFile=…/techbyte-release.jks
```

When absent, release falls back to debug signing so `flutter run --release`
still works for a contributor without the keystore. Neither the keystore nor
`key.properties` is committed.

To create one:

```bash
keytool -genkey -v -keystore ~/techbyte-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias techbyte
```

**The release SHA-1 must be registered in Firebase before Google Sign-In works
in a release build** — and the Play App Signing fingerprint too if Play
re-signs. See [firebase.md](firebase.md).

## CI

`.github/workflows/android.yml` runs on every push/PR to `main` or `dev`:

```
analyze-and-test → build
```

- `dart format --set-exit-if-changed`
- `flutter analyze --fatal-infos`
- `flutter test`
- `flutter build apk --debug`, uploaded as an artifact

This workflow only verifies the code. It never publishes anything and needs
no signing secrets.

CI regenerates Drift code and restores `google-services.json` from the
`GOOGLE_SERVICES_JSON` secret (base64). Without that secret the Firebase Gradle
plugin fails at configuration time, so the workflow checks for it and fails
with a clear message rather than a stack trace.

To set it:

```bash
base64 -w0 android/app/google-services.json
# paste into repo Settings → Secrets → Actions → GOOGLE_SERVICES_JSON
```

## Release automation

`.github/workflows/release.yml` fires when a **PR from `dev` into `main` is
merged** (or manually via `workflow_dispatch`). See
[release.md](release.md) for the full branch flow, versioning scheme,
required secrets and artifact naming convention.

## Release checklist

Before the first automated release will succeed:

- [ ] Release keystore created (`tools/create_release_keystore.sh`)
- [ ] Release SHA-1 and SHA-256 registered in Firebase
- [ ] Play App Signing SHA-1 registered (once the app is uploaded to Play once)
- [ ] `GOOGLE_SERVICES_JSON`, `FIREBASE_OPTIONS_DART`,
      `RELEASE_KEYSTORE_BASE64`, `RELEASE_KEYSTORE_PASSWORD`,
      `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD` set as repository secrets
- [ ] Actions → General → Workflow permissions set to "Read and write"
- [ ] App Check switched to Play Integrity (already the non-debug default)
- [ ] Firestore rules deployed
- [ ] Crashlytics and Analytics verified in a release build

## Not done yet

- ProGuard / R8 rules beyond the defaults.
- Build flavours for dev / staging / production.
- Play Console upload — releases currently publish to GitHub Releases only.
