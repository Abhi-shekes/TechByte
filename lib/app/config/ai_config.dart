/// Configuration for all AI usage, and the guardrails that keep it free.
///
/// TechByte's hard product constraint is that it must never generate billable
/// usage. Two things enforce that:
///
///   1. [FirebaseAI.googleAI] — the Gemini Developer API — is the only backend
///      ever used. The Vertex AI backend requires a billing account, so it is
///      never constructed anywhere in this codebase.
///   2. The budgets below cut generation off locally *before* the provider's
///      own quota is reached, so the normal state is "we stopped", not "the
///      API rejected us".
///
/// If a free quota is ever reduced or withdrawn, the correct response is to
/// lower these numbers or disable generation — never to enable billing.
abstract final class AiConfig {
  /// Model id. Flash-class models are the ones with a usable free tier and the
  /// latency budget a swipe-driven feed needs.
  static const model = 'gemini-2.5-flash';

  /// Hard local ceiling on generation requests per UTC day.
  ///
  /// Set well below the published free-tier limit so that ordinary use never
  /// approaches it, leaving headroom for retries and for the quota being
  /// shared with anything else on the same project.
  static const dailyRequestBudget = 40;

  /// Questions asked for per generation call. Batching is the main reason the
  /// budget above is sufficient: one request refills the buffer several times
  /// over.
  static const questionsPerGeneration = 8;

  /// A generation run is attempted once and retried at most this many times.
  /// Repeated retries burn quota for a result that is usually not improving.
  static const maxRetries = 1;

  /// Buffer thresholds for the feed. Generation is triggered when the number
  /// of unseen questions left in the local pool falls below [refillThreshold].
  static const refillThreshold = 12;

  /// Requests are abandoned past this point rather than left hanging; the feed
  /// falls back to cached content instead of showing a spinner.
  static const requestTimeout = Duration(seconds: 25);

  /// Sampling temperature. High enough for variety across a long feed, low
  /// enough that technical claims stay conservative.
  static const temperature = 0.9;

  /// Once a quota error is seen, generation is suspended for this long. It
  /// stops the app from hammering an endpoint that is already refusing it.
  static const quotaBackoff = Duration(hours: 6);
}
