# Offline-first

## Principle

The app is **local-first, not offline-tolerant**. SQLite is the source of truth
for the feed. The network adds content; it is never required to read it.

A user who installs TechByte on a plane, never signs in, and never connects
still gets a working feed of 34 curated questions.

## What works offline

| | |
|---|---|
| Browse the feed | Yes — from `question_rows` |
| Reveal answers | Yes — every card is self-contained |
| Saved questions | Yes |
| Search saved | Yes — local string match, no AI |
| Progress and topic familiarity | Yes — computed from local tables |
| Explore categories | Yes |
| Previously opened deep dives | Yes — `generated_content_rows` |
| Theme, settings, onboarding | Yes — SharedPreferences |

## What needs a connection

- Generating new questions
- A deep dive or explanation not already cached
- Signing in for the first time
- Firestore sync

## Why cards are self-contained

Every `Question` carries its answer and all supporting sections. The feed never
has to fetch anything to render a card. That single decision is what makes
offline browsing work without a special case — there is no "offline mode",
because the online path reads from the same place.

Only deep dives and alternate explanations are generated lazily, and both are
cached on first use.

## Fallback chain

```
generated content cache        ← generated_content_rows
        ↓ miss
Gemini                         ← if enabled, in budget, online
        ↓ unavailable
local content pool             ← question_rows (seed + ai + curated)
        ↓
feed continues
```

Nothing in this chain throws. `AiUnavailable` is a value, and the UI renders it
as an explanation rather than an error.

## Honest degradation

When generation stops, `_AiNotice` says so:

> Daily AI limit reached · showing saved questions

This is deliberate. Silently recycling old questions would be a worse
experience than admitting the limit, and running out of free quota is an
expected state in a product designed around free tiers.

## Writes are local-first

Every interaction — seen, revealed, completed, skipped, saved — writes to
SQLite immediately and is dispatched without being awaited on the swipe path.
`question_interactions.synced` marks rows not yet mirrored to Firestore, so
sync can be opportunistic and the app never blocks on the network.

## Seeding

`ensureSeeded()` runs before the first frame. It is a single `COUNT` on the
common path, and idempotent, so it is safe on every launch.

## Not yet implemented

- Firestore sync (the `synced` column exists and is maintained; the uploader
  does not).
- Conflict resolution for multi-device use. Last-write-wins per field is
  probably sufficient given the data, but it has not been designed.
