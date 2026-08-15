/// The next review position for a question.
class ReviewSchedule {
  const ReviewSchedule({required this.stage, required this.dueAt});

  /// Index into [SpacedRepetition.intervals].
  final int stage;

  /// When the question becomes eligible for the review slot again.
  final DateTime dueAt;

  @override
  bool operator ==(Object other) =>
      other is ReviewSchedule && other.stage == stage && other.dueAt == dueAt;

  @override
  int get hashCode => Object.hash(stage, dueAt);

  @override
  String toString() => 'ReviewSchedule(stage: $stage, dueAt: $dueAt)';
}

/// Expanding-interval scheduling for questions the user got wrong.
///
/// Deliberately not SM-2. SM-2 tunes an ease factor per item from a graded
/// recall score (0–5), and TechByte only ever learns one bit — right or wrong.
/// Feeding a binary signal into an ease factor produces arithmetic that looks
/// principled and carries no more information than a fixed ladder, so this uses
/// the fixed ladder and stays honest about what it knows.
///
/// ```
/// Day 1   ❌ → back to the start
/// Day 3   ❌ → back to the start
/// Day 7   ✓  → advance
/// Day 21  ✓  → advance
/// ```
abstract final class SpacedRepetition {
  /// Interval for each stage. The last entry repeats for anything beyond it,
  /// so a well-known question settles at a long cadence instead of drifting
  /// out to intervals no one will ever be around for.
  static const intervals = <Duration>[
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 21),
    Duration(days: 60),
  ];

  static int get maxStage => intervals.length - 1;

  /// Schedules the next review after an answer.
  ///
  /// Correct advances one stage; wrong resets to the beginning rather than
  /// stepping back one. A question you have just failed is not "slightly less
  /// known" than one you failed at an earlier stage — the evidence says you do
  /// not know it, and the schedule should say so too.
  static ReviewSchedule next({
    required int currentStage,
    required bool correct,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final stage = correct ? (currentStage + 1).clamp(0, maxStage) : 0;
    return ReviewSchedule(stage: stage, dueAt: clock.add(intervals[stage]));
  }

  /// Schedule for a question skipped or left unrevealed.
  ///
  /// Not a failure — the user may simply have been scrolling. It earns the
  /// shortest interval without touching the stage, so it comes back soon but
  /// does not undo genuine progress.
  static ReviewSchedule afterSkip({required int currentStage, DateTime? now}) {
    final clock = now ?? DateTime.now();
    return ReviewSchedule(
      stage: currentStage,
      dueAt: clock.add(intervals.first),
    );
  }

  /// Whether a question is due, given its schedule.
  static bool isDue(DateTime? dueAt, {DateTime? now}) {
    if (dueAt == null) return false;
    return !dueAt.isAfter(now ?? DateTime.now());
  }
}
