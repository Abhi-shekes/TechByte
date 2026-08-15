/// Taxonomy for TechByte content: question shapes, categories, difficulty and
/// provenance.
///
/// Every enum here is persisted (in Drift and in Firestore) by its `id` string
/// rather than by index, so reordering or inserting values is safe.
library;

/// The rhetorical shape of a question. Drives prompt selection and lets the
/// feed mix formats so ten cards in a row don't all read the same way.
enum QuestionType {
  why('why', 'Why'),
  how('how', 'How'),
  whatHappensIf('what_happens_if', 'What happens if'),
  compare('compare', 'Compare'),
  behindTheScenes('behind_the_scenes', 'Behind the scenes'),
  mythFact('myth_fact', 'Myth or fact'),
  surprising('surprising', 'Surprising'),
  production('production', 'Production'),
  interview('interview', 'Interview'),
  debugging('debugging', 'Debugging');

  const QuestionType(this.id, this.label);

  final String id;
  final String label;

  static QuestionType fromId(String id) =>
      values.firstWhere((t) => t.id == id, orElse: () => QuestionType.why);
}

/// Top-level technology categories. Extensible: [Category.fromId] tolerates
/// unknown ids so content generated against a newer taxonomy still loads.
enum Category {
  programming('programming', 'Programming'),
  computerScience('computer_science', 'Computer Science'),
  operatingSystems('operating_systems', 'Operating Systems'),
  networking('networking', 'Networking'),
  internet('internet', 'Internet'),
  databases('databases', 'Databases'),
  backend('backend', 'Backend'),
  cloud('cloud', 'Cloud'),
  devops('devops', 'DevOps'),
  aiMl('ai_ml', 'AI/ML'),
  hardware('hardware', 'Hardware'),
  mobile('mobile', 'Mobile'),
  cybersecurity('cybersecurity', 'Cybersecurity'),
  electronics('electronics', 'Electronics'),
  distributedSystems('distributed_systems', 'Distributed Systems'),
  systemDesign('system_design', 'System Design'),
  developerTools('developer_tools', 'Developer Tools'),
  realWorldTech('real_world_tech', 'Real-World Technology');

  const Category(this.id, this.label);

  final String id;
  final String label;

  static Category? tryFromId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }

  static Category fromId(String id) => tryFromId(id) ?? Category.realWorldTech;
}

enum Difficulty {
  easy('easy', 'Easy', 1),
  medium('medium', 'Medium', 2),
  hard('hard', 'Hard', 3),
  expert('expert', 'Expert', 4);

  const Difficulty(this.id, this.label, this.rank);

  final String id;
  final String label;
  final int rank;

  static Difficulty fromId(String id) =>
      values.firstWhere((d) => d.id == id, orElse: () => Difficulty.medium);
}

/// Where a question came from. The feed uses this to prefer curated content
/// and to let us purge AI content wholesale if quality regresses.
enum QuestionSource {
  /// Ships in the APK. Always available, including on first launch offline.
  seed('seed'),

  /// Generated on-device via Firebase AI Logic and cached locally.
  ai('ai'),

  /// Authored/approved through the admin workflow and synced from Firestore.
  curated('curated');

  const QuestionSource(this.id);

  final String id;

  static QuestionSource fromId(String id) =>
      values.firstWhere((s) => s.id == id, orElse: () => QuestionSource.seed);
}

/// The self-declared experience level chosen during onboarding.
enum ExperienceLevel {
  curious('curious', 'Curious'),
  beginner('beginner', 'Beginner'),
  intermediate('intermediate', 'Intermediate'),
  advanced('advanced', 'Advanced'),
  professional('professional', 'Professional');

  const ExperienceLevel(this.id, this.label);

  final String id;
  final String label;

  static ExperienceLevel fromId(String id) => values.firstWhere(
    (l) => l.id == id,
    orElse: () => ExperienceLevel.intermediate,
  );

  /// Difficulties that suit this level. Used to weight the feed rather than to
  /// hard-filter it, so users still meet the occasional stretch question.
  Set<Difficulty> get preferredDifficulties => switch (this) {
    ExperienceLevel.curious => {Difficulty.easy},
    ExperienceLevel.beginner => {Difficulty.easy, Difficulty.medium},
    ExperienceLevel.intermediate => {Difficulty.medium, Difficulty.hard},
    ExperienceLevel.advanced => {Difficulty.hard, Difficulty.expert},
    ExperienceLevel.professional => {Difficulty.hard, Difficulty.expert},
  };
}

/// What the user says they're here for. Shifts the feed weighting.
enum LearningGoal {
  learnTech('learn_tech', 'Learn technology'),
  interviewPrep('interview_prep', 'Interview preparation'),
  engineeringGrowth('engineering_growth', 'Engineering growth'),
  curiosity('curiosity', 'Curiosity'),
  all('all', 'All of it');

  const LearningGoal(this.id, this.label);

  final String id;
  final String label;

  static LearningGoal fromId(String id) =>
      values.firstWhere((g) => g.id == id, orElse: () => LearningGoal.all);
}
