# TechByte content pipeline

Bulk question authoring, run on a laptop, shipped in the APK.

## Why this exists

The app can generate questions on-device, and for a while that was the only
source of new content beyond the 34 hand-written ones. That does not survive
launch:

- **The free Gemini quota is per Firebase project, not per device.** The app's
  `AiConfig.dailyRequestBudget = 40` is enforced per install, in local SQLite.
  Ten users sharing one project quota exhaust it; a thousand users never get
  past the first request.
- **Nobody reviews on-device output.** It goes straight into the feed.
- **Every device pays again for the same question.** Content generated on one
  phone is invisible to every other phone.

Generating at authoring time inverts all three. One run produces content every
install gets — offline, instantly, against no runtime quota — and a human can
read it before it ships.

On-device AI stays for what genuinely has to be per-user: deep dives, "explain
differently", answer grading, debug scenarios.

## Requirements

Node 20+. **No dependencies, no `npm install`.**

The key is read from the project-root `.env` (already gitignored) or the
environment. `GEMINI_API_KEY`, `GOOGLE_API_KEY` and `API_KEY` are all accepted,
in that order — the last because that is the name Google's own quickstart
hands you, and renaming a working credential to satisfy a tool is a bad trade.

```bash
# .env at the project root
API_KEY=...        # free key: https://aistudio.google.com/apikey
```

An explicitly exported variable beats the file, so a one-off key can be passed
inline without editing anything.

That key is for the Gemini Developer API — the same no-cost backend the app
uses via `FirebaseAI.googleAI()`. Vertex AI requires billing and is never used
here either.

## Choosing a model

`--model` defaults to `gemini-2.5-flash`, matching `AiConfig.model`. The
authoring tool does not have to match the app, though, and for a one-time job
where output is reviewed anyway, a stronger model is usually worth it.

To see what a key can actually reach:

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
  -H "x-goog-api-key: $API_KEY" | grep '"name"'
```

Two things to know before switching:

- **Newer flash models are frequently saturated.** They return
  `503 UNAVAILABLE — "experiencing high demand"`. The client retries with a
  long backoff and the run still completes, but it can spend several requests
  per successful batch. The end-of-run summary counts these separately from
  content rejections so the two are never confused.
- **Pin a version, don't use `-latest`.** An alias that silently changes model
  mid-corpus changes the voice mid-corpus, which is the one thing the seed
  content exists to hold steady.

## Generating

```bash
cd tools/content

node generate.mjs --count 200                          # add 200 questions
node generate.mjs --count 500 --categories databases,cloud
node generate.mjs --dry-run                            # print a prompt, call nothing
node generate.mjs --help
```

The run is **interruptible and resumable**. The pack is rewritten after every
accepted batch, so Ctrl-C or a spent daily quota loses nothing — re-running
tops the same pack up rather than starting over.

What it does per batch:

1. Picks the category with the fewest questions so far, so the corpus balances
   as it grows rather than drifting toward whatever the model likes writing.
2. Sends the existing questions in that category as an avoid-list, plus three
   hand-written questions as the voice reference.
3. Requests structured JSON, schema-constrained at the API level.
4. Validates every candidate against `validator.mjs` — the same rules the app
   applies on-device.
5. Assigns a content-derived id, appends, writes the pack.

Rejections are normal and are summarised at the end by reason. A high
`near-duplicate` count means that category is saturated; move on.

### Free-tier pacing

`--rpm 10` paces requests locally. The per-minute limit is worth respecting;
the per-day limit is the one that ends a run, and when it does the tool says so
and exits cleanly rather than burning retries against a spent quota.

At `--batch 8`, a day's free quota is worth well over a thousand questions.
Two or three sessions is a corpus no user will exhaust.

## Validating

```bash
node validate.mjs              # every pack in assets/content
node validate.mjs path/to/pack.json
npm test                       # parity tests for the validator port
```

`validate.mjs` checks all packs **as one corpus**, so a question duplicated
across two packs is caught. Run it in CI: a bad pack does not crash the app,
the on-device validator simply drops the entries — silent shrinkage of the
corpus is exactly the failure nobody notices.

## Pack format

```jsonc
{
  "formatVersion": 1,
  "packId": "core-001",
  "generatedAt": "…",
  "count": 34,
  "questions": [ { "id": "…", "type": "why", "category": "hardware", … } ]
}
```

A bare JSON array is also accepted, so the hand-written files the admin CLI
takes keep working unchanged.

Packs live in `assets/content/` and are discovered at runtime by
`QuestionPack` — adding one is dropping a file in, with no pubspec or Dart
change. Load order is by filename.

| Pack | Contents |
|---|---|
| `pack-core-001.json` | The 34 hand-written questions. The voice and quality bar. |
| `pack-generated-*.json` | Authoring-time output. Reviewable and purgeable wholesale. |

Keeping them separate is deliberate: the hand-written bar stays clean, and
generated content can be deleted and regenerated without touching it.

### Ids

Generated ids are a hash of the question text, so the same question always gets
the same id and re-running can never duplicate an entry.

The trade-off, stated plainly: **editing a question's text changes its id**,
which orphans any user's interaction row for it. That is the right default for
generated content — a materially reworded question is a different question —
but it means hand-edits to a shipped pack should keep the original id.

## Two validators

`validator.mjs` is a line-by-line port of
`lib/features/questions/domain/question_validator.dart`. Two implementations of
one rule set only stay honest if both are tested against the same fixtures, so
`validator.test.mjs` mirrors `test/questions/question_validator_test.dart` case
for case, and both assert that the shipped core pack passes.

If you change a rule, change it in both and add the fixture to both.
