/**
 * Minimal Gemini REST client for authoring-time generation.
 *
 * No SDK on purpose: Node 20+ has `fetch`, and one file of plain HTTP is
 * easier to reason about than a dependency tree for a tool that makes exactly
 * one kind of call. It also keeps `tools/content` installable with no
 * `npm install` step at all.
 *
 * This talks to the Gemini Developer API (the free-tier backend), the same one
 * the app uses via `FirebaseAI.googleAI()`. The Vertex backend requires
 * billing and is never referenced here either.
 */
import { TYPES, CATEGORIES, DIFFICULTIES } from './validator.mjs';

const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

/**
 * Structured-output schema, mirroring GeminiService._questionSchema.
 *
 * Constraining the model at the API level is what makes parsing reliable; the
 * validator then handles what a schema cannot express.
 */
export const QUESTION_SCHEMA = {
  type: 'ARRAY',
  items: {
    type: 'OBJECT',
    properties: {
      question: { type: 'STRING' },
      shortAnswer: { type: 'STRING' },
      whyItMatters: { type: 'STRING' },
      realWorldExample: { type: 'STRING' },
      technicalDetails: { type: 'STRING' },
      interviewAngle: { type: 'STRING' },
      followUpQuestion: { type: 'STRING' },
      type: { type: 'STRING', enum: TYPES },
      category: { type: 'STRING', enum: CATEGORIES },
      difficulty: { type: 'STRING', enum: DIFFICULTIES },
      subcategory: { type: 'STRING' },
      tags: { type: 'ARRAY', items: { type: 'STRING' } },
    },
    required: [
      'question', 'shortAnswer', 'whyItMatters', 'realWorldExample',
      'technicalDetails', 'followUpQuestion', 'type', 'category', 'difficulty',
    ],
  },
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Thrown when the daily quota is gone. Distinct because it ends the run. */
export class QuotaExhausted extends Error {
  constructor(message) {
    super(message);
    this.name = 'QuotaExhausted';
  }
}

export class GeminiClient {
  /**
   * @param {object} options
   * @param {string} options.apiKey
   * @param {string} [options.model]
   * @param {number} [options.rpm]  Requests per minute to pace at. The free
   *   tier is rate-limited per minute as well as per day, and pacing locally
   *   is far cheaper than discovering the limit through 429s.
   */
  constructor({ apiKey, model = 'gemini-2.5-flash', rpm = 10, temperature = 0.9, maxRetries = 3 }) {
    if (!apiKey) {
      throw new Error(
        'No API key. Get one free at https://aistudio.google.com/apikey and:\n' +
        '  export GEMINI_API_KEY=...',
      );
    }
    this.apiKey = apiKey;
    this.model = model;
    this.minInterval = rpm > 0 ? 60_000 / rpm : 0;
    this.temperature = temperature;
    this.maxRetries = maxRetries;
    this.lastRequestAt = 0;
    this.requestCount = 0;
    this.tokensIn = 0;
    this.tokensOut = 0;
  }

  async _pace() {
    const wait = this.lastRequestAt + this.minInterval - Date.now();
    if (wait > 0) await sleep(wait);
    this.lastRequestAt = Date.now();
  }

  /**
   * One structured-output request. Returns parsed JSON.
   *
   * Retries transient failures (429, 5xx, network) with exponential backoff.
   * Never retries a hard quota error — hammering a spent quota only burns the
   * budget the pacing above exists to protect.
   */
  async generateJson({ systemInstruction, prompt, schema, maxOutputTokens = 32768 }) {
    const url = `${ENDPOINT}/${this.model}:generateContent`;
    const body = {
      systemInstruction: { parts: [{ text: systemInstruction }] },
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: this.temperature,
        responseMimeType: 'application/json',
        responseSchema: schema,
        maxOutputTokens,
      },
    };

    let lastError;
    for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
      await this._pace();

      let response;
      try {
        response = await fetch(url, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-goog-api-key': this.apiKey,
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(180_000),
        });
      } catch (error) {
        lastError = new Error(`network: ${error.message}`);
        await sleep(this._backoff(attempt));
        continue;
      }

      this.requestCount++;

      if (response.ok) {
        const json = await response.json();
        return this._extract(json);
      }

      const text = await response.text();

      if (response.status === 429) {
        // Per-day exhaustion is terminal; per-minute is just impatience.
        if (/per day|PerDay|daily/i.test(text)) {
          throw new QuotaExhausted(
            'Daily free-tier quota is gone. Re-run tomorrow — the pack file ' +
            'is written after every batch, so nothing is lost.',
          );
        }
        const delay = this._retryDelay(text) ?? this._backoff(attempt);
        process.stderr.write(`  rate limited, waiting ${Math.round(delay / 1000)}s\n`);
        await sleep(delay);
        lastError = new Error(`429: ${text.slice(0, 200)}`);
        continue;
      }

      if (response.status === 400 && /API key/i.test(text)) {
        throw new Error(`Invalid API key. ${text.slice(0, 200)}`);
      }

      if (response.status >= 500) {
        lastError = new Error(`${response.status}: ${text.slice(0, 200)}`);
        // 503 UNAVAILABLE on a popular model means "this model is saturated
        // right now", not "you asked too fast". Retrying in two seconds just
        // burns another request against the same congestion, so these back off
        // harder than a rate limit does.
        const unavailable = response.status === 503;
        await sleep(this._backoff(attempt, { aggressive: unavailable }));
        continue;
      }

      throw new Error(`${response.status}: ${text.slice(0, 400)}`);
    }

    throw lastError ?? new Error('request failed');
  }

  _backoff(attempt, { aggressive = false } = {}) {
    // Exponential with jitter, so parallel runs do not resynchronise.
    const base = aggressive ? 8000 : 2000;
    const ceiling = aggressive ? 120_000 : 60_000;
    return Math.min(2 ** attempt * base, ceiling) + Math.random() * 1000;
  }

  /** Google returns a suggested delay on some 429s; prefer it to guessing. */
  _retryDelay(text) {
    const match = text.match(/"retryDelay"\s*:\s*"(\d+)s"/);
    return match ? (Number(match[1]) + 1) * 1000 : null;
  }

  _extract(json) {
    const usage = json.usageMetadata ?? {};
    this.tokensIn += usage.promptTokenCount ?? 0;
    this.tokensOut += usage.candidatesTokenCount ?? 0;

    const candidate = json.candidates?.[0];
    if (!candidate) {
      const reason = json.promptFeedback?.blockReason ?? 'no candidates';
      throw new Error(`blocked: ${reason}`);
    }
    if (candidate.finishReason === 'SAFETY') throw new Error('blocked: safety');
    if (candidate.finishReason === 'MAX_TOKENS') {
      throw new Error('truncated: raise --max-output-tokens or lower --batch');
    }

    const text = (candidate.content?.parts ?? [])
      .map((part) => part.text ?? '')
      .join('')
      .trim();

    if (!text) throw new Error('empty response body');

    // Tolerate fenced blocks, which models still emit occasionally despite a
    // JSON response mime type.
    const cleaned = text.startsWith('```')
      ? text.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '').trim()
      : text;

    try {
      return JSON.parse(cleaned);
    } catch (error) {
      throw new Error(`unparseable JSON: ${error.message}`);
    }
  }
}
