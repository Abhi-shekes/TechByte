# TechByte

[![Android CI](https://github.com/Abhi-shekes/TechByte/actions/workflows/android.yml/badge.svg)](https://github.com/Abhi-shekes/TechByte/actions/workflows/android.yml)
[![Release](https://github.com/Abhi-shekes/TechByte/actions/workflows/release.yml/badge.svg)](https://github.com/Abhi-shekes/TechByte/actions/workflows/release.yml)

Short-form technical curiosity for Android. A full-screen vertical feed of
questions worth thinking about — swipe, think, reveal, learn, repeat.

> Why can two USB-C cables that look completely identical behave completely
> differently?

TechByte is **not** a tech news app and **not** a quiz app. Every question has
to pass one test: *would a technically curious person genuinely want to know
the answer?* Definition questions ("What is RAM?") are banned in code, not just
by convention — see [`QuestionValidator`](lib/features/questions/domain/question_validator.dart).

---

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Project, theme, Firebase, Google Sign-In, local DB, Riverpod, architecture | Done |
| 2 | Vertical feed, question cards, think/reveal, cache, prefetch | Done |
| 3 | Gemini generation, structured output, validation, dedup | Done |
| 4 | Saved, history, preferences, topic familiarity, daily session, offline | Done |
| 5 | Deep dive, explain differently, spaced repetition, personalised feed | Done |
| 6 | Interview, debug, production scenarios, evaluation | Done |
| 7 | App Check, analytics events, Crashlytics, perf, CI, release config | Done |

Also built: launcher icon and splash, global search, daily reminders,
Firestore sync, and an admin CLI (`tools/admin/`).

### Two things need you, not code

1. **Create the Firestore database.** Sync code is written and wired, but the
   database does not exist yet. The region **cannot be changed afterwards**:

   ```bash
   firebase firestore:databases:create "(default)" \
     --location=asia-south1 --project techbyte-app
   firebase deploy --only firestore:rules --project techbyte-app
   ```

   `asia-south1` (Mumbai) is the right choice for India-based users. Until the
   database exists, every sync call fails gracefully and logs — the app is
   fully usable without it.

2. **Create the release keystore**: `bash tools/create_release_keystore.sh`.
   Not automated on purpose — lose that file and you can never update the app
   on Play again.

### Deliberately not built

**Current-technology content** (§48). The `trending` feed slot exists and its
weight is redistributed automatically. Doing it properly needs sourcing,
attribution and expiry, and a model cannot verify that something is recent —
generating "news" without grounding would produce confident fiction, which is
worse than an empty slot.

## Practice

Two graded modes plus spaced review, all reachable from the Practice tab.

**Interview** draws a real question from the local pool and grades a free-text
answer on accuracy, completeness, clarity, depth and structure.

**Debugging** poses a production incident with metrics and grades the
*reasoning*, not just the conclusion — someone who investigates in a sensible
order scores well even without naming the exact root cause. Four scenarios ship
bundled, so the mode works offline; more are generated when quota allows.

**Review** returns questions you got wrong on an expanding schedule — 1 day, 3,
7, 21, 60. A wrong answer resets to the start rather than stepping back one
stage. Review is self-graded rather than AI-graded, deliberately: it is
high-frequency, and spending an AI request on "did I know that?" would burn the
daily budget on the cheapest possible judgement.

Grading is the one place the app knowingly waits on Gemini — the user has just
spent a minute writing, so a few seconds is acceptable. It runs at temperature
0.2 so the same answer does not score 5 one minute and 8 the next.

---

## Constraints

These are product requirements, not preferences:

- **Android only.** No iOS, web or desktop targets.
- **Google Sign-In only.** No email/password, phone, anonymous or other providers.
- **₹0 infrastructure.** Only free-tier services. The app must never create
  billable usage.
- **Never auto-enable billing.** If a feature cannot run inside a free quota,
  it degrades or turns off. See [docs/gemini.md](docs/gemini.md).

Free tiers are not guaranteed forever. The app is built to **stop gracefully
when a quota is exhausted**, never to spend money to keep going.

---

## Setup

### Prerequisites

- Flutter 3.35.7 (Dart 3.9.2)
- JDK 17
- Android SDK, API 31+

### 1. Install and generate

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Drift's database code is generated and **not** committed. Nothing compiles
until you run build_runner.

### 2. Firebase

The project `techbyte-app` already exists and the Android app
(`com.techbyte.app`) is registered. To regenerate local config:

```bash
flutterfire configure \
  --project=techbyte-app \
  --platforms=android \
  --android-package-name=com.techbyte.app
```

This writes `lib/firebase_options.dart` and
`android/app/google-services.json`, both gitignored.

### 3. Two manual console steps

These cannot be done from the CLI, and **sign-in will fail without them**:

1. **Enable Google as a sign-in provider**
   → [Authentication → Sign-in method](https://console.firebase.google.com/project/techbyte-app/authentication/providers)
   → Google → Enable → set a support email → Save.

2. **Confirm the debug SHA-1 is registered**
   → [Project settings → Your apps](https://console.firebase.google.com/project/techbyte-app/settings/general)

   The debug fingerprint for this machine is already registered:

   ```
   C4:D9:69:9D:2D:38:82:B8:74:2E:8F:77:02:D1:B9:C4:C4:BB:98:F9
   ```

   For another machine, get its fingerprint with:

   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore \
     -alias androiddebugkey -storepass android -keypass android
   ```

   then `firebase apps:android:sha:create <appId> <sha1> --project techbyte-app`.

After enabling Google sign-in, **re-run `flutterfire configure`** so the
refreshed `google-services.json` contains the OAuth web client id that
`google_sign_in` needs on Android.

### 4. Enable the Gemini Developer API

→ [Firebase AI Logic](https://console.firebase.google.com/project/techbyte-app/ailogic)
→ choose the **Gemini Developer API** (the no-cost option), not Vertex AI.

The app never constructs the Vertex backend; see [docs/gemini.md](docs/gemini.md).

### 5. Run

```bash
flutter run
```

The feed works immediately on bundled content — sign-in and network are not
required to see questions.

---

## Commands

```bash
flutter analyze --fatal-infos                             # lint
flutter test                                              # 80 tests
dart format lib test                                      # format
dart run build_runner build --delete-conflicting-outputs  # regenerate Drift
flutter build apk --debug                                 # build
firebase deploy --only firestore:rules --project techbyte-app
```

---

## Branch workflow & releases

```
feature branches ──► dev ──► (PR) ──► main ──► release.yml ──► GitHub Release
```

- Work happens on `dev`. Every push/PR to `dev` or `main` runs CI (format,
  analyze, test, debug build) via `.github/workflows/android.yml`.
- Merging a `dev → main` pull request triggers
  `.github/workflows/release.yml`: it bumps the version, builds a **signed**
  release APK and AAB, tags the commit, and publishes a GitHub Release with
  both files attached.
- Versioning auto-increments on every release — both the patch digit and the
  build number (`0.1.0+1` → `0.1.1+2` → …) — committed back to
  `pubspec.yaml` by the workflow itself.
- Artifact naming: `techbyte-v<version>-<buildNumber>-release.{apk,aab}`.

Full details, required secrets, and how to re-run a failed release: see
[docs/release.md](docs/release.md).

---

## Architecture

Feature-first, Riverpod for state and DI, Drift for local persistence,
go_router for navigation.

```
Android (Flutter)
   ├── Firebase Auth (Google only)
   ├── Firebase AI Logic → Gemini Developer API (free tier)
   ├── Firestore (sync target, never on the swipe path)
   ├── Analytics · Crashlytics · App Check
   └── Drift / SQLite  ← the feed reads only from here
```

The rule that shapes everything: **a swipe never waits on anything.** Cards
come from an in-memory pool loaded up front; database writes and AI generation
are dispatched without being awaited.

```
lib/
├── app/          router, theme, config (feed weights, AI budget)
├── core/         storage (Drift), providers
├── features/     auth, feed, questions, deep_dive, explore, practice,
│                 saved, profile, onboarding, settings, shell
└── services/     ai (GeminiService, prompts), firebase
```

Full detail in [docs/architecture.md](docs/architecture.md).

---

## Docs

| Document | Covers |
|---|---|
| [architecture.md](docs/architecture.md) | Layers, state management, data flow |
| [firebase.md](docs/firebase.md) | Project setup, services, App Check |
| [gemini.md](docs/gemini.md) | AI integration and how cost is kept at zero |
| [ai-prompts.md](docs/ai-prompts.md) | Prompt library and editorial rules |
| [content.md](docs/content.md) | Content model, taxonomy, quality bar |
| [feed-engine.md](docs/feed-engine.md) | Controlled randomness and slot weighting |
| [offline.md](docs/offline.md) | Offline-first behaviour and fallback chain |
| [security.md](docs/security.md) | Firestore rules, auth, data handling |
| [testing.md](docs/testing.md) | Test strategy and how to run them |
| [android-build.md](docs/android-build.md) | Build, signing, CI |
| [release.md](docs/release.md) | Branch flow, versioning, release automation |

---

## Known constraints in this toolchain

Dart 3.9.2 is below the floor of several current codegen packages:

- `riverpod_generator` / `riverpod_lint` need Dart 3.12 / 3.10. **Providers are
  written manually.** Riverpod 3 supports this fully.
- `drift_dev` above 2.29 needs Dart 3.10, so drift is pinned to 2.29.

Upgrading Flutter would lift both. It is a shared SDK across sibling projects,
so it has not been changed unilaterally.
