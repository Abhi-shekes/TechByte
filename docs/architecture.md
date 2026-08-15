# Architecture

## The constraint that shapes everything

**A swipe must never wait.**

The product is a vertical feed. If advancing a card can block on a database
write, a network call, or an AI request, the experience fails regardless of how
good the content is. Every structural decision below follows from that.

Consequences:

- The feed reads from an **in-memory pool** loaded before the first card renders.
- Card selection is **pure and synchronous** (`FeedSelector`).
- Persistence is **fire-and-forget** (`unawaited(...)` on the swipe path).
- AI generation is **background, guarded, and optional**.
- SQLite is the **only** read path for content. Firestore is a sync target.

## Layers

```
presentation   Widgets. No business logic, no service calls.
      ↓
application    Riverpod controllers/providers. Orchestration.
      ↓
domain         Pure Dart: models, selection, validation. No I/O, no Flutter.
      ↓
data           Repositories over Drift and Firebase.
```

Direction of dependency is strictly downward. `domain` imports nothing from
`data`, which is what makes `FeedSelector` and `QuestionValidator` directly
unit-testable without a database or a network.

## Feature-first layout

```
lib/
├── app/
│   ├── config/       feed_config.dart, ai_config.dart
│   ├── router/       app_router.dart
│   └── theme/        app_theme.dart, app_palette.dart, app_typography.dart
├── core/
│   ├── providers/    core_providers.dart  (composition root)
│   └── storage/      app_database.dart, tables.dart
├── features/
│   ├── auth/         data · presentation
│   ├── feed/         application · domain · presentation
│   ├── questions/    data · domain
│   ├── deep_dive/    application · data · presentation
│   ├── explore/ practice/ saved/ profile/ onboarding/ settings/ shell/
└── services/
    ├── ai/           gemini_service.dart, ai_usage_tracker.dart, prompts/
    └── firebase/     firebase_bootstrap.dart
```

`questions/` holds the content model shared by every other feature, rather
than duplicating it per feature.

## State management

Riverpod 3, **written by hand**. Codegen is unavailable on Dart 3.9.2 (see the
README), and manual declaration costs little:

| Provider | Type | Purpose |
|---|---|---|
| `sharedPreferencesProvider` | `Provider` | Overridden in `main` |
| `appDatabaseProvider` | `Provider` | Drift, disposed with the scope |
| `questionRepositoryProvider` | `Provider` | Content + interactions |
| `geminiServiceProvider` | `Provider` | The only `firebase_ai` consumer |
| `authStateProvider` | `StreamProvider` | Drives routing |
| `userPreferencesProvider` | `NotifierProvider` | Write-through settings |
| `feedControllerProvider` | `AsyncNotifierProvider` | The feed |
| `explanationProvider` | `FutureProvider.family` | Cache-first derived content |

`core_providers.dart` is the composition root. `SharedPreferences` is loaded
before `runApp` and injected as an override so the theme and onboarding state
are known for the very first frame — otherwise launch flashes the wrong theme.

## Data flow: one swipe

```
PageView.onPageChanged(index)
   │
   ├─ mark previous card skipped if never revealed   ─┐
   ├─ mark new card seen                              ├─ unawaited, off the path
   │                                                  │
   ├─ extend the queue from the in-memory pool  ── pure, synchronous
   ├─ state = AsyncData(next)                   ── renders immediately
   │
   └─ _maybeGenerate()                          ── background, guarded
         │
         └─ unseen pool < threshold && AI enabled && budget left
               └─ GeminiService.generateQuestions()
                     └─ validate → insert → reload pool
```

If generation is disabled, out of budget, or offline, nothing above changes —
the feed keeps drawing from what is already stored.

## Persistence

Drift over SQLite. Five tables:

| Table | Holds |
|---|---|
| `question_rows` | Content, whatever its source |
| `question_interactions` | Per-question user state, including review schedule |
| `topic_familiarity_rows` | Per-category counters |
| `generated_content_rows` | Cached deep dives and alternate explanations |
| `ai_usage_rows` | Daily AI counters for budget enforcement |

Content and user state are separate tables so content can be replaced or
re-synced without touching history.

## Routing

`go_router` with a `StatefulShellRoute.indexedStack`, so each of the five tabs
keeps its own stack and scroll position — switching to Saved and back must not
reset the feed.

Redirects resolve in order:

```
auth still loading         → /splash
not signed in              → /sign-in
onboarding incomplete      → /onboarding
otherwise on a pre-app route → /feed
```

The router instance is created once. A `ChangeNotifier` bridges Riverpod
changes to `refreshListenable`, so auth changes re-run `redirect` without
tearing down the navigator.

## Where each spec requirement lives

| Requirement | Implementation |
|---|---|
| Controlled randomness (§13) | `features/feed/domain/feed_selector.dart` |
| Content validation (§29) | `features/questions/domain/question_validator.dart` |
| Prompt library (§30) | `services/ai/prompts/prompt_library.dart` |
| Pre-generation buffer (§31) | `FeedController._maybeGenerate` |
| Billing safety (§23) | `app/config/ai_config.dart`, `AiUsageTracker` |
| Cost control (§49) | `ai_usage_rows` table |
| Offline-first (§27) | `QuestionRepository` — SQLite only |
