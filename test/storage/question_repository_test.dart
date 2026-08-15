import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/questions/data/question_repository.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';

import '../helpers/sqlite_test_setup.dart';

void main() {
  late AppDatabase db;
  late QuestionRepository repo;

  setUpAll(configureSqliteForTests);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = QuestionRepository(db);
  });

  tearDown(() => db.close());

  Question question(String id, {Category category = Category.networking}) =>
      Question(
        id: id,
        type: QuestionType.why,
        category: category,
        difficulty: Difficulty.medium,
        question: 'Why does $id happen?',
        shortAnswer: 'Because of the underlying mechanism.',
        source: QuestionSource.ai,
        tags: const ['a', 'b'],
      );

  group('seeding', () {
    // A fixed loader rather than the real asset packs: this group is about
    // seeding mechanics, and asserting them against a corpus that grows every
    // time content is generated would make the tests drift with the content.
    // test/questions/question_test.dart covers the real packs.
    var loads = 0;
    Future<List<Question>> loader() async {
      loads++;
      return [question('pack_a'), question('pack_b')];
    }

    setUp(() => loads = 0);

    test('populates an empty database', () async {
      await repo.ensureSeeded(loader: loader);
      expect(await repo.candidates(), hasLength(2));
    });

    test('is idempotent across launches', () async {
      await repo.ensureSeeded(loader: loader);
      final first = (await repo.candidates()).length;

      await repo.ensureSeeded(loader: loader);
      final second = (await repo.candidates()).length;

      expect(second, first);
    });

    test('does not read the packs when content is already stored', () async {
      await repo.ensureSeeded(loader: loader);
      await repo.ensureSeeded(loader: loader);

      // The COUNT short-circuit is the whole reason this is safe to call on
      // every launch — parsing the corpus each time would undo that.
      expect(loads, 1);
    });
  });

  group('insertAll', () {
    test('reports how many rows were actually new', () async {
      expect(await repo.insertAll([question('a'), question('b')]), 2);
      // Re-inserting the same ids must not duplicate content in the feed.
      expect(await repo.insertAll([question('a'), question('c')]), 1);
    });

    test('round-trips a question through the database', () async {
      await repo.insertAll([question('a', category: Category.cloud)]);
      final restored = await repo.byId('a');

      expect(restored, isNotNull);
      expect(restored!.category, Category.cloud);
      expect(restored.tags, ['a', 'b']);
      expect(restored.source, QuestionSource.ai);
    });
  });

  group('interactions', () {
    test('markSeen accumulates instead of overwriting', () async {
      await repo.insertAll([question('a')]);

      await repo.markSeen('a');
      await repo.markSeen('a');
      await repo.markSeen('a');

      expect((await repo.interaction('a'))?.timesSeen, 3);
    });

    test('reveal and complete are recorded', () async {
      await repo.insertAll([question('a')]);
      await repo.markRevealed('a');
      await repo.markCompleted('a');

      final interaction = await repo.interaction('a');
      expect(interaction?.revealed, isTrue);
      expect(interaction?.completed, isTrue);
    });

    test('completing clears a previous skip', () async {
      await repo.insertAll([question('a')]);
      await repo.markSkipped('a');
      expect((await repo.interaction('a'))?.skipped, isTrue);

      await repo.markCompleted('a');
      expect((await repo.interaction('a'))?.skipped, isFalse);
    });

    test('saving and unsaving updates the saved stream', () async {
      await repo.insertAll([question('a'), question('b')]);

      await repo.setSaved('a', saved: true);
      expect(await repo.watchSaved().first, hasLength(1));

      await repo.setSaved('b', saved: true);
      expect(await repo.watchSaved().first, hasLength(2));

      await repo.setSaved('a', saved: false);
      final saved = await repo.watchSaved().first;
      expect(saved, hasLength(1));
      expect(saved.single.question.id, 'b');
    });
  });

  group('reporting', () {
    test('removes a question from the feed without deleting it', () async {
      await repo.insertAll([question('a'), question('b')]);

      await repo.report('a');

      final candidates = await repo.candidates();
      expect(candidates.map((c) => c.question.id), ['b']);
      // Still retrievable for admin review — reported, not destroyed.
      expect(await repo.byId('a'), isNotNull);
    });
  });

  group('progress', () {
    test('summary counts viewed, completed and saved', () async {
      await repo.insertAll([question('a'), question('b'), question('c')]);

      await repo.markSeen('a');
      await repo.markSeen('b');
      await repo.markCompleted('a');
      await repo.setSaved('c', saved: true);

      final summary = await repo.progressSummary();
      expect(summary.viewed, 2);
      expect(summary.completed, 1);
      expect(summary.saved, 1);
      expect(summary.totalAvailable, 3);
    });

    test('topic progress groups by category', () async {
      await repo.insertAll([
        question('n1'),
        question('n2'),
        question('h1', category: Category.hardware),
      ]);

      await repo.markSeen('n1');
      await repo.markCompleted('n1');

      final progress = await repo.topicProgress();

      expect(progress[Category.networking]?.available, 2);
      expect(progress[Category.networking]?.seen, 1);
      expect(progress[Category.networking]?.completed, 1);
      expect(progress[Category.networking]?.familiarity, 1.0);
      expect(progress[Category.hardware]?.available, 1);
      expect(progress[Category.hardware]?.familiarity, 0.0);
    });
  });

  group('candidates', () {
    test('honours category and exclusion filters', () async {
      await repo.insertAll([
        question('n1'),
        question('h1', category: Category.hardware),
        question('h2', category: Category.hardware),
      ]);

      final hardware = await repo.candidates(categories: {Category.hardware});
      expect(hardware.map((c) => c.question.id), unorderedEquals(['h1', 'h2']));

      final filtered = await repo.candidates(
        categories: {Category.hardware},
        excludeIds: {'h1'},
      );
      expect(filtered.map((c) => c.question.id), ['h2']);
    });
  });
}
