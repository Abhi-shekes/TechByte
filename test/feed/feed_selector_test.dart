import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/app/config/feed_config.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/feed/domain/feed_selector.dart';
import 'package:techbyte/features/questions/data/question_repository.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';

QuestionWithState _card(
  String id, {
  Category category = Category.networking,
  QuestionType type = QuestionType.why,
  int timesSeen = 0,
  bool completed = false,
  DateTime? lastSeenAt,
  DateTime? reviewDueAt,
}) {
  return QuestionWithState(
    question: Question(
      id: id,
      type: type,
      category: category,
      difficulty: Difficulty.medium,
      question: 'Why does $id behave the way it does?',
      shortAnswer: 'Because of how the underlying mechanism works in practice.',
      source: QuestionSource.seed,
    ),
    interaction: timesSeen == 0 && lastSeenAt == null && reviewDueAt == null
        ? null
        : QuestionInteraction(
            questionId: id,
            timesSeen: timesSeen,
            revealed: completed,
            completed: completed,
            skipped: false,
            saved: false,
            reviewStage: 0,
            reviewDueAt: reviewDueAt,
            lastSeenAt: lastSeenAt,
            synced: false,
          ),
  );
}

void main() {
  // A fixed seed keeps these deterministic: the selector is random by design,
  // and a flaky feed test is worse than no feed test.
  FeedSelector selector({FeedConfig? config}) =>
      FeedSelector(config: config, random: Random(42));

  const emptyContext = FeedContext(topicProgress: {});

  group('FeedSelector', () {
    test('returns null when the pool is empty', () {
      final result = selector().next(
        pool: const [],
        context: emptyContext,
        alreadyQueued: {},
      );
      expect(result, isNull);
    });

    test('never returns a question already queued', () {
      final pool = [_card('a'), _card('b'), _card('c')];

      final result = selector().next(
        pool: pool,
        context: emptyContext,
        alreadyQueued: {'a', 'b'},
      );

      expect(result?.question.id, 'c');
    });

    test('returns null when every candidate is already queued', () {
      final pool = [_card('a'), _card('b')];

      final result = selector().next(
        pool: pool,
        context: emptyContext,
        alreadyQueued: {'a', 'b'},
      );

      expect(result, isNull);
    });

    test('breaks a same-category run when an alternative exists', () {
      final pool = [
        _card('net1'),
        _card('net2'),
        _card('hw1', category: Category.hardware),
      ];

      // Two networking cards just went past, which is the configured limit.
      final result = selector().next(
        pool: pool,
        context: emptyContext,
        alreadyQueued: {},
        recentCategories: [Category.networking, Category.networking],
      );

      expect(result?.question.category, Category.hardware);
    });

    test('tolerates a run it cannot break', () {
      final pool = [_card('net1'), _card('net2')];

      final result = selector().next(
        pool: pool,
        context: emptyContext,
        alreadyQueued: {},
        recentCategories: [Category.networking, Category.networking],
      );

      // Only networking is available, so a run is better than showing nothing.
      expect(result, isNotNull);
      expect(result!.question.category, Category.networking);
    });

    test('falls back to seen questions once everything has been seen', () {
      final old = DateTime(2026, 1, 1);
      final recent = DateTime(2026, 6, 1);

      final pool = [
        _card('older', timesSeen: 1, completed: true, lastSeenAt: old),
        _card('newer', timesSeen: 1, completed: true, lastSeenAt: recent),
      ];

      // Nothing is unseen and nothing is review-eligible (both completed), so
      // the selector must still produce a card rather than stalling the feed.
      final result = selector().next(
        pool: pool,
        context: emptyContext,
        alreadyQueued: {},
        now: recent,
      );

      expect(result, isNotNull);
    });

    test('treats an explicitly scheduled review as eligible when due', () {
      final now = DateTime(2026, 6, 1);
      final pool = [
        _card(
          'due',
          timesSeen: 2,
          completed: true,
          lastSeenAt: now.subtract(const Duration(days: 10)),
          reviewDueAt: now.subtract(const Duration(days: 1)),
        ),
      ];

      // Only the review slot can supply this card — it is seen and completed,
      // so it is excluded from curiosity, weak-topic and new-topic slots.
      final result = selector(
        config: const FeedConfig(weights: {FeedSlot.review: 1}),
      ).next(pool: pool, context: emptyContext, alreadyQueued: {}, now: now);

      expect(result?.question.id, 'due');
    });

    test('does not surface a scheduled review before it is due', () {
      final now = DateTime(2026, 6, 1);
      final pool = [
        _card(
          'notyet',
          timesSeen: 2,
          completed: true,
          lastSeenAt: now.subtract(const Duration(days: 10)),
          reviewDueAt: now.add(const Duration(days: 3)),
        ),
      ];

      final result = selector(
        config: const FeedConfig(weights: {FeedSlot.review: 1}),
      ).next(pool: pool, context: emptyContext, alreadyQueued: {}, now: now);

      // The review slot is empty, so selection falls through to the
      // least-recently-seen fallback rather than returning nothing.
      expect(result?.question.id, 'notyet');
    });

    test('interview slot only draws interview-shaped questions', () {
      final pool = [
        _card('why1', type: QuestionType.why),
        _card('int1', type: QuestionType.interview),
        _card('dbg1', type: QuestionType.debugging),
      ];

      final results = <String>{};
      for (var i = 0; i < 30; i++) {
        final result = FeedSelector(
          config: const FeedConfig(weights: {FeedSlot.interview: 1}),
          random: Random(i),
        ).next(pool: pool, context: emptyContext, alreadyQueued: {});
        if (result != null) results.add(result.question.id);
      }

      expect(results, isNot(contains('why1')));
      expect(results, containsAll(<String>{'int1', 'dbg1'}));
    });

    test('weak-topic slot prefers the least-completed categories', () {
      final pool = [
        _card('net', category: Category.networking),
        _card('hw', category: Category.hardware),
      ];

      // Networking is well completed, hardware is not — so hardware is weak.
      const context = FeedContext(
        topicProgress: {
          Category.networking: TopicProgress(
            seen: 10,
            completed: 9,
            available: 20,
          ),
          Category.hardware: TopicProgress(
            seen: 10,
            completed: 1,
            available: 20,
          ),
        },
      );

      final result = FeedSelector(
        config: const FeedConfig(weights: {FeedSlot.weakTopics: 1}),
        random: Random(7),
      ).next(pool: pool, context: context, alreadyQueued: {});

      expect(result?.question.category, Category.hardware);
    });

    test('spreads selection across the pool rather than fixating', () {
      final pool = [for (var i = 0; i < 20; i++) _card('q$i')];

      final picked = <String>{};
      for (var i = 0; i < 40; i++) {
        final result = FeedSelector(
          random: Random(i),
        ).next(pool: pool, context: emptyContext, alreadyQueued: {});
        if (result != null) picked.add(result.question.id);
      }

      // Controlled randomness, not a fixed order: many distinct questions
      // should come out of repeated independent draws.
      expect(picked.length, greaterThan(5));
    });
  });
}
