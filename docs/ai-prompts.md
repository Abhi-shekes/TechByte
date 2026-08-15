# AI prompts

All prompts live in `lib/services/ai/prompts/prompt_library.dart`. Centralised
because prompts are the main quality lever, need reviewing as a set, and must
stay consistent with the seed content that defines the voice.

## System instruction

Applied to every request. Four blocks:

**Voice** — precise and calm. No hype, no exclamation marks, no emoji, never
"Ever wondered". Explain the mechanism, not the vocabulary.

**The one rule** — the editorial rule, stated as a hard ban with worked
examples:

```
BANNED: definition questions. Never "What is RAM?", "What is DNS?".
REQUIRED: questions about mechanism, consequence, surprise or contradiction.

Weak:   What is a CPU cache?
Strong: Why doesn't the CPU simply read RAM every time it needs data?
```

Without this, models reliably drift toward "What is X?" — which is precisely
the content this product exists to avoid. The contrastive pairs do far more
work than an abstract instruction.

**Accuracy** — only state what is true; prefer omitting a detail to guessing
one; no invented benchmarks, dates, version numbers or company claims;
approximations must read as approximate.

**Length** — short answer understandable in under 30 seconds; supporting
sections 1–3 sentences; never pad to fill a field.

## Question generation

`questionGeneration({count, categories, level, goal, avoidQuestions})`

Constrains category ids, difficulty (from `ExperienceLevel`), and type mixing,
then lists **existing question texts to avoid**.

Passing `avoidQuestions` is the primary defence against repetition. The
duplicate validator is the backstop — by the time it rejects something, the
quota has already been spent.

Output is schema-constrained (see [gemini.md](gemini.md)), so the prompt does
not need to describe JSON formatting beyond "Return only the JSON array".

## Deep dive

`deepDive({question, shortAnswer, technicalDetails})`

Key instructions: do not restate what the reader already knows, and go **one
layer down**, not sideways to a related topic. Sideways drift is the common
failure — asked to go deeper on DNS, a model will happily start explaining
HTTP instead.

Ends by naming what the next layer down would be, which seeds the chain.

## Explain differently

`explanation({question, shortAnswer, style})` with six styles:

| Style | Instruction shape |
|---|---|
| `simple` | Plain language, no jargon, short sentences |
| `eli10` | One familiar comparison; simplified, never wrong |
| `analogy` | One analogy carried through, plus where it breaks down |
| `realWorld` | A situation an engineer would actually encounter |
| `technical` | Rigorous, with mechanism and numbers |
| `interview` | Spoken answer, 60–90 seconds, key insight first |

"Where the analogy breaks down" is deliberate: an analogy without its limits is
how people acquire confident misconceptions.

## Conventions

- Prompts are pure functions returning `String`. No I/O, no service coupling —
  testable in isolation.
- Established content is passed in as context rather than regenerated, so
  variants stay consistent with the answer the user already read.
- Instructions are positive and specific. "Return prose only — no headings, no
  preamble" beats "don't be verbose".

## Phase 6 prompts

`interview_prompt`, `interview_evaluation_prompt`, `debugging_prompt`,
`debug_evaluation_prompt` are specified but not written. Evaluation prompts
will need to grade reasoning, not just conclusions, and return structured
scores — so they will use a response schema like question generation does.
