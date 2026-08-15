import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/features/feed/domain/daily_session.dart';
import 'package:techbyte/features/questions/data/question_repository.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';

QuestionWithState _card(String id, Category category) => QuestionWithState(
  question: Question(
    id: id,
    type: QuestionType.why,
    category: category,
    difficulty: Difficulty.medium,
    question: 'Why does $id behave that way?',
    shortAnswer: 'Because of the mechanism underneath it.',
    source: QuestionSource.seed,
  ),
);

/// A pool spread across several categories, three questions each.
List<QuestionWithState> _pool({int perCategory = 3}) {
  final categories = [
    Category.networking,
    Category.hardware,
    Category.databases,
    Category.aiMl,
    Category.cloud,
    Category.programming,
  ];
  return [
    for (final category in categories)
      for (var i = 0; i < perCategory; i++)
        _card('${category.id}_$i', category),
  ];
}

void main() {
  final today = DateTime(2026, 6, 1, 14, 30);

  group('DailySessionBuilder', () {
    test('builds the requested number of questions', () {
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(),
        count: 10,
      );
      expect(session.questionIds, hasLength(10));
    });

    test('is deterministic for a given date', () {
      // Reopening the app mid-session must not reshuffle the set.
      final a = DailySessionBuilder.build(date: today, pool: _pool());
      final b = DailySessionBuilder.build(
        date: DateTime(2026, 6, 1, 22, 5),
        pool: _pool(),
      );
      expect(a.questionIds, b.questionIds);
    });

    test('produces a different set on a different date', () {
      final a = DailySessionBuilder.build(date: today, pool: _pool());
      final b = DailySessionBuilder.build(
        date: DateTime(2026, 6, 2),
        pool: _pool(),
      );
      expect(a.questionIds, isNot(b.questionIds));
    });

    test('normalises the date to midnight', () {
      final session = DailySessionBuilder.build(date: today, pool: _pool());
      expect(session.date, DateTime(2026, 6, 1));
    });

    test('never repeats a question within one session', () {
      final session = DailySessionBuilder.build(date: today, pool: _pool());
      expect(
        session.questionIds.toSet(),
        hasLength(session.questionIds.length),
      );
    });

    test('spreads the first picks across distinct categories', () {
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(),
        count: 6,
      );

      final categories = session.questionIds
          .map((id) => id.split('_').first)
          .toSet();
      // Six categories are available, so a well-spread set uses all six.
      expect(categories, hasLength(6));
    });

    test('pads from seen questions rather than returning a short set', () {
      // "Today's Tech 10" showing four items would read as a bug.
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(perCategory: 1),
        count: 10,
      );
      expect(session.questionIds, hasLength(6));

      final bigger = DailySessionBuilder.build(
        date: today,
        pool: _pool(perCategory: 2),
        count: 10,
      );
      expect(bigger.questionIds, hasLength(10));
    });

    test('handles an empty pool without throwing', () {
      final session = DailySessionBuilder.build(date: today, pool: const []);
      expect(session.questionIds, isEmpty);
      expect(session.total, 0);
      expect(session.progress, 0);
      expect(session.isComplete, isFalse);
    });
  });

  group('DailySession progress', () {
    test('counts only completions that belong to the session', () {
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(),
        count: 10,
      );

      final completed = {
        ...session.questionIds.take(3),
        'something_else_entirely',
      };
      final updated = session.copyWith(completedIds: completed);

      expect(updated.completed, 3);
      expect(updated.progress, closeTo(0.3, 1e-9));
      expect(updated.isComplete, isFalse);
    });

    test('is complete once every question is done', () {
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(),
        count: 10,
      );
      final updated = session.copyWith(
        completedIds: session.questionIds.toSet(),
      );

      expect(updated.isComplete, isTrue);
      expect(updated.progress, 1.0);
    });

    test('an empty session is never complete', () {
      final empty = DailySession(
        date: today,
        questionIds: const [],
        completedIds: const {},
      );
      expect(empty.isComplete, isFalse);
    });

    test('estimates reading time at about 45 seconds a question', () {
      final session = DailySessionBuilder.build(
        date: today,
        pool: _pool(),
        count: 10,
      );
      expect(session.estimatedMinutes, 8);
    });
  });
}
