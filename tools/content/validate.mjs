#!/usr/bin/env node
/**
 * Validates content packs against the same rules the app applies on-device.
 *
 * Run it in CI over assets/content/*.json. A pack that fails here would not
 * crash the app — the on-device validator would simply drop the bad entries —
 * which is exactly why it needs checking here instead: silent shrinkage of the
 * corpus is the failure mode nobody notices.
 *
 * Usage:
 *   node validate.mjs                       # every pack in assets/content
 *   node validate.mjs path/to/pack.json …
 */
import { readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { categoryCounts, readPack } from './pack.mjs';
import { validateCorpus } from './validator.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CONTENT_DIR = resolve(HERE, '../../assets/content');

async function targets(argv) {
  if (argv.length) return argv.map((p) => resolve(p));
  const files = await readdir(CONTENT_DIR);
  return files
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => join(CONTENT_DIR, f));
}

async function main() {
  const files = await targets(process.argv.slice(2));
  if (!files.length) {
    console.error('No packs found.');
    process.exit(1);
  }

  // Validated as one corpus, not file by file, so a question duplicated across
  // two packs is caught. The app merges them into one table regardless.
  const all = [];
  const origin = new Map();

  for (const file of files) {
    const pack = await readPack(file);
    if (!pack) {
      console.error(`✗ ${file}: not found`);
      process.exit(1);
    }
    for (const q of pack.questions) {
      origin.set(all.length, file);
      all.push(q);
    }
    console.log(`  ${pack.questions.length.toString().padStart(5)}  ${file}`);
  }

  const problems = validateCorpus(all);

  console.log(`\n${all.length} question(s) across ${files.length} pack(s)`);

  if (problems.length) {
    console.error(`\n✗ ${problems.length} problem(s):`);
    for (const problem of problems) console.error(`  ${problem}`);
    process.exit(1);
  }

  const counts = [...categoryCounts(all)].sort((a, b) => b[1] - a[1]);
  console.log('\nBy category:');
  for (const [category, count] of counts) {
    console.log(`  ${String(count).padStart(5)}  ${category}`);
  }

  console.log('\n✓ All packs valid.');
}

main().catch((error) => {
  console.error(`✗ ${error.message}`);
  process.exit(1);
});
