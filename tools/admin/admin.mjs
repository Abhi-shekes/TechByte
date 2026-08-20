#!/usr/bin/env node
/**
 * TechByte content admin CLI.
 *
 * Runs against Firebase Admin, so it bypasses security rules by design — this
 * is the privileged path the rules exist to keep clients away from. It is a
 * local tool, not a service: nothing here is deployed or exposed.
 */
import { randomUUID } from 'node:crypto';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

// One implementation of the content rules, shared with the generator and with
// CI. This file used to carry its own looser copy, which meant content could
// pass `validate` here and still be dropped by the stricter on-device
// validator after shipping.
import { readPack } from '../content/pack.mjs';
import { validateCorpus } from '../content/validator.mjs';

const PROJECT_ID = 'techbyte-app';

initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

async function loadAndValidate(path) {
  const pack = await readPack(path);
  if (!pack) throw new Error(`${path}: not found`);

  // Ids are assigned at publish time for hand-written files, so an entry
  // without one is not an error here — only a duplicate is.
  const questions = pack.questions;
  const problems = validateCorpus(questions).filter(
    (p) => !p.endsWith('empty id'),
  );

  return { questions, problems };
}

const commands = {
  async validate(path) {
    const { questions, problems } = await loadAndValidate(path);
    if (problems.length) {
      console.error(`✗ ${problems.length} problem(s):`);
      problems.forEach((p) => console.error('  ' + p));
      process.exitCode = 1;
      return;
    }
    console.log(`✓ ${questions.length} question(s) valid.`);
  },

  async publish(path) {
    const { questions, problems } = await loadAndValidate(path);
    if (problems.length) {
      console.error(`✗ Refusing to publish — ${problems.length} problem(s):`);
      problems.forEach((p) => console.error('  ' + p));
      process.exitCode = 1;
      return;
    }

    // Batched: 500 ops is the Firestore limit, and chunking keeps a large
    // import atomic per chunk rather than one write per question.
    const CHUNK = 400;
    for (let i = 0; i < questions.length; i += CHUNK) {
      const batch = db.batch();
      for (const q of questions.slice(i, i + CHUNK)) {
        const id = q.id ?? `curated_${randomUUID()}`;
        batch.set(db.collection('questions').doc(id), {
          ...q,
          id,
          difficulty: q.difficulty ?? 'medium',
          tags: q.tags ?? [],
          source: 'curated',
          status: 'published',
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      await batch.commit();
    }
    console.log(`✓ Published ${questions.length} question(s).`);
  },

  async list(...args) {
    const status = args.includes('--status')
      ? args[args.indexOf('--status') + 1] : 'published';
    const limit = args.includes('--limit')
      ? Number(args[args.indexOf('--limit') + 1]) : 20;

    const snap = await db.collection('questions')
      .where('status', '==', status).limit(limit).get();

    if (snap.empty) { console.log(`No questions with status "${status}".`); return; }
    snap.forEach((doc) => {
      const d = doc.data();
      console.log(`${doc.id}  [${d.category}]  ${d.question}`);
    });
    console.log(`\n${snap.size} shown.`);
  },

  async unpublish(id) {
    if (!id) throw new Error('Usage: unpublish <questionId>');
    await db.collection('questions').doc(id).update({
      status: 'unpublished',
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.log(`✓ Unpublished ${id} (not deleted — still reviewable).`);
  },

  async reports() {
    const snap = await db.collection('reports').orderBy('createdAt', 'desc')
      .limit(50).get();
    if (snap.empty) { console.log('No reports.'); return; }
    snap.forEach((doc) => {
      const d = doc.data();
      console.log(`${d.questionId}  ${d.reason ?? '(no reason)'}`);
    });
  },

  async 'grant-admin'(email) {
    if (!email) throw new Error('Usage: grant-admin <email>');
    const user = await getAuth().getUserByEmail(email);
    await getAuth().setCustomUserClaims(user.uid, { admin: true });
    console.log(`✓ ${email} is now an admin.`);
    console.log('They must sign out and back in for the claim to take effect.');
  },
};

const [command, ...args] = process.argv.slice(2);
const handler = commands[command];

if (!handler) {
  console.error(`Unknown command: ${command ?? '(none)'}`);
  console.error(`Available: ${Object.keys(commands).join(', ')}`);
  process.exit(1);
}

handler(...args).catch((error) => {
  console.error(`✗ ${error.message}`);
  process.exit(1);
});
