# Feed engine

## Problem

A purely random shuffle feels bad. It produces long runs of the same category,
never revisits topics the user is weak at, and re-shows things at the wrong
time. A fully deterministic curriculum feels worse — it stops being a feed.

The goal is **controlled randomness**: unpredictable card to card, deliberate
in aggregate.

## Slots

Each swipe picks a *slot* by weight, then picks a question within it.

| Slot | Weight | Draws from |
|---|---|---|
| `curiosity` | 30% | Anything unseen |
| `weakTopics` | 20% | Categories with the lowest completion |
| `review` | 15% | Seen before and due again |
| `interview` | 15% | Interview / debugging / production types |
| `newTopics` | 10% | Categories with fewer than 3 seen |
| `trending` | 10% | Not populated yet — see below |

Weights live in `FeedConfig` as a value object, not constants, so they can be
overridden in tests and later driven by Remote Config without a release.

`trending` is deliberately empty. Current-technology content is optional in the
product spec and needs sourcing, attribution and expiry rules before it can
ship. Its weight is redistributed automatically, because **selection normalises
over slots that actually have candidates** — an empty slot never wastes a swipe.

## Selection

```dart
QuestionWithState? next({
  required List<QuestionWithState> pool,
  required FeedContext context,
  required Set<String> alreadyQueued,
  List<Category> recentCategories = const [],
  DateTime? now,
})
```

Pure and synchronous: no I/O, no ambient clock. That is what makes the hardest-
to-eyeball part of the product directly testable, and why `now` is a parameter.

Steps:

1. Drop anything already queued.
2. Build candidate lists per slot.
3. Weighted-random pick among **non-empty** slots.
4. Within the slot, pick randomly, preferring a card that breaks a category run.
5. If every slot is empty, fall back to the least-recently-seen questions.

Step 5 matters: a user who has seen everything must still get a card, not an
empty screen.

## Breaking category runs

`maxConsecutiveSameCategory` defaults to 2. If the last two cards shared a
category, the selector prefers a different one — but takes the run rather than
returning nothing when no alternative exists.

## Review eligibility

```
reviewDueAt set   → eligible when due  (spaced repetition, Phase 5)
otherwise         → eligible if not completed and last seen ≥ 1 day ago
```

Completed questions without an explicit schedule do not return. The schema
carries `reviewStage` and `reviewDueAt` already, so enabling full spaced
repetition needs no migration.

## Topic familiarity

`completed / seen`, per category, clamped to 0–1.

Deliberately simple, and labelled "familiarity" rather than a skill score in
both the UI and the code. It measures follow-through on what the user has met,
nothing more.

## Buffering

```
FeedConfig.bufferSize        = 6   // cards kept ahead
FeedConfig.prefetchThreshold = 3
AiConfig.refillThreshold     = 12  // unseen pool size that triggers generation
```

The queue extends synchronously from the in-memory pool on every page change,
so the next cards always exist before they are needed. Generation only tops up
the *pool*; it never gates a swipe.

## Testing

`test/feed/feed_selector_test.dart` — 11 tests using a seeded `Random`, since a
flaky feed test is worse than none:

- never repeats a queued question
- breaks category runs, and tolerates runs it cannot break
- falls back once everything is seen
- honours and withholds scheduled reviews
- interview slot draws only interview-shaped types
- weak-topic slot picks the least-completed category
- repeated independent draws spread across the pool
