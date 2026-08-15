import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/features/practice/domain/answer_evaluation.dart';
import 'package:techbyte/features/practice/domain/debug_scenario.dart';
import 'package:techbyte/features/practice/domain/practice_mode.dart';

Map<String, dynamic> validEvaluation({double overall = 7.5}) => {
  'overall': overall,
  'dimensions': [
    {'label': 'Technical accuracy', 'score': 8},
    {'label': 'Completeness', 'score': 6},
  ],
  'strengths': ['You named head-of-line blocking directly.'],
  'missing': ['No mention of why QUIC avoids it.'],
  'idealAnswer':
      'TCP guarantees in-order delivery, so one lost packet stalls every '
      'byte behind it while it is retransmitted.',
  'followUpQuestion': 'How does QUIC get reliability without TCP?',
};

void main() {
  group('AnswerEvaluation parsing', () {
    test('reads a well-formed evaluation', () {
      final e = AnswerEvaluation.fromJson(validEvaluation());

      expect(e.overall, 7.5);
      expect(e.dimensions, hasLength(2));
      expect(e.dimensions.first.label, 'Technical accuracy');
      expect(e.dimensions.first.score, 8);
      expect(e.strengths, hasLength(1));
      expect(e.followUpQuestion, isNotNull);
      expect(e.isUsable, isTrue);
    });

    test('clamps scores into 0–10', () {
      final e = AnswerEvaluation.fromJson({
        ...validEvaluation(overall: 47),
        'dimensions': [
          {'label': 'Clarity', 'score': -3},
        ],
      });

      expect(e.overall, 10);
      expect(e.dimensions.single.score, 0);
    });

    test('accepts numbers that arrive as strings', () {
      final e = AnswerEvaluation.fromJson({
        ...validEvaluation(),
        'overall': '6.5',
      });
      expect(e.overall, 6.5);
    });

    test('drops malformed dimensions and blank list entries', () {
      final e = AnswerEvaluation.fromJson({
        ...validEvaluation(),
        'dimensions': [
          {'label': 'Depth', 'score': 5},
          {'label': '', 'score': 9},
          'not an object',
        ],
        'strengths': ['Good point', '   ', 42],
      });

      expect(e.dimensions, hasLength(1));
      expect(e.strengths, ['Good point']);
    });

    test('survives a completely empty response without throwing', () {
      final e = AnswerEvaluation.fromJson(const {});

      expect(e.overall, 0);
      expect(e.dimensions, isEmpty);
      expect(e.idealAnswer, isEmpty);
      // A grade with nothing to learn from is not worth showing.
      expect(e.isUsable, isFalse);
    });

    test('is unusable without an ideal answer, however good the score', () {
      final e = AnswerEvaluation.fromJson({
        ...validEvaluation(overall: 9),
        'idealAnswer': 'Yes.',
      });
      expect(e.isUsable, isFalse);
    });
  });

  group('AnswerEvaluation grading', () {
    test('passes at the threshold, not below it', () {
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 6)).isPass,
        isTrue,
      );
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 5.9)).isPass,
        isFalse,
      );
    });

    test('bands map to the expected labels', () {
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 9)).band,
        EvaluationBand.strong,
      );
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 7)).band,
        EvaluationBand.solid,
      );
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 5)).band,
        EvaluationBand.partial,
      );
      expect(
        AnswerEvaluation.fromJson(validEvaluation(overall: 2)).band,
        EvaluationBand.weak,
      );
    });
  });

  group('PracticeMode', () {
    test('each mode has a distinct five-point rubric', () {
      for (final mode in PracticeMode.values) {
        expect(mode.dimensions, hasLength(5));
      }
      // Debugging grades reasoning, interview grades delivery — if these ever
      // collapse into the same list, the two modes stop being different.
      expect(
        PracticeMode.interview.dimensions,
        isNot(PracticeMode.debugging.dimensions),
      );
    });

    test('debugging rubric weights reasoning over the conclusion', () {
      final dimensions = PracticeMode.debugging.dimensions;
      expect(dimensions, contains('Reasoning quality'));
      // Root cause is one of five, not the whole grade.
      expect(dimensions.where((d) => d == 'Root cause'), hasLength(1));
    });
  });

  group('DebugScenario', () {
    test('parses metrics and rejects incomplete ones', () {
      final scenario = DebugScenario.fromJson({
        'title': 'Latency spike',
        'situation':
            'A service that normally answers in 100 ms is taking four seconds '
            'with no deploy and no traffic change.',
        'metrics': [
          {'label': 'CPU', 'value': '25%'},
          {'label': 'Memory', 'value': ''},
          {'value': 'orphan'},
        ],
        'prompt': 'What do you check first?',
        'category': 'backend',
      }, id: 'x');

      expect(scenario.metrics, hasLength(1));
      expect(scenario.metrics.single.label, 'CPU');
      expect(scenario.isUsable, isTrue);
    });

    test('a scenario without metrics is not usable', () {
      final scenario = DebugScenario.fromJson({
        'title': 'Something broke',
        'situation':
            'The service is slow and nobody knows why, which is not enough '
            'to reason about on its own.',
        'metrics': <dynamic>[],
        'category': 'backend',
      });

      // Without numbers to rule things out it is just a question with extra
      // words, so it must not reach the user.
      expect(scenario.isUsable, isFalse);
    });

    test('seed scenarios are all usable and uniquely identified', () {
      final seeds = SeedDebugScenarios.all();

      expect(seeds, isNotEmpty);
      expect(seeds.every((s) => s.isUsable), isTrue);
      expect(seeds.map((s) => s.id).toSet(), hasLength(seeds.length));
      // Each carries enough signal to reason over.
      expect(seeds.every((s) => s.metrics.length >= 4), isTrue);
    });
  });
}
