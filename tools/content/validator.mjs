/**
 * Content validation, mirroring lib/features/questions/domain/question_validator.dart.
 *
 * Two implementations of the same rules is a liability, so this file is a
 * deliberate line-by-line port rather than an approximation: the thresholds,
 * the banned openers, the stop-word list and the similarity metric all match
 * the Dart. `test/questions/question_validator_test.dart` covers the Dart side;
 * `npm test` here covers this side against the same fixtures.
 *
 * Why port it at all: rejecting a question at authoring time costs nothing,
 * whereas shipping it means every user downloads content the on-device
 * validator will silently drop.
 */

// Kept in sync with lib/features/questions/domain/question_enums.dart.
export const TYPES = [
  'why', 'how', 'what_happens_if', 'compare', 'behind_the_scenes',
  'myth_fact', 'surprising', 'production', 'interview', 'debugging',
];

export const CATEGORIES = [
  'programming', 'computer_science', 'operating_systems', 'networking',
  'internet', 'databases', 'backend', 'cloud', 'devops', 'ai_ml', 'hardware',
  'mobile', 'cybersecurity', 'electronics', 'distributed_systems',
  'system_design', 'developer_tools', 'real_world_tech',
];

export const DIFFICULTIES = ['easy', 'medium', 'hard', 'expert'];

/** Mirrors QuestionValidator._textbookOpeners. */
const BANNED_OPENERS = [
  'what is a ', 'what is an ', 'what is the ', 'what is ', 'what are ',
  'define ', 'explain the concept of ',
];

/** Mirrors QuestionValidator._stopWords. */
const STOP_WORDS = new Set([
  'the', 'and', 'for', 'are', 'but', 'not', 'you', 'your', 'can', 'does',
  'did', 'why', 'how', 'what', 'when', 'who', 'which', 'that', 'this', 'with',
  'from', 'they', 'them', 'its', 'it', 'is', 'was', 'were', 'be', 'been',
  'have', 'has', 'had', 'would', 'could', 'should', 'will', 'may', 'might',
  'more', 'most', 'some', 'than', 'then', 'there', 'their', 'even', 'also',
  'into', 'over', 'under', 'about', 'actually', 'happens', 'happen',
]);

export const LIMITS = {
  minQuestionLength: 20,
  maxQuestionLength: 220,
  minShortAnswerLength: 40,
  maxShortAnswerLength: 900,
  duplicateThreshold: 0.8,
};

/**
 * Normalised content-word set used for duplicate detection.
 * Mirrors QuestionValidator.fingerprint.
 */
export function fingerprint(text) {
  return new Set(
    String(text ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length > 2 && !STOP_WORDS.has(w)),
  );
}

/**
 * Shared tokens as a fraction of the *larger* question.
 *
 * Not Jaccard — see the Dart comment. Dividing by the larger set is what
 * catches "nearly full" vs "almost full" rephrasings.
 */
export function similarity(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const token of a) if (b.has(token)) intersection++;
  return intersection / Math.max(a.size, b.size);
}

/**
 * Validates one question. Returns `null` if it passes, or a reason string.
 *
 * `existingFingerprints` should be fingerprints of everything already in the
 * corpus, including items accepted earlier in the same run.
 */
export function validateQuestion(q, existingFingerprints = []) {
  const question = String(q?.question ?? '').trim();
  const answer = String(q?.shortAnswer ?? '').trim();

  if (question.length < LIMITS.minQuestionLength) {
    return `question too short (${question.length})`;
  }
  if (question.length > LIMITS.maxQuestionLength) {
    return `question too long (${question.length})`;
  }
  if (!question.endsWith('?')) return 'question is not phrased as a question';

  if (answer.length < LIMITS.minShortAnswerLength) {
    return `short answer too short (${answer.length})`;
  }
  if (answer.length > LIMITS.maxShortAnswerLength) {
    return `short answer too long (${answer.length})`;
  }

  const lower = question.toLowerCase();
  for (const opener of BANNED_OPENERS) {
    if (lower.startsWith(opener)) return `textbook phrasing: "${opener}…"`;
  }

  const lowerAnswer = answer.toLowerCase();
  if (
    lower.includes('as an ai') ||
    lower.includes('lorem ipsum') ||
    lowerAnswer.includes('as an ai') ||
    (answer.includes('...') && answer.length < 80)
  ) {
    return 'placeholder or meta text';
  }

  // Taxonomy. The app's `fromId` is lenient and silently falls back to a
  // default, which is right at runtime and wrong here — a mislabelled category
  // would land in the pack as `programming` and never be noticed.
  if (!TYPES.includes(q?.type)) return `unknown type "${q?.type}"`;
  if (!CATEGORIES.includes(q?.category)) {
    return `unknown category "${q?.category}"`;
  }
  if (q?.difficulty && !DIFFICULTIES.includes(q.difficulty)) {
    return `unknown difficulty "${q.difficulty}"`;
  }

  const fp = fingerprint(question);
  for (const existing of existingFingerprints) {
    if (similarity(fp, existing) >= LIMITS.duplicateThreshold) {
      return 'near-duplicate of an existing question';
    }
  }

  return null;
}

/**
 * Validates a whole corpus, checking each entry against every entry before it.
 *
 * This is the cross-corpus duplicate check the admin CLI could not do while
 * content lived in Firestore one document per question.
 */
export function validateCorpus(questions) {
  const problems = [];
  const fingerprints = [];
  const seenIds = new Set();

  questions.forEach((q, i) => {
    const label = `[${i}] ${q?.id ?? '(no id)'}`;

    if (!q?.id || !String(q.id).trim()) {
      problems.push(`${label}: empty id`);
    } else if (seenIds.has(q.id)) {
      problems.push(`${label}: duplicate id`);
    } else {
      seenIds.add(q.id);
    }

    const reason = validateQuestion(q, fingerprints);
    if (reason) problems.push(`${label}: ${reason}`);
    else fingerprints.push(fingerprint(q.question));
  });

  return problems;
}
