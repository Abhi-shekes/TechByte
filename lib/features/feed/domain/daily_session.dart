import 'dart:math';

import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';

/// Today's fixed set of questions.
///
/// The daily session is deliberately *not* the feed. The feed is endless and
/// unpredictable; this is a bounded, finishable thing with a visible end — the
/// difference between browsing and completing something.
class DailySession {
  const DailySession({
    required this.date,
    required this.questionIds,
    required this.completedIds,
  });

  /// Local date this session belongs to, normalised to midnight.
  final DateTime date;

  final List<String> questionIds;
  final Set<String> completedIds;

  int get total => questionIds.length;
  int get completed => questionIds.where(completedIds.contains).length;
  bool get isComplete => total > 0 && completed >= total;
  double get progress => total == 0 ? 0 : completed / total;

  /// Rough reading time, at about 45 seconds per question.
  int get estimatedMinutes => ((total * 45) / 60).ceil();

  DailySession copyWith({Set<String>? completedIds}) => DailySession(
    date: date,
    questionIds: questionIds,
    completedIds: completedIds ?? this.completedIds,
  );
}

/// Builds the daily set.
///
/// Deterministic for a given date: the seed comes from the date itself, so
/// reopening the app mid-session shows the same ten questions rather than
/// silently reshuffling them. That determinism is the whole reason this is a
/// separate builder rather than ten draws from [FeedSelector].
abstract final class DailySessionBuilder {
  static DateTime normalise(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// Picks [count] questions for [date], spread across categories.
  ///
  /// Unseen questions are strongly preferred, but the session is padded from
  /// seen ones rather than returned short — "Today's Tech 10" showing four
  /// items would read as a bug.
  static DailySession build({
    required DateTime date,
    required List<QuestionWithState> pool,
    int count = 10,
    Set<String> completedIds = const {},
  }) {
    final day = normalise(date);
    if (pool.isEmpty) {
      return DailySession(
        date: day,
        questionIds: const [],
        completedIds: completedIds,
      );
    }

    // Same date → same seed → same questions, on any launch.
    final random = Random(
      day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay,
    );

    final unseen = pool.where((q) => !q.wasSeen).toList()..shuffle(random);
    final seen = pool.where((q) => q.wasSeen).toList()..shuffle(random);

    final picked = <QuestionWithState>[];
    final usedCategories = <Category>{};

    // First pass: one per category, so the set feels varied by construction
    // rather than by luck.
    for (final candidate in unseen) {
      if (picked.length >= count) break;
      if (usedCategories.add(candidate.question.category)) {
        picked.add(candidate);
      }
    }

    // Then fill from whatever is left, unseen first.
    for (final candidate in [...unseen, ...seen]) {
      if (picked.length >= count) break;
      if (picked.any((p) => p.question.id == candidate.question.id)) continue;
      picked.add(candidate);
    }

    return DailySession(
      date: day,
      questionIds: picked.map((p) => p.question.id).toList(growable: false),
      completedIds: completedIds,
    );
  }
}
