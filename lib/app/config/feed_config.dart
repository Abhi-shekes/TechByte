/// The kinds of slot the feed draws from.
///
/// The feed should feel random without being random: a purely random shuffle
/// produces long runs of the same category and never revisits weak topics.
/// Each swipe picks a slot by weight, then picks a question within that slot.
enum FeedSlot {
  /// Pure curiosity. Anything unseen, any category.
  curiosity,

  /// Categories where completion is lowest — the gaps worth closing.
  weakTopics,

  /// Questions seen before and due for another look.
  review,

  /// Interview-shaped questions.
  interview,

  /// Categories the user has barely touched, to widen coverage.
  newTopics,

  /// Time-sensitive content. Not populated yet: current-technology content is
  /// explicitly optional in the product spec and needs sourcing and expiry
  /// rules before it can ship. Its weight is redistributed until then.
  trending,
}

/// Tunable weighting for feed composition.
///
/// Exposed as a value object rather than constants so it can be overridden in
/// tests and, later, from Remote Config without a release.
class FeedConfig {
  const FeedConfig({
    this.weights = defaultWeights,
    this.bufferSize = 6,
    this.prefetchThreshold = 3,
    this.reviewEligibleAfter = const Duration(days: 1),
    this.maxConsecutiveSameCategory = 2,
  });

  /// Slot weights. Need not sum to 1 — selection normalises over whatever
  /// slots actually have candidates, so an empty slot never wastes a swipe.
  final Map<FeedSlot, double> weights;

  /// Cards kept ready ahead of the current one.
  final int bufferSize;

  /// Refill when fewer than this many remain ahead.
  final int prefetchThreshold;

  /// How long after being seen a question may return in the review slot.
  final Duration reviewEligibleAfter;

  /// Cap on same-category runs, so the feed keeps feeling varied even when one
  /// category dominates the available pool.
  final int maxConsecutiveSameCategory;

  static const defaultWeights = <FeedSlot, double>{
    FeedSlot.curiosity: 0.30,
    FeedSlot.weakTopics: 0.20,
    FeedSlot.review: 0.15,
    FeedSlot.interview: 0.15,
    FeedSlot.newTopics: 0.10,
    FeedSlot.trending: 0.10,
  };

  FeedConfig copyWith({
    Map<FeedSlot, double>? weights,
    int? bufferSize,
    int? prefetchThreshold,
    Duration? reviewEligibleAfter,
    int? maxConsecutiveSameCategory,
  }) {
    return FeedConfig(
      weights: weights ?? this.weights,
      bufferSize: bufferSize ?? this.bufferSize,
      prefetchThreshold: prefetchThreshold ?? this.prefetchThreshold,
      reviewEligibleAfter: reviewEligibleAfter ?? this.reviewEligibleAfter,
      maxConsecutiveSameCategory:
          maxConsecutiveSameCategory ?? this.maxConsecutiveSameCategory,
    );
  }
}

/// Configuration for the daily session ("Today's Tech 10").
abstract final class DailySessionConfig {
  static const questionCount = 10;

  /// Rough reading time shown on the daily card, at ~45s per question.
  static const estimatedMinutes = 8;
}
