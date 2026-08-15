/**
 * Authoring prompts, mirroring lib/services/ai/prompts/prompt_library.dart.
 *
 * The system instruction is verbatim the app's, because the whole point of the
 * seed corpus is that it defines one voice. Where this diverges is scope: the
 * app generates for one user's stated level and topics, while this generates a
 * corpus everyone shares, so it sweeps categories and difficulties instead of
 * narrowing to a profile.
 */

export const CATEGORY_LABELS = {
  programming: 'Programming',
  computer_science: 'Computer Science',
  operating_systems: 'Operating Systems',
  networking: 'Networking',
  internet: 'Internet',
  databases: 'Databases',
  backend: 'Backend',
  cloud: 'Cloud',
  devops: 'DevOps',
  ai_ml: 'AI/ML',
  hardware: 'Hardware',
  mobile: 'Mobile',
  cybersecurity: 'Cybersecurity',
  electronics: 'Electronics',
  distributed_systems: 'Distributed Systems',
  system_design: 'System Design',
  developer_tools: 'Developer Tools',
  real_world_tech: 'Real-World Technology',
};

export const TYPE_LABELS = {
  why: 'Why',
  how: 'How',
  what_happens_if: 'What happens if',
  compare: 'Compare',
  behind_the_scenes: 'Behind the scenes',
  myth_fact: 'Myth or fact',
  surprising: 'Surprising',
  production: 'Production',
  interview: 'Interview',
  debugging: 'Debugging',
};

/** Verbatim from PromptLibrary.systemInstruction. */
export const SYSTEM_INSTRUCTION = `
You write for TechByte, a short-form technical curiosity app for engineers and technically curious people.

VOICE
- Precise, calm, and concrete. No hype, no exclamation marks, no emoji.
- Never address the reader as "folks", never open with "Ever wondered".
- Assume intelligence. Explain the mechanism, not the vocabulary.

THE ONE RULE
Every question must make a technically curious person genuinely want the answer before they get it.

- BANNED: definition questions. Never "What is RAM?", "What is DNS?", "Explain TCP".
- REQUIRED: questions about mechanism, consequence, surprise or contradiction.

Weak:   What is a CPU cache?
Strong: Why doesn't the CPU simply read RAM every time it needs data?

Weak:   What is DNS?
Strong: If every DNS server went offline for an hour, what would break first?

ACCURACY
- Only state things that are actually true. Prefer omitting a detail to guessing one.
- No invented benchmarks, dates, version numbers or company-specific claims.
- Approximate figures must be clearly approximate ("roughly 200 cycles").

LENGTH
- The short answer must be understandable in under 30 seconds.
- Each supporting section is 1-3 sentences. Never pad to fill a field.
`.trim();

/**
 * Prompt for one authoring batch.
 *
 * A batch targets a single category. Asking for a spread across all eighteen
 * in one call reliably produces four networking questions and one each of
 * everything else; asking for eight within one category produces eight
 * distinct mechanisms, and balance comes from rotating the category instead.
 *
 * `avoidQuestions` carries the existing corpus for this category. The
 * duplicate validator is the backstop; this is the primary defence, since a
 * rejected question has already cost a request.
 */
export function questionGeneration({
  count,
  category,
  avoidQuestions = [],
  difficulties = ['easy', 'medium', 'hard'],
  exampleQuestions = [],
}) {
  const label = CATEGORY_LABELS[category] ?? category;

  const avoidBlock = avoidQuestions.length === 0
    ? 'Nothing has been written for this category yet.'
    : avoidQuestions.slice(-120).map((q) => `- ${q}`).join('\n');

  const exampleBlock = exampleQuestions.length === 0
    ? ''
    : `
THE BAR — these are existing TechByte questions. Match this level of specificity and this voice. Do not reuse their subject matter:
${exampleQuestions.map((q) => `- ${q}`).join('\n')}
`;

  const typeList = Object.entries(TYPE_LABELS)
    .map(([id, name]) => `${id} (${name})`)
    .join(', ');

  return `
Write ${count} new TechByte questions, all in the category "${category}" (${label}).

Every question must use exactly this category id: ${category}
${exampleBlock}
DIFFICULTY — spread the batch across: ${difficulties.join(', ')}.

MIX OF TYPES — vary these across the batch, do not use the same type twice in a row:
${typeList}

COVERAGE — each question must be about a different mechanism. Do not write eight variations on one idea. Range across the whole of ${label}, including the parts that are unglamorous.

ALREADY WRITTEN — do not repeat these, restate them in different words, or cover the same underlying mechanism:
${avoidBlock}

FIELDS
- question: the hook, ending in a question mark. Under 140 characters.
- shortAnswer: the payoff, 2-3 sentences. Must actually answer it, not tease.
- whyItMatters: why this changes how the reader thinks or acts.
- realWorldExample: one concrete, verifiable situation. No invented numbers.
- technicalDetails: the mechanism, for a reader who wants the real explanation.
- interviewAngle: what an interviewer listens for. Omit unless genuinely relevant.
- followUpQuestion: a natural next question. Do not answer it.
- subcategory: a short lowercase slug such as "ssd", "dns", "kafka".
- tags: 2-4 short lowercase slugs.

Return only the JSON array.
`.trim();
}
