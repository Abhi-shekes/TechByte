# Gemini integration

## The rule

**TechByte must never generate billable usage.**

Not "should be cheap". Never. Two mechanisms enforce it.

### 1. Backend choice

```dart
FirebaseAI.googleAI()   // Gemini Developer API — has a no-cost tier
FirebaseAI.vertexAI()   // requires a billing account — NEVER USED
```

`GeminiService` constructs `googleAI()` only. `vertexAI` appears nowhere in
`lib/`, which is a grep-able invariant worth keeping that way.

### 2. Local budget

Relying on the provider's quota means discovering the limit by being rejected.
`AiUsageTracker` counts locally and stops first:

```dart
// app/config/ai_config.dart
dailyRequestBudget      = 40      // well under the free-tier limit
questionsPerGeneration  = 8       // batching is why 40 is plenty
maxRetries              = 1       // retries burn quota for little gain
requestTimeout          = 25s
quotaBackoff            = 6h      // after a quota error, stop trying
```

Counters live in `ai_usage_rows`, bucketed by UTC day: requests, failures,
quota failures, cache hits, questions generated, questions rejected.

## Service surface

Nothing outside `services/ai/` imports `firebase_ai`. Widgets never call it —
`FeedController` and `explanationProvider` do.

| Method | Status |
|---|---|
| `generateQuestions()` | Implemented |
| `generateDeepDive()` | Implemented |
| `generateExplanation()` | Implemented |
| `evaluateInterviewAnswer()` | Phase 6 |
| `generateDebugScenario()` / `evaluateDebugAnswer()` | Phase 6 |

Phase 6 methods are deliberately absent rather than stubbed — a method that
throws is worse than one that does not exist yet.

## Results are typed, not thrown

```dart
sealed class AiResult<T> { }
final class AiSuccess<T>     extends AiResult<T> { final T value; }
final class AiUnavailable<T> extends AiResult<T> { final AiUnavailableReason reason; }
```

Unavailability is a **normal state** in this app — the quota is finite and the
device is often offline — so callers are forced to handle it at the type level
rather than remembering to catch.

| Reason | Retryable | Shown as |
|---|---|---|
| `quotaExhausted` | no | "Daily AI limit reached" |
| `rateLimited` | yes | "AI is busy right now" |
| `offline` | yes | "You are offline" |
| `safetyBlocked` | no | "That request was blocked" |
| `invalidResponse` | yes | "AI returned unusable content" |
| `notConfigured` | no | "AI is not available" |

## Structured output

Questions are generated against a `responseSchema`, so parsing is reliable:

```dart
Schema.array(items: Schema.object(
  properties: { 'question': Schema.string(), 'shortAnswer': Schema.string(), … },
  optionalProperties: ['interviewAngle', 'subcategory', 'tags'],
))
```

`type`, `category` and `difficulty` are `Schema.enumString`, so the model
cannot invent taxonomy values.

## Validation pipeline

The schema guarantees shape. It cannot guarantee quality:

```
Gemini
  ↓  structured JSON (schema-enforced)
  ↓  QuestionValidator
  │     ├─ length bounds
  │     ├─ must end in "?"
  │     ├─ banned definition openers ("What is …")
  │     ├─ placeholder / meta text
  │     └─ near-duplicate check
  ↓  insert into SQLite
  ↓  feed
```

Rejected items are counted, not retried. Retrying a bad batch spends quota for
a marginal result.

**Duplicate detection** uses shared content-word tokens over the *larger* of
the two token sets, threshold 0.8. Jaccard is the obvious choice and is wrong
here: swapping two words in a short question ("nearly full" → "almost full")
drops Jaccard to ~0.71, letting real rephrasings through. See
`QuestionValidator._similarity`.

## Fallback chain

```
cached generated content   (generated_content_rows)
   ↓ miss
Gemini                     (if enabled, in budget, online)
   ↓ unavailable
local content              (question_rows — seeded, AI, curated)
   ↓
the feed keeps working
```

The `_AiNotice` banner tells the user why new questions stopped arriving
instead of silently repeating old ones.

## Caching is the main cost lever

`generated_content_rows` is keyed `<questionId>::<kind>`. A deep dive costs one
request *ever*; every later view is served on-device and offline. Cache hits
are counted so the ratio is visible.

## What is deliberately not done

- No automatic billing account creation.
- No prompt to "upgrade for more".
- No silent fallback to a paid model or backend.
- No retry storm against a spent quota.

If a feature cannot run inside a free quota, it is disabled or degraded.
