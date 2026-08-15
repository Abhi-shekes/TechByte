import '../../questions/domain/question_enums.dart';

/// The kinds of graded practice.
///
/// Both modes share a pipeline — pose a problem, take a free-text answer, grade
/// it, schedule a review — and differ only in what "good" means. That is why
/// the dimensions below are per-mode rather than a single fixed set.
enum PracticeMode {
  interview(
    'interview',
    'Interview',
    'Answer as you would out loud, in about 60–90 seconds.',
  ),
  debugging(
    'debugging',
    'Debugging',
    'Say what you would investigate, and why, before concluding.',
  );

  const PracticeMode(this.id, this.label, this.instruction);

  final String id;
  final String label;

  /// Shown above the answer box. Sets the expectation the grader will apply.
  final String instruction;

  /// Question types this mode draws from.
  Set<QuestionType> get sourceTypes => switch (this) {
    PracticeMode.interview => {
      QuestionType.interview,
      QuestionType.production,
      QuestionType.compare,
    },
    PracticeMode.debugging => {QuestionType.debugging, QuestionType.production},
  };

  /// The rubric. Interview grading rewards a complete, well-structured answer;
  /// debugging grading rewards the *reasoning*, which is why "root cause" is
  /// only one of five dimensions rather than the whole score.
  List<String> get dimensions => switch (this) {
    PracticeMode.interview => const [
      'Technical accuracy',
      'Completeness',
      'Clarity',
      'Depth',
      'Structure',
    ],
    PracticeMode.debugging => const [
      'Hypotheses considered',
      'Investigation order',
      'Use of evidence',
      'Reasoning quality',
      'Root cause',
    ],
  };

  /// Placeholder for the answer box. Mode-specific because "Write your
  /// answer…" tells someone staring at a blank field nothing about what a good
  /// one looks like, which is most of why they stall on it.
  String get answerHint => switch (this) {
    PracticeMode.interview =>
      'Start with the one-line answer, then justify it…',
    PracticeMode.debugging =>
      'What do you suspect, what would you check, and why…',
  };

  /// Roughly how long a complete answer runs, in words. Shown as a target, not
  /// a limit — the counter turns positive once it is reached and never scolds.
  int get targetWords => switch (this) {
    PracticeMode.interview => 80,
    PracticeMode.debugging => 110,
  };

  /// Openers the user can tap to drop into the answer box.
  ///
  /// The rubric already names what grading rewards — structure, hypotheses,
  /// use of evidence — but only after the answer has been written and scored.
  /// These put the same shape in front of the user *while* they write, which
  /// is the difference between feedback and teaching.
  List<({String label, String snippet})> get scaffolds => switch (this) {
    PracticeMode.interview => const [
      (label: 'In short', snippet: 'In short, '),
      (label: 'Because', snippet: 'This works because '),
      (label: 'For example', snippet: 'For example, '),
      (label: 'Trade-off', snippet: 'The trade-off is '),
      (label: 'When not to', snippet: 'I would avoid this when '),
    ],
    PracticeMode.debugging => const [
      (label: 'Suspects', snippet: 'Possible causes: '),
      (label: 'Check first', snippet: 'I would check this first: '),
      (label: 'Ruled out', snippet: 'I can rule out '),
      (label: 'Evidence', snippet: 'The metric that tells me this is '),
      (label: 'Conclusion', snippet: 'Most likely cause: '),
    ],
  };

  static PracticeMode fromId(String id) => values.firstWhere(
    (m) => m.id == id,
    orElse: () => PracticeMode.interview,
  );
}
