# Content

## The editorial rule

> Make the user curious **before** giving them the answer.

Every question must pass: *would a technically curious person genuinely want to
know the answer?* If not, it does not ship.

| Weak | Strong |
|---|---|
| What is RAM? | Why can't your phone use storage as fast as RAM? |
| What is DNS? | If every DNS server went offline for an hour, what would break first? |
| What is a CPU cache? | Why doesn't the CPU simply read RAM every time it needs data? |

This is enforced in code. `QuestionValidator` rejects questions opening with
`what is`, `what are`, `define`, and similar, regardless of how good the answer
is.

## Model

```jsonc
{
  "id": "seed_usbc_cables_differ",
  "type": "surprising",           // 10 types
  "category": "hardware",         // 18 categories
  "subcategory": "usb",           // free-form slug
  "difficulty": "easy",
  "question": "…",                // the hook
  "shortAnswer": "…",             // the payoff, 2–3 sentences
  "whyItMatters": "…",
  "realWorldExample": "…",
  "technicalDetails": "…",
  "interviewAngle": "…",          // optional
  "followUpQuestion": "…",        // seeds Go Deeper
  "tags": ["usb-c", "cables"],
  "source": "seed | ai | curated",
  "createdAt": "…", "updatedAt": "…"
}
```

Only `question` and `shortAnswer` are required for a card to render.
`detailSections` returns just the sections that exist, so an empty heading can
never be shown.

`Question.fromJson` is deliberately lenient: unknown enum values fall back to
defaults and whitespace-only fields become null, so content generated against a
newer taxonomy still loads.

## Taxonomy

**Types** — `why`, `how`, `whatHappensIf`, `compare`, `behindTheScenes`,
`mythFact`, `surprising`, `production`, `interview`, `debugging`.

**Categories** — programming, computer science, operating systems, networking,
internet, databases, backend, cloud, devops, AI/ML, hardware, mobile,
cybersecurity, electronics, distributed systems, system design, developer
tools, real-world technology.

Everything persists by string id, never by enum index, so reordering or
inserting values is safe.

## Provenance

| Source | Meaning |
|---|---|
| `seed` | Ships in the APK. Always available, offline, before sign-in. |
| `ai` | Generated on-device via Gemini and cached locally. |
| `curated` | Authored/approved through the admin workflow, synced from Firestore. |

Provenance is tracked so AI content can be purged wholesale if quality
regresses, without touching curated or seed content.

## Bundled content

Content ships as **packs** — JSON files in `assets/content/`, discovered at
runtime by `QuestionPack` and inserted into SQLite on first launch. Adding a
pack is dropping a file in; there is no pubspec or Dart change.

| Pack | Contents |
|---|---|
| `pack-core-001.json` | 34 hand-written questions across 17 categories. |
| `pack-generated-*.json` | Authoring-time output from `tools/content`. |

They exist for three reasons:

1. First launch works instantly — no network, no sign-in.
2. The app stays usable offline and when the AI quota is spent.
3. **The core pack is the quality bar.** Generated content is prompted to match
   its voice and specificity, and judged against it.

Because of (3), a test asserts every bundled question passes the same validator
that gates generated content. The bar has to clear itself.

Content lived in a Dart source file until packs replaced it. The reason was not
aesthetics: content in Dart cannot be written by a tool, cannot be validated in
CI without compiling the app, and is compiled into the binary uncompressed.

## Where content is authored

Generation happens **at authoring time, not on-device** — see
`tools/content/README.md`. The distinction is a scaling one, not a stylistic
one: the free Gemini quota is per Firebase project, while the app's
`dailyRequestBudget` is enforced per install, so on-device bulk generation
cannot survive more than a handful of users. Authoring-time generation is paid
once and shared by every install.

On-device AI remains for what has to be per-user: deep dives, "explain
differently", answer grading, and debug scenarios.

## Quality signals

Tracked per question: times seen, revealed, completed, skipped, saved,
reported. Reported content is excluded from the feed via a `reported` flag —
**not deleted**, so it remains reviewable through the admin workflow.

## Current-technology content

Optional, and not implemented. When added it must carry source and date,
summarise rather than copy, attribute properly, and expire. The majority of the
feed stays evergreen — TechByte is not a news app.
