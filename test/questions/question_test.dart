import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/features/questions/data/question_pack.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';
import 'package:techbyte/features/questions/domain/question_validator.dart';

void main() {
  group('Question serialization', () {
    test('round-trips through JSON', () {
      final original = Question(
        id: 'q1',
        type: QuestionType.compare,
        category: Category.networking,
        subcategory: 'tcp',
        difficulty: Difficulty.hard,
        question: 'Why would anyone choose UDP when TCP guarantees delivery?',
        shortAnswer: 'Because the guarantee costs time.',
        whyItMatters: 'It explains why calls use UDP.',
        tags: const ['tcp', 'udp'],
        source: QuestionSource.curated,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      final restored = Question.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.subcategory, 'tcp');
      expect(restored.whyItMatters, 'It explains why calls use UDP.');
      expect(restored.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('tolerates missing and malformed optional fields', () {
      final restored = Question.fromJson({
        'id': 'q2',
        'type': 'not_a_real_type',
        'category': 'not_a_real_category',
        'difficulty': 'nonsense',
        'question': 'Why does this parse?',
        'shortAnswer': 'Because unknown values fall back to defaults.',
        'tags': 'not a list',
        'whyItMatters': '   ',
      });

      expect(restored.type, QuestionType.why);
      expect(restored.category, Category.realWorldTech);
      expect(restored.difficulty, Difficulty.medium);
      expect(restored.tags, isEmpty);
      // Whitespace-only optional fields become null so no empty section renders.
      expect(restored.whyItMatters, isNull);
    });

    test('detailSections omits absent sections and keeps display order', () {
      const question = Question(
        id: 'q3',
        type: QuestionType.why,
        category: Category.cloud,
        difficulty: Difficulty.easy,
        question: 'Why is egress expensive?',
        shortAnswer: 'Because it is priced as a business decision.',
        whyItMatters: 'It dominates cloud bills.',
        technicalDetails: 'Ingress is free, egress is not.',
        source: QuestionSource.seed,
      );

      expect(question.detailSections.map((s) => s.heading), [
        'Why it matters',
        'Technical detail',
      ]);
    });
  });

  group('Bundled content packs', () {
    // Loads the real assets, so this is the test that fails if a pack is
    // malformed, undeclared in pubspec, or quietly dropped from the build.
    late final List<Question> bundled;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      bundled = await QuestionPack.loadBundled();
    });

    test('is non-empty and marked as seed content', () {
      expect(bundled, isNotEmpty);
      expect(bundled.every((q) => q.source == QuestionSource.seed), isTrue);
    });

    test('has unique ids', () {
      final ids = bundled.map((q) => q.id).toSet();
      expect(ids.length, bundled.length);
    });

    test('every question has the two fields a card cannot render without', () {
      for (final question in bundled) {
        expect(question.question, isNotEmpty, reason: question.id);
        expect(question.shortAnswer, isNotEmpty, reason: question.id);
      }
    });

    // The bundled corpus defines the quality bar generated content is judged
    // against, so it has to clear that bar itself. `tools/content/validate.mjs`
    // asserts the same thing at authoring time; this is the check that it was
    // actually run before shipping.
    test('every bundled question passes the content validator', () {
      const validator = QuestionValidator();
      final fingerprints = <Set<String>>[];

      for (final question in bundled) {
        final result = validator.validate(
          question,
          existingFingerprints: fingerprints,
        );
        expect(
          result,
          isA<ValidationAccepted>(),
          reason: '${question.id} was rejected: $result',
        );
        fingerprints.add(QuestionValidator.fingerprint(question.question));
      }
    });

    test('covers a broad spread of categories', () {
      final categories = bundled.map((q) => q.category).toSet();
      expect(categories.length, greaterThanOrEqualTo(10));
    });
  });
}
