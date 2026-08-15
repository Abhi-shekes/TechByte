import 'dart:math';

import '../../../app/config/feed_config.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';

/// Inputs the selector needs about the current user.
class FeedContext {
  const FeedContext({
    required this.topicProgress,
    this.preferredCategories = const {},
    this.level = ExperienceLevel.intermediate,
    this.goal = LearningGoal.all,
  });

  final Map<Category, TopicProgress> topicProgress;
  final Set<Category> preferredCategories;
  final ExperienceLevel level;
  final LearningGoal goal;
}

/// Picks the next question, given everything currently available locally.
///
/// Pure and synchronous by design: no I/O, no clock beyond what is passed in.
/// That makes the feed's behaviour — the part of the product that is hardest
/// to eyeball and easiest to get subtly wrong — directly unit-testable.
class FeedSelector {
  FeedSelector({FeedConfig? config, Random? random})
    : _config = config ?? const FeedConfig(),
      _random = random ?? Random();

  final FeedConfig _config;
  final Random _random;

  /// Chooses the next question from [pool], or null when nothing is eligible.
  ///
  /// [recentCategories] is the tail of what was just shown, newest last, and is
  /// used only to break up same-category runs.
  QuestionWithState? next({
    required List<QuestionWithState> pool,
    required FeedContext context,
    required Set<String> alreadyQueued,
    List<Category> recentCategories = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final available = pool
        .where((q) => !alreadyQueued.contains(q.question.id))
        .toList(growable: false);
    if (available.isEmpty) return null;

    // Build the candidate set per slot once, then weight only the slots that
    // actually have something in them.
    final buckets = <FeedSlot, List<QuestionWithState>>{
      FeedSlot.curiosity: available.where((q) => !q.wasSeen).toList(),
      FeedSlot.weakTopics: _weakTopicCandidates(
        available,
        context,
      ).toList(growable: false),
      FeedSlot.review: available
          .where((q) => _isReviewEligible(q, clock))
          .toList(growable: false),
      FeedSlot.interview: available
          .where(
            (q) =>
                !q.wasSeen &&
                (q.question.type == QuestionType.interview ||
                    q.question.type == QuestionType.debugging ||
                    q.question.type == QuestionType.production),
          )
          .toList(growable: false),
      FeedSlot.newTopics: _newTopicCandidates(
        available,
        context,
      ).toList(growable: false),
    };

    final slot = _pickSlot(buckets);
    // Every slot empty means the user has seen everything; fall back to the
    // least recently seen question rather than showing nothing.
    final candidates = slot == null
        ? _leastRecentlySeen(available)
        : buckets[slot]!;

    return _pickAvoidingRuns(candidates, recentCategories);
  }

  /// Categories the user completes least, weighted toward the weakest.
  Iterable<QuestionWithState> _weakTopicCandidates(
    List<QuestionWithState> pool,
    FeedContext context,
  ) {
    final engaged =
        context.topicProgress.entries.where((e) => e.value.seen >= 3).toList()
          ..sort((a, b) => a.value.familiarity.compareTo(b.value.familiarity));

    if (engaged.isEmpty) return const [];

    final weakest = engaged
        .take((engaged.length / 2).ceil())
        .map((e) => e.key)
        .toSet();

    return pool.where((q) => weakest.contains(q.question.category));
  }

  /// Categories barely touched yet — the discovery slot.
  Iterable<QuestionWithState> _newTopicCandidates(
    List<QuestionWithState> pool,
    FeedContext context,
  ) {
    return pool.where((q) {
      if (q.wasSeen) return false;
      final progress = context.topicProgress[q.question.category];
      return progress == null || progress.seen < 3;
    });
  }

  bool _isReviewEligible(QuestionWithState q, DateTime now) {
    final interaction = q.interaction;
    if (interaction == null || interaction.timesSeen == 0) return false;

    // Explicitly scheduled review wins when the spaced-repetition layer has
    // set a due date.
    final due = interaction.reviewDueAt;
    if (due != null) return !due.isAfter(now);

    // Otherwise, anything skipped or left incomplete becomes eligible once it
    // has had time to go cold.
    if (interaction.completed) return false;
    final lastSeen = interaction.lastSeenAt;
    if (lastSeen == null) return false;
    return now.difference(lastSeen) >= _config.reviewEligibleAfter;
  }

  /// Weighted choice over slots that have candidates.
  FeedSlot? _pickSlot(Map<FeedSlot, List<QuestionWithState>> buckets) {
    final live = <FeedSlot, double>{};
    for (final entry in buckets.entries) {
      if (entry.value.isEmpty) continue;
      final weight = _config.weights[entry.key] ?? 0;
      if (weight > 0) live[entry.key] = weight;
    }
    if (live.isEmpty) return null;

    final total = live.values.reduce((a, b) => a + b);
    var roll = _random.nextDouble() * total;
    for (final entry in live.entries) {
      roll -= entry.value;
      if (roll <= 0) return entry.key;
    }
    return live.keys.last;
  }

  /// Picks from [candidates], preferring one that breaks a same-category run.
  QuestionWithState? _pickAvoidingRuns(
    List<QuestionWithState> candidates,
    List<Category> recentCategories,
  ) {
    if (candidates.isEmpty) return null;

    final runCategory = _currentRunCategory(recentCategories);
    if (runCategory != null) {
      final different = candidates
          .where((q) => q.question.category != runCategory)
          .toList(growable: false);
      if (different.isNotEmpty) {
        return different[_random.nextInt(different.length)];
      }
    }
    return candidates[_random.nextInt(candidates.length)];
  }

  /// The category to avoid, if the last few cards were all the same one.
  Category? _currentRunCategory(List<Category> recent) {
    final limit = _config.maxConsecutiveSameCategory;
    if (recent.length < limit) return null;

    final tail = recent.sublist(recent.length - limit);
    final first = tail.first;
    return tail.every((c) => c == first) ? first : null;
  }

  List<QuestionWithState> _leastRecentlySeen(List<QuestionWithState> pool) {
    final sorted = [...pool]
      ..sort((a, b) {
        final aSeen = a.interaction?.lastSeenAt;
        final bSeen = b.interaction?.lastSeenAt;
        if (aSeen == null && bSeen == null) return 0;
        if (aSeen == null) return -1;
        if (bSeen == null) return 1;
        return aSeen.compareTo(bSeen);
      });
    return sorted.take(10).toList(growable: false);
  }
}
