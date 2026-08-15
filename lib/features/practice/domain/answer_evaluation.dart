/// One rubric line from a graded answer.
class DimensionScore {
  const DimensionScore({required this.label, required this.score});

  final String label;

  /// 0–10.
  final double score;

  @override
  bool operator ==(Object other) =>
      other is DimensionScore && other.label == label && other.score == score;

  @override
  int get hashCode => Object.hash(label, score);
}

/// The result of grading a free-text practice answer.
///
/// Shaped to be *useful after a wrong answer*, not just to produce a number.
/// The score exists so progress is legible; [missing] and [idealAnswer] are
/// what the user actually learns from, which is why neither is optional.
class AnswerEvaluation {
  const AnswerEvaluation({
    required this.overall,
    required this.dimensions,
    required this.strengths,
    required this.missing,
    required this.idealAnswer,
    this.followUpQuestion,
  });

  /// 0–10, one decimal place.
  final double overall;

  final List<DimensionScore> dimensions;

  /// What the answer got right. Never empty in practice — the prompt requires
  /// at least one, because an evaluation that only lists failures stops being
  /// read.
  final List<String> strengths;

  /// What a strong answer would have covered and this one did not.
  final List<String> missing;

  final String idealAnswer;
  final String? followUpQuestion;

  /// The threshold at which an answer counts as "correct" for scheduling.
  ///
  /// 6.0 rather than 5.0: passing a review should mean you could hold your own
  /// on the question, not that you were closer to right than wrong.
  static const passThreshold = 6.0;

  bool get isPass => overall >= passThreshold;

  /// Coarse band used for colour and wording in the UI.
  EvaluationBand get band => switch (overall) {
    >= 8.5 => EvaluationBand.strong,
    >= passThreshold => EvaluationBand.solid,
    >= 4.0 => EvaluationBand.partial,
    _ => EvaluationBand.weak,
  };

  factory AnswerEvaluation.fromJson(Map<String, dynamic> json) {
    double num0(Object? v) => switch (v) {
      final num n => n.toDouble().clamp(0.0, 10.0),
      final String s => (double.tryParse(s) ?? 0).clamp(0.0, 10.0),
      _ => 0.0,
    };

    List<String> strings(Object? v) => switch (v) {
      final List<dynamic> l =>
        l
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false),
      _ => const <String>[],
    };

    final dimensions = switch (json['dimensions']) {
      final List<dynamic> l =>
        l
            .whereType<Map<String, dynamic>>()
            .map(
              (d) => DimensionScore(
                label: (d['label'] as String?)?.trim() ?? '',
                score: num0(d['score']),
              ),
            )
            .where((d) => d.label.isNotEmpty)
            .toList(growable: false),
      _ => const <DimensionScore>[],
    };

    return AnswerEvaluation(
      overall: num0(json['overall']),
      dimensions: dimensions,
      strengths: strings(json['strengths']),
      missing: strings(json['missing']),
      idealAnswer: (json['idealAnswer'] as String?)?.trim() ?? '',
      followUpQuestion: switch (json['followUpQuestion']) {
        final String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      },
    );
  }

  /// Whether the grade is complete enough to show.
  ///
  /// A model that returns a score but no ideal answer has produced a number
  /// without the part that teaches anything, so it is treated as invalid
  /// rather than rendered as a bare grade.
  bool get isUsable => idealAnswer.length >= 40 && dimensions.isNotEmpty;
}

enum EvaluationBand {
  strong('Strong answer'),
  solid('Solid answer'),
  partial('Partly there'),
  weak('Needs work');

  const EvaluationBand(this.label);

  final String label;
}
