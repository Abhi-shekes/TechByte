/**
 * Reading and writing content packs.
 *
 * A pack is the unit of content shipped to the app: a JSON object with a
 * little metadata and an array of questions. Packs are plain, uncompressed
 * JSON on purpose — the APK compresses assets already and HTTP compresses
 * transfers already, so gzipping here would buy nothing and cost readability
 * in diffs and in a crash log.
 */
import { createHash } from 'node:crypto';
import { readFile, writeFile, rename } from 'node:fs/promises';

export const FORMAT_VERSION = 1;

/**
 * Field order in emitted JSON. Stable so that regenerating a pack produces a
 * reviewable diff rather than a reshuffle of every line.
 */
const FIELD_ORDER = [
  'id', 'type', 'category', 'subcategory', 'difficulty', 'question',
  'shortAnswer', 'whyItMatters', 'realWorldExample', 'technicalDetails',
  'interviewAngle', 'followUpQuestion', 'tags',
];

/**
 * A content-derived id, so the same question always gets the same id no matter
 * how many times generation runs. That makes the generator idempotent and
 * makes an accidental double-import a no-op rather than a duplicate.
 *
 * The trade-off, stated plainly: editing a question's text changes its id, so
 * a user's interaction row for it is orphaned. That is the right default for
 * generated content — a materially reworded question is a different question —
 * but it means hand-edits to shipped packs should keep the original id.
 */
export function contentId(question, prefix = 'gen') {
  const normalised = String(question).trim().toLowerCase().replace(/\s+/g, ' ');
  const hash = createHash('sha256').update(normalised).digest('hex');
  return `${prefix}_${hash.slice(0, 16)}`;
}

/** Strips nulls/empties and applies the canonical field order. */
export function normaliseQuestion(q) {
  const ordered = {};
  for (const key of FIELD_ORDER) {
    const value = q[key];
    if (value === null || value === undefined) continue;
    if (typeof value === 'string' && !value.trim()) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    ordered[key] = typeof value === 'string' ? value.trim() : value;
  }
  return ordered;
}

/**
 * Reads a pack. Tolerates a bare array so the hand-written content files the
 * admin CLI already accepts keep working unchanged.
 */
export async function readPack(path) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw new Error(`${path}: ${error.message}`);
  }

  if (Array.isArray(parsed)) {
    return { formatVersion: FORMAT_VERSION, packId: null, questions: parsed };
  }
  if (!Array.isArray(parsed?.questions)) {
    throw new Error(`${path}: expected a JSON array or an object with "questions"`);
  }
  return parsed;
}

/**
 * Writes a pack atomically.
 *
 * Via a temp file and rename because the generator rewrites the pack after
 * every accepted batch: a crash mid-write must not leave a truncated corpus
 * where a resumable one used to be.
 */
export async function writePack(path, pack) {
  const body = {
    formatVersion: FORMAT_VERSION,
    packId: pack.packId,
    ...(pack.description ? { description: pack.description } : {}),
    generatedAt: new Date().toISOString(),
    count: pack.questions.length,
    questions: pack.questions.map(normaliseQuestion),
  };

  const temp = `${path}.tmp`;
  await writeFile(temp, `${JSON.stringify(body, null, 2)}\n`, 'utf8');
  await rename(temp, path);
}

/** Per-category counts, used for balancing and for the run summary. */
export function categoryCounts(questions) {
  const counts = new Map();
  for (const q of questions) {
    counts.set(q.category, (counts.get(q.category) ?? 0) + 1);
  }
  return counts;
}
