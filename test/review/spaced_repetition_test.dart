import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/questions/data/question_repository.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';
import 'package:techbyte/features/review/domain/spaced_repetition.dart';

import '../helpers/sqlite_test_setup.dart';

void main() {
  final now = DateTime(2026, 6, 1);

  group('SpacedRepetition', () {
    test('a correct answer advances one stage', () {
      final result = SpacedRepetition.next(
        currentStage: 0,
        correct: true,
        now: now,
      );
      expect(result.stage, 1);
      expect(result.dueAt, now.add(const Duration(days: 3)));
    });

    test('a wrong answer resets to the beginning, not one step back', () {
      // A question you have just failed is not "slightly less known" than one
      // failed earlier — the evidence says you do not know it.
      final result = SpacedRepetition.next(
        currentStage: 3,
        correct: false,
        now: now,
      );
      expect(result.stage, 0);
      expect(result.dueAt, now.add(const Duration(days: 1)));
    });

    test('follows the documented ladder over a run of correct answers', () {
      final expected = [
        const Duration(days: 3),
        const Duration(days: 7),
        const Duration(days: 21),
        const Duration(days: 60),
      ];

      var stage = 0;
      for (final interval in expected) {
        final result = SpacedRepetition.next(
          currentStage: stage,
          correct: true,
          now: now,
        );
        expect(result.dueAt, now.add(interval));
        stage = result.stage;
      }
    });

    test('clamps at the final stage instead of growing without bound', () {
      final atMax = SpacedRepetition.next(
        currentStage: SpacedRepetition.maxStage,
        correct: true,
        now: now,
      );
      expect(atMax.stage, SpacedRepetition.maxStage);
      expect(atMax.dueAt, now.add(const Duration(days: 60)));
    });

    test('a skip requeues soon without undoing progress', () {
      final result = SpacedRepetition.afterSkip(currentStage: 3, now: now);
      expect(result.stage, 3);
      expect(result.dueAt, now.add(const Duration(days: 1)));
    });

    test('isDue is inclusive of the due moment and false for null', () {
      expect(SpacedRepetition.isDue(now, now: now), isTrue);
      expect(
        SpacedRepetition.isDue(now.subtract(const Duration(days: 1)), now: now),
        isTrue,
      );
      expect(
        SpacedRepetition.isDue(now.add(const Duration(days: 1)), now: now),
        isFalse,
      );
      expect(SpacedRepetition.isDue(null, now: now), isFalse);
    });
  });

  group('QuestionRepository review scheduling', () {
    late AppDatabase db;
    late QuestionRepository repo;

    setUpAll(configureSqliteForTests);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = QuestionRepository(db);
      await repo.insertAll([
        const Question(
          id: 'a',
          type: QuestionType.interview,
          category: Category.networking,
          difficulty: Difficulty.medium,
          question: 'Why does this need reviewing?',
          shortAnswer: 'Because recall decays without retrieval practice.',
          source: QuestionSource.seed,
        ),
      ]);
    });

    tearDown(() => db.close());

    test('records the schedule even with no prior interaction row', () async {
      // Regression guard: the insert path used to enumerate columns, which
      // silently dropped the review schedule for a never-before-seen question.
      final schedule = await repo.recordAnswer('a', correct: true, now: now);

      final interaction = await repo.interaction('a');
      expect(interaction, isNotNull);
      expect(interaction!.reviewStage, schedule.stage);
      expect(interaction.reviewDueAt, schedule.dueAt);
      expect(interaction.lastAnswerCorrect, isTrue);
      expect(interaction.completed, isTrue);
    });

    test('a wrong answer after a right one resets the stage', () async {
      await repo.recordAnswer('a', correct: true, now: now);
      await repo.recordAnswer('a', correct: true, now: now);
      expect((await repo.interaction('a'))!.reviewStage, 2);

      await repo.recordAnswer('a', correct: false, now: now);
      final interaction = await repo.interaction('a');
      expect(interaction!.reviewStage, 0);
      expect(interaction.lastAnswerCorrect, isFalse);
    });

    test('dueForReview returns only questions that are actually due', () async {
      await repo.recordAnswer('a', correct: false, now: now);

      // Due one day later; not due at the moment it was answered.
      expect(await repo.dueForReview(now: now), isEmpty);
      expect(
        await repo.dueForReview(now: now.add(const Duration(days: 2))),
        hasLength(1),
      );
    });
  });
}
