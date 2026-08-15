# Testing

```bash
flutter test                       # all 80
flutter test test/feed/            # one directory
flutter test --plain-name 'reveals the answer'
```

## Coverage

| File | Tests | Covers |
|---|---|---|
| `test/feed/feed_selector_test.dart` | 11 | Slot weighting, dedup, category runs, review windows, fallbacks |
| `test/feed/question_card_test.dart` | 8 | Think/reveal states, section rendering, bookmark |
| `test/questions/question_validator_test.dart` | 7 | Banned phrasings, length bounds, duplicate detection |
| `test/questions/question_test.dart` | 7 | Serialisation, lenient parsing, seed content quality |
| `test/storage/question_repository_test.dart` | 13 | Seeding, inserts, interactions, progress, reporting |
| `test/review/spaced_repetition_test.dart` | 9 | Interval ladder, reset-on-wrong, due windows, persistence |
| `test/practice/evaluation_test.dart` | 13 | Grade parsing, clamping, pass threshold, rubrics, scenarios |
| `test/feed/daily_session_test.dart` | 12 | Determinism per date, category spread, padding, progress |

## What is tested, and why

**The feed algorithm** gets the most attention. It is the hardest part of the
product to eyeball — a subtly wrong weighting looks fine for ten swipes and
bad over a week — and it is pure and synchronous, so it is cheap to test
thoroughly. `FeedSelector` takes both `Random` and `now` as parameters
specifically to make this possible.

**Seed content is tested against the validator.** Seed questions define the
quality bar that generated content is judged against, so the bar has to clear
itself. This test would have caught a definition-style question slipping into
the bundled set.

**Lenient parsing is tested with hostile input** — unknown enum values, a
string where a list belongs, whitespace-only fields — because
`Question.fromJson` parses model output and must degrade rather than throw.

## Determinism

`FeedSelector` is random by design, so every feed test passes a seeded
`Random`. A flaky feed test is worse than no feed test.

Widget tests pass `reducedMotion: true` so assertions run against the settled
state rather than racing a transition.

## Database tests

`AppDatabase.forTesting(NativeDatabase.memory())` — real SQLite, no mocks. The
queries are the thing being tested, so mocking them would test nothing.

Host-VM tests need `libsqlite3`. Most Linux machines ship `libsqlite3.so.0` but
not the bare `libsqlite3.so` symlink, which lives in the `-dev` package, so the
loader fails on a missing file rather than anything real.
`test/helpers/sqlite_test_setup.dart` points the loader at the versioned
library; call `configureSqliteForTests` from `setUpAll` in any test that opens
a database. No `sudo` required.

## A test that found a real bug

The duplicate-detection test failed on first run. These two:

> Why does a phone slow down when its storage is nearly full?
> Why does your phone slow down when the storage is almost full?

scored 0.71 on Jaccard similarity, under the 0.82 threshold — so the validator
would have let an obvious rephrasing into the feed. The fix was changing the
metric to shared tokens over the *larger* token set, which scores that pair at
0.83 while still refusing to call a short question a duplicate of a longer one
that happens to contain its words.

## Hostile-input testing for grades

`AnswerEvaluation.fromJson` is tested against scores out of range, numbers
arriving as strings, malformed dimension entries, and a completely empty
object. All of it comes from a model, so none of it can be trusted to have the
shape the schema asked for.

One rule worth keeping: a grade with no ideal answer is `isUsable == false` and
never reaches the UI. A bare number teaches nothing, and showing one would make
the feature feel like scoring rather than learning.

## Not yet covered

- `GeminiService` — needs a fake `FirebaseAI`; the error-classification and
  budget logic is the part worth testing.
- `PracticeController` — the grade-then-schedule sequence, in particular that
  only a graded answer moves a review stage.
- `FeedController` — the orchestration around the selector.
- `AnalyticsService` — worth a test asserting no event parameter ever carries
  question or answer text.
- `AuthRepository` — needs fakes for `FirebaseAuth` and `GoogleSignIn`.
- Integration tests (§52) — sign-in, offline mode, sync.

`mocktail` is already a dev dependency for this.
