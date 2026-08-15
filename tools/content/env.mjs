/**
 * Loads the project-root `.env` so the tools work without a wrapper script.
 *
 * `.env` is gitignored and holds a real credential. Nothing here ever prints
 * the value — errors report the variable name only.
 */
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const PROJECT_ROOT = resolve(HERE, '../..');

/** Names accepted for the Gemini key, in priority order. */
const KEY_NAMES = ['GEMINI_API_KEY', 'GOOGLE_API_KEY', 'API_KEY'];

/**
 * Reads `.env` into `process.env` without overwriting anything already set,
 * so an explicit `GEMINI_API_KEY=… node generate.mjs` still wins.
 */
export function loadEnv() {
  const path = resolve(PROJECT_ROOT, '.env');
  if (!existsSync(path)) return;

  // Node's own parser, available since 20.12 — no dependency, and it handles
  // the quoting rules consistently with `node --env-file`.
  if (typeof process.loadEnvFile === 'function') {
    const before = { ...process.env };
    process.loadEnvFile(path);
    // Restore anything the file shadowed: the shell is the higher authority.
    for (const [key, value] of Object.entries(before)) process.env[key] = value;
  }
}

/**
 * Returns the Gemini API key, or throws with instructions.
 *
 * Several names are accepted because the key Google hands you is presented as
 * a bare `API_KEY` in their quickstart, and renaming a working credential to
 * satisfy a tool is a bad trade.
 */
export function requireApiKey() {
  loadEnv();

  for (const name of KEY_NAMES) {
    const value = process.env[name]?.trim();
    if (value) return { key: value, name };
  }

  throw new Error(
    `No Gemini API key found.\n` +
    `  Looked for ${KEY_NAMES.join(', ')} in the environment and in .env\n` +
    `  Get a free key: https://aistudio.google.com/apikey\n` +
    `  Then add to .env (already gitignored):  API_KEY=...`,
  );
}
