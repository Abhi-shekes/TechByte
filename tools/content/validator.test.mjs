/**
 * Parity tests for the JS port of QuestionValidator.
 *
 * These deliberately mirror test/questions/question_validator_test.dart case
 * for case. Two implementations of one rule set only stay honest if the same
 * fixtures are asserted against both — otherwise the port drifts and content
 * starts passing here while being dropped on-device.
 *
 * Run: node --test   (from tools/content)
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  fingerprint,
  similarity,
  validateCorpus,
  validateQuestion,
} from './validator.mjs';

const base = {
  id: 'q1',
  type: 'why',
  category: 'hardware',
  difficulty: 'medium',
  question: 'Why does a phone slow down when its storage is nearly full?',
  shortAnswer:
    'Flash storage can only write to empty blocks, so a nearly full drive ' +
    'must erase and rewrite blocks before every new write.',
};

const question = (overrides = {}) => ({ ...base, ...overrides });

test('accepts a well-formed question', () => {
  assert.equal(validateQuestion(question()), null);
});

test('rejects definition-style phrasings', () => {
  const banned = [
    'What is RAM?',
    'What is a CPU cache and how does it work?',
    'What are the different types of database index?',
    'Define the CAP theorem in distributed systems?',
  ];
  for (const text of banned) {
    assert.notEqual(
      validateQuestion(question({ question: text })),
      null,
      `should have rejected: ${text}`,
    );
  }
});

test('rejects a question not phrased as a question', () => {
  const result = validateQuestion(
    question({ question: 'Storage fills up and the phone becomes slower.' }),
  );
  assert.equal(result, 'question is not phrased as a question');
});

test('rejects answers that are too short to be useful', () => {
  const result = validateQuestion(question({ shortAnswer: 'It is slow.' }));
  assert.match(result, /short answer too short/);
});

test('rejects a near-duplicate of an existing question', () => {
  const existing = fingerprint(
    'Why does a phone slow down when its storage is nearly full?',
  );
  const result = validateQuestion(
    question({
      question: 'Why does your phone slow down when the storage is almost full?',
    }),
    [existing],
  );
  assert.equal(result, 'near-duplicate of an existing question');
});

test('accepts a genuinely different question about the same topic', () => {
  const existing = fingerprint(
    'Why does a phone slow down when its storage is nearly full?',
  );
  const result = validateQuestion(
    question({
      question:
        'Why do solid state drives need a TRIM command from the operating system?',
    }),
    [existing],
  );
  assert.equal(result, null);
});

test('fingerprint ignores punctuation, case and stop words', () => {
  assert.deepEqual(
    [...fingerprint('Why does the CPU cache exist?')].sort(),
    [...fingerprint('why DOES cpu   cache exist')].sort(),
  );
});

test('similarity divides by the larger set, not the union', () => {
  // The property the Dart comment calls out: a short question inside a much
  // longer one must not score as a duplicate.
  const short = fingerprint('Why is DNS slow?');
  const long = fingerprint(
    'Why is DNS slow when resolving a hostname that has never been cached ' +
    'anywhere in the resolver chain before today?',
  );
  assert.ok(similarity(short, long) < 0.8);
});

test('rejects unknown taxonomy values', () => {
  assert.match(validateQuestion(question({ type: 'trivia' })), /unknown type/);
  assert.match(
    validateQuestion(question({ category: 'quantum' })),
    /unknown category/,
  );
  assert.match(
    validateQuestion(question({ difficulty: 'impossible' })),
    /unknown difficulty/,
  );
});

test('rejects placeholder and meta text', () => {
  assert.equal(
    validateQuestion(question({ shortAnswer: 'As an AI, I cannot verify this claim fully.' })),
    'placeholder or meta text',
  );
});

test('validateCorpus catches duplicate ids and cross-entry duplicates', () => {
  const problems = validateCorpus([
    question({ id: 'a' }),
    question({ id: 'a', question: 'Why do CPUs have more than one cache level?' }),
    question({
      id: 'b',
      question: 'Why does your phone slow down when the storage is almost full?',
    }),
  ]);

  assert.ok(problems.some((p) => p.includes('duplicate id')));
  assert.ok(problems.some((p) => p.includes('near-duplicate')));
});

test('accepts the shipped core pack', async () => {
  // The core pack is the quality bar generated content is judged against, so
  // it has to clear that bar itself — same assertion as the Dart test.
  const { readPack } = await import('./pack.mjs');
  const { fileURLToPath } = await import('node:url');
  const { dirname, resolve } = await import('node:path');

  const here = dirname(fileURLToPath(import.meta.url));
  const pack = await readPack(
    resolve(here, '../../assets/content/pack-core-001.json'),
  );

  assert.ok(pack, 'core pack should exist');
  assert.deepEqual(validateCorpus(pack.questions), []);
});
