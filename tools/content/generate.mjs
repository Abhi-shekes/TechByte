#!/usr/bin/env node
/**
 * Bulk content authoring for TechByte.
 *
 * The premise: content is an authoring cost paid once, not a runtime cost paid
 * per user. Generating on a laptop and shipping the result means every install
 * gets the whole corpus for free, offline, with no per-device quota and — the
 * part that matters most — with a human able to read it before it ships.
 *
 * Generating the same content on-device instead costs one shared project quota
 * divided by every user, and nobody ever reviews it.
 *
 * Usage:
 *   export GEMINI_API_KEY=...        # https://aistudio.google.com/apikey
 *   node generate.mjs --count 200
 *   node generate.mjs --count 500 --categories networking,databases
 *   node generate.mjs --dry-run      # print one prompt, call nothing
 *
 * The output pack is rewritten after every accepted batch, so the run is
 * interruptible and resumable: re-running tops the same pack up rather than
 * starting over, and duplicate detection spans everything already written.
 */
import { readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { requireApiKey } from './env.mjs';
import { GeminiClient, QUESTION_SCHEMA, QuotaExhausted } from './gemini.mjs';
import { SYSTEM_INSTRUCTION, questionGeneration } from './prompts.mjs';
import { categoryCounts, contentId, readPack, writePack } from './pack.mjs';
import { CATEGORIES, fingerprint, validateQuestion } from './validator.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONTENT_DIR = resolve(HERE, '../../assets/content');

function parseArgs(argv) {
  const args = {
    count: 100,
    batch: 8,
    out: join(CONTENT_DIR, 'pack-generated-001.json'),
    categories: CATEGORIES,
    model: 'gemini-2.5-flash',
    rpm: 10,
    temperature: 0.9,
    difficulties: ['easy', 'medium', 'hard'],
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined) throw new Error(`${arg} needs a value`);
      return value;
    };

    switch (arg) {
      case '--count': args.count = Number(next()); break;
      case '--batch': args.batch = Number(next()); break;
      case '--out': args.out = resolve(next()); break;
      case '--model': args.model = next(); break;
      case '--rpm': args.rpm = Number(next()); break;
      case '--temperature': args.temperature = Number(next()); break;
      case '--categories': args.categories = next().split(',').map((c) => c.trim()); break;
      case '--difficulties': args.difficulties = next().split(',').map((d) => d.trim()); break;
      case '--dry-run': args.dryRun = true; break;
      case '--help': case '-h': args.help = true; break;
      default: throw new Error(`Unknown argument: ${arg}`);
    }
  }

  const unknown = args.categories.filter((c) => !CATEGORIES.includes(c));
  if (unknown.length) {
    throw new Error(
      `Unknown categor${unknown.length > 1 ? 'ies' : 'y'}: ${unknown.join(', ')}\n` +
      `Valid: ${CATEGORIES.join(', ')}`,
    );
  }

  return args;
}

const HELP = `
TechByte bulk content generator.

  --count N          Questions to add before stopping        (default 100)
  --batch N          Questions requested per API call        (default 8)
  --out PATH         Pack to write/extend                    (default assets/content/pack-generated-001.json)
  --categories a,b   Restrict to these category ids          (default: all 18)
  --difficulties a,b Difficulty spread to ask for            (default easy,medium,hard)
  --model NAME       Gemini model                            (default gemini-2.5-flash)
  --rpm N            Local pacing, requests per minute       (default 10)
  --temperature N    Sampling temperature                    (default 0.9)
  --dry-run          Print one prompt and exit, calling nothing
  --help             This

Requires GEMINI_API_KEY. Free key: https://aistudio.google.com/apikey
`.trim();

/**
 * Loads every pack in assets/content plus the output pack.
 *
 * Duplicate detection has to span the whole corpus, not just the pack being
 * written — otherwise generating a second pack cheerfully reproduces the
 * first one.
 */
async function loadCorpus(outPath) {
  const seen = new Map();
  let files = [];
  try {
    files = (await readdir(CONTENT_DIR))
      .filter((f) => f.startsWith('pack-') && f.endsWith('.json'))
      .map((f) => join(CONTENT_DIR, f));
  } catch {
    // No content directory yet; the output pack is the whole corpus.
  }
  if (!files.includes(outPath)) files.push(outPath);

  const corpus = [];
  for (const file of files) {
    const pack = await readPack(file);
    if (!pack) continue;
    for (const q of pack.questions) {
      if (seen.has(q.id)) continue;
      seen.set(q.id, true);
      corpus.push({ ...q, _file: file });
    }
  }
  return corpus;
}

/**
 * Picks the category furthest behind, so the corpus balances as it grows.
 *
 * [failures] is added to the real count purely for this choice. A category the
 * model keeps refusing must stop being picked, or the run spins on it forever
 * — but folding those failures into the real counts would make the tool
 * believe a category has content it does not, and skew balancing for the rest
 * of the run.
 */
function nextCategory(categories, counts, failures) {
  let best = categories[0];
  let bestCount = Infinity;
  for (const category of categories) {
    const count = (counts.get(category) ?? 0) + (failures.get(category) ?? 0);
    if (count < bestCount) {
      best = category;
      bestCount = count;
    }
  }
  return best;
}

/** A few hand-written questions to anchor the voice. */
function pickExamples(corpus, count = 3) {
  const handWritten = corpus.filter((q) => q.id?.startsWith('seed_'));
  const pool = handWritten.length ? handWritten : corpus;
  const shuffled = [...pool].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, count).map((q) => q.question);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(HELP);
    return;
  }

  const corpus = await loadCorpus(args.out);
  const outPack = (await readPack(args.out)) ?? {
    packId: 'generated-001',
    description: 'Generated at authoring time, validated and reviewed before shipping.',
    questions: [],
  };

  // Fingerprints of the entire corpus, extended as the run accepts questions.
  const fingerprints = corpus.map((q) => fingerprint(q.question));
  const byCategory = categoryCounts(corpus);
  const existingIds = new Set(corpus.map((q) => q.id));

  console.log(`Corpus: ${corpus.length} question(s) across ${byCategory.size} categor(ies)`);
  console.log(`Target: +${args.count} into ${args.out}\n`);

  if (args.dryRun) {
    const category = nextCategory(args.categories, byCategory);
    console.log(questionGeneration({
      count: args.batch,
      category,
      avoidQuestions: corpus.filter((q) => q.category === category).map((q) => q.question),
      difficulties: args.difficulties,
      exampleQuestions: pickExamples(corpus),
    }));
    return;
  }

  const { key, name } = requireApiKey();
  console.log(`Using ${name} from the environment, model ${args.model}\n`);

  const client = new GeminiClient({
    apiKey: key,
    model: args.model,
    rpm: args.rpm,
    temperature: args.temperature,
  });

  let accepted = 0;
  let rejected = 0;
  const rejectionReasons = new Map();
  const requestFailures = new Map();
  const attemptsByCategory = new Map();
  let stopping = false;

  process.on('SIGINT', () => {
    if (stopping) process.exit(130);
    stopping = true;
    console.log('\nFinishing the current batch, then stopping…');
  });

  while (accepted < args.count && !stopping) {
    const category = nextCategory(args.categories, byCategory, attemptsByCategory);
    const inCategory = corpus.filter((q) => q.category === category);
    const remaining = args.count - accepted;
    const batchSize = Math.min(args.batch, Math.max(remaining, 1));

    process.stdout.write(
      `[${accepted}/${args.count}] ${category} (has ${inCategory.length}) … `,
    );

    let candidates;
    try {
      candidates = await client.generateJson({
        systemInstruction: SYSTEM_INSTRUCTION,
        prompt: questionGeneration({
          count: batchSize,
          category,
          avoidQuestions: inCategory.map((q) => q.question),
          difficulties: args.difficulties,
          exampleQuestions: pickExamples(corpus),
        }),
        schema: QUESTION_SCHEMA,
      });
    } catch (error) {
      if (error instanceof QuotaExhausted) {
        console.log('\n');
        console.error(`✗ ${error.message}`);
        break;
      }
      // First line only: a 503 body is six lines of JSON, and the run prints
      // one of these per failure.
      const summary = error.message.split('\n')[0].slice(0, 120);
      console.log(`failed: ${summary}`);
      requestFailures.set(summary, (requestFailures.get(summary) ?? 0) + 1);
      attemptsByCategory.set(category, (attemptsByCategory.get(category) ?? 0) + 1);
      continue;
    }

    if (!Array.isArray(candidates)) {
      console.log('failed: expected an array');
      continue;
    }

    let batchAccepted = 0;
    for (const candidate of candidates) {
      const reason = validateQuestion(candidate, fingerprints);
      if (reason) {
        rejected++;
        rejectionReasons.set(reason, (rejectionReasons.get(reason) ?? 0) + 1);
        continue;
      }

      const id = contentId(candidate.question);
      if (existingIds.has(id)) {
        rejected++;
        rejectionReasons.set('exact duplicate', (rejectionReasons.get('exact duplicate') ?? 0) + 1);
        continue;
      }

      // The model is told which category to use, but is not trusted to obey;
      // a stray one would quietly unbalance the corpus.
      const question = { ...candidate, id, category };

      outPack.questions.push(question);
      corpus.push(question);
      existingIds.add(id);
      fingerprints.push(fingerprint(question.question));
      byCategory.set(category, (byCategory.get(category) ?? 0) + 1);
      accepted++;
      batchAccepted++;

      if (accepted >= args.count) break;
    }

    console.log(`+${batchAccepted}/${candidates.length}`);

    // Written after every batch: an interrupted run keeps everything it earned.
    if (batchAccepted > 0) await writePack(args.out, outPack);
  }

  await writePack(args.out, outPack);

  const attempted = accepted + rejected;
  console.log(`\n${'─'.repeat(56)}`);
  console.log(`Accepted   ${accepted}`);
  console.log(`Rejected   ${rejected}${attempted ? ` (${Math.round((rejected / attempted) * 100)}%)` : ''}`);
  console.log(`Requests   ${client.requestCount}`);
  console.log(`Tokens     ${client.tokensIn} in / ${client.tokensOut} out`);
  console.log(`Pack       ${args.out} — ${outPack.questions.length} question(s)`);

  if (rejectionReasons.size) {
    console.log('\nRejections by reason:');
    for (const [reason, count] of [...rejectionReasons].sort((a, b) => b[1] - a[1])) {
      console.log(`  ${String(count).padStart(4)}  ${reason}`);
    }
  }

  if (requestFailures.size) {
    console.log('\nRequest failures (retried, then skipped):');
    for (const [reason, count] of [...requestFailures].sort((a, b) => b[1] - a[1])) {
      console.log(`  ${String(count).padStart(4)}  ${reason}`);
    }
  }

  const finalCounts = [...categoryCounts(corpus)].sort((a, b) => b[1] - a[1]);
  console.log('\nCorpus by category:');
  for (const [category, count] of finalCounts) {
    console.log(`  ${String(count).padStart(4)}  ${category}`);
  }
}

main().catch((error) => {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
});
