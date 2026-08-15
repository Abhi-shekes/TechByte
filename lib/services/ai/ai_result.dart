/// Result of an AI call.
///
/// Deliberately not an exception-based API. Generation being unavailable is a
/// completely normal state in this app — the free quota is finite and the
/// device is often offline — so callers are forced to handle it at the type
/// level rather than remembering to catch.
sealed class AiResult<T> {
  const AiResult();

  /// The value, or null when the call did not succeed.
  T? get valueOrNull => switch (this) {
    AiSuccess<T>(:final value) => value,
    AiUnavailable<T>() => null,
  };

  bool get isSuccess => this is AiSuccess<T>;
}

final class AiSuccess<T> extends AiResult<T> {
  const AiSuccess(this.value);
  final T value;
}

final class AiUnavailable<T> extends AiResult<T> {
  const AiUnavailable(this.reason, {this.detail});

  final AiUnavailableReason reason;
  final String? detail;

  @override
  String toString() =>
      'AiUnavailable(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// Why generation could not produce a result.
///
/// Each value maps to a distinct user-facing behaviour, which is the point of
/// distinguishing them: a quota stop is permanent for the day and should not
/// show a retry button, whereas a network failure should.
enum AiUnavailableReason {
  /// Provider quota or rate limit hit, or the local daily budget is spent.
  /// Not an error condition — the app is working as designed.
  quotaExhausted('Daily AI limit reached'),

  /// Temporary rate limiting. Worth retrying later, not immediately.
  rateLimited('AI is busy right now'),

  /// No usable connection.
  offline('You are offline'),

  /// The model responded, but the content was blocked by safety filters.
  safetyBlocked('That request was blocked'),

  /// The response did not survive schema or content validation.
  invalidResponse('AI returned unusable content'),

  /// Firebase AI is not configured or the user is not signed in.
  notConfigured('AI is not available'),

  /// Anything unclassified.
  unknown('Something went wrong');

  const AiUnavailableReason(this.message);

  /// Short, non-alarming text safe to show directly in the UI.
  final String message;

  /// Whether offering the user a retry makes sense.
  bool get isRetryable => switch (this) {
    AiUnavailableReason.quotaExhausted => false,
    AiUnavailableReason.safetyBlocked => false,
    AiUnavailableReason.notConfigured => false,
    _ => true,
  };
}
