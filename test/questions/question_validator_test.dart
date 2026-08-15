import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';
import 'package:techbyte/features/questions/domain/question_validator.dart';

Question _question({
  String id = 'q1',
  String question =
      'Why does a phone slow down when its storage is nearly full?',
  String shortAnswer =
      'Flash storage can only write to empty blocks, so a nearly full drive '
      'must erase and rewrite blocks before every new write.',
}) {
  return Question(
    id: id,
    type: QuestionType.why,
    category: Category.hardware,
    difficulty: Difficulty.medium,
    question: question,
    shortAnswer: shortAnswer,
    source: QuestionSource.ai,
  );
}

void main() {
  const validator = QuestionValidator();

  group('QuestionValidator', () {
    test('accepts a well-formed question', () {
      expect(validator.validate(_question()), isA<ValidationAccepted>());
    });

    test('rejects definition-style phrasings', () {
      // The editorial rule the whole product rests on: "What is X?" is banned
      // regardless of how good the answer is.
      for (final text in [
        'What is RAM?',
        'What is a CPU cache and how does it work?',
        'What are the different types of database index?',
        'Define the CAP theorem in distributed systems?',
      ]) {
        final result = validator.validate(_question(question: text));
        expect(
          result,
          isA<ValidationRejected>(),
          reason: 'should have rejected: $text',
        );
      }
    });

    test('rejects a question not phrased as a question', () {
      final result = validator.validate(
        _question(question: 'Storage fills up and the phone becomes slower.'),
      );
      expect(result, isA<ValidationRejected>());
    });

    test('rejects answers that are too short to be useful', () {
      final result = validator.validate(_question(shortAnswer: 'It is slow.'));
      expect(result, isA<ValidationRejected>());
    });

    test('rejects an empty id', () {
      expect(
        validator.validate(_question(id: '  ')),
        isA<ValidationRejected>(),
      );
    });

    test('rejects a near-duplicate of an existing question', () {
      final existing = QuestionValidator.fingerprint(
        'Why does a phone slow down when its storage is nearly full?',
      );

      final result = validator.validate(
        _question(
          question:
              'Why does your phone slow down when the storage is almost full?',
        ),
        existingFingerprints: [existing],
      );

      expect(result, isA<ValidationRejected>());
    });

    test('accepts a genuinely different question about the same topic', () {
      final existing = QuestionValidator.fingerprint(
        'Why does a phone slow down when its storage is nearly full?',
      );

      final result = validator.validate(
        _question(
          question:
              'Why do solid state drives need a TRIM command from the operating system?',
        ),
        existingFingerprints: [existing],
      );

      expect(result, isA<ValidationAccepted>());
    });

    test('fingerprint ignores punctuation, case and stop words', () {
      expect(
        QuestionValidator.fingerprint('Why does the CPU cache exist?'),
        QuestionValidator.fingerprint('why DOES cpu   cache exist'),
      );
    });
  });
}
