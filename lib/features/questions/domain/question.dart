import 'package:collection/collection.dart';

import 'question_enums.dart';

/// A single TechByte question and everything needed to render its card.
///
/// Immutable and self-contained: the feed never has to fetch anything extra to
/// display a card, which is what makes offline browsing and instant swiping
/// possible. Deep dives and alternate explanations are the only content
/// generated lazily, and they live in a separate cache keyed by [id].
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.category,
    required this.difficulty,
    required this.question,
    required this.shortAnswer,
    required this.source,
    this.subcategory,
    this.whyItMatters,
    this.realWorldExample,
    this.technicalDetails,
    this.interviewAngle,
    this.followUpQuestion,
    this.tags = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final QuestionType type;
  final Category category;

  /// Free-form narrower topic (`ssd`, `dns`, `kafka`). Not an enum: the
  /// subcategory space is long-tailed and grows with generated content.
  final String? subcategory;

  final Difficulty difficulty;

  /// The hook. Shown alone in the "think" state.
  final String question;

  /// The payoff, 1–3 sentences. Shown first on reveal.
  final String shortAnswer;

  final String? whyItMatters;
  final String? realWorldExample;
  final String? technicalDetails;
  final String? interviewAngle;

  /// A natural next question, used to seed Go Deeper.
  final String? followUpQuestion;

  final List<String> tags;
  final QuestionSource source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Sections present beyond the short answer, in display order. Drives the
  /// reveal animation so we never render an empty heading.
  List<({String heading, String body})> get detailSections => [
    if (_has(whyItMatters)) (heading: 'Why it matters', body: whyItMatters!),
    if (_has(realWorldExample))
      (heading: 'Real world', body: realWorldExample!),
    if (_has(technicalDetails))
      (heading: 'Technical detail', body: technicalDetails!),
    if (_has(interviewAngle))
      (heading: 'Interview angle', body: interviewAngle!),
  ];

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  Question copyWith({
    String? id,
    QuestionType? type,
    Category? category,
    String? subcategory,
    Difficulty? difficulty,
    String? question,
    String? shortAnswer,
    String? whyItMatters,
    String? realWorldExample,
    String? technicalDetails,
    String? interviewAngle,
    String? followUpQuestion,
    List<String>? tags,
    QuestionSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Question(
      id: id ?? this.id,
      type: type ?? this.type,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      difficulty: difficulty ?? this.difficulty,
      question: question ?? this.question,
      shortAnswer: shortAnswer ?? this.shortAnswer,
      whyItMatters: whyItMatters ?? this.whyItMatters,
      realWorldExample: realWorldExample ?? this.realWorldExample,
      technicalDetails: technicalDetails ?? this.technicalDetails,
      interviewAngle: interviewAngle ?? this.interviewAngle,
      followUpQuestion: followUpQuestion ?? this.followUpQuestion,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.id,
    'category': category.id,
    'subcategory': subcategory,
    'difficulty': difficulty.id,
    'question': question,
    'shortAnswer': shortAnswer,
    'whyItMatters': whyItMatters,
    'realWorldExample': realWorldExample,
    'technicalDetails': technicalDetails,
    'interviewAngle': interviewAngle,
    'followUpQuestion': followUpQuestion,
    'tags': tags,
    'source': source.id,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  /// Lenient by design: this parses both our own persisted rows and model
  /// output that has already passed schema validation, so a missing optional
  /// field degrades to null rather than throwing.
  factory Question.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final v = json[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return Question(
      id: str('id') ?? '',
      type: QuestionType.fromId(str('type') ?? ''),
      category: Category.fromId(str('category') ?? ''),
      subcategory: str('subcategory'),
      difficulty: Difficulty.fromId(str('difficulty') ?? ''),
      question: str('question') ?? '',
      shortAnswer: str('shortAnswer') ?? '',
      whyItMatters: str('whyItMatters'),
      realWorldExample: str('realWorldExample'),
      technicalDetails: str('technicalDetails'),
      interviewAngle: str('interviewAngle'),
      followUpQuestion: str('followUpQuestion'),
      tags: switch (json['tags']) {
        final List<dynamic> l => l.whereType<String>().toList(growable: false),
        _ => const <String>[],
      },
      source: QuestionSource.fromId(str('source') ?? ''),
      createdAt: DateTime.tryParse(str('createdAt') ?? ''),
      updatedAt: DateTime.tryParse(str('updatedAt') ?? ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          other.id == id &&
          other.question == question &&
          other.shortAnswer == shortAnswer &&
          other.type == type &&
          other.category == category &&
          other.difficulty == difficulty &&
          other.source == source &&
          const ListEquality<String>().equals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    id,
    question,
    shortAnswer,
    type,
    category,
    difficulty,
    source,
    const ListEquality<String>().hash(tags),
  );

  @override
  String toString() => 'Question($id, ${category.id}, "$question")';
}
