import 'package:drift/drift.dart';

/// Cached question content, regardless of where it came from.
///
/// This is the feed's source of truth. Seed content is inserted on first run,
/// generated content is appended as it is validated, and the feed only ever
/// reads from here — which is what makes swiping instant and offline browsing
/// work without a special case.
class QuestionRows extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get category => text()();
  TextColumn get subcategory => text().nullable()();
  TextColumn get difficulty => text()();
  TextColumn get question => text()();
  TextColumn get shortAnswer => text()();
  TextColumn get whyItMatters => text().nullable()();
  TextColumn get realWorldExample => text().nullable()();
  TextColumn get technicalDetails => text().nullable()();
  TextColumn get interviewAngle => text().nullable()();
  TextColumn get followUpQuestion => text().nullable()();

  /// JSON-encoded `List<String>`.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  TextColumn get source => text()();

  /// Set when a user reports the question as wrong or low quality. Reported
  /// content is excluded from the feed without being deleted, so it can still
  /// be reviewed through the admin workflow.
  BoolColumn get reported => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-question user state.
///
/// Separate from [QuestionRows] so content can be replaced or re-synced
/// without touching the user's history, and so a single question row is shared
/// rather than duplicated per user on this device.
class QuestionInteractions extends Table {
  TextColumn get questionId => text()();

  IntColumn get timesSeen => integer().withDefault(const Constant(0))();
  BoolColumn get revealed => boolean().withDefault(const Constant(false))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
  BoolColumn get saved => boolean().withDefault(const Constant(false))();

  DateTimeColumn get savedAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  /// Null until the question has been answered in a mode that grades.
  BoolColumn get lastAnswerCorrect => boolean().nullable()();

  /// Spaced repetition. [reviewStage] indexes into the interval schedule;
  /// [reviewDueAt] is when the question becomes eligible for the review slot.
  IntColumn get reviewStage => integer().withDefault(const Constant(0))();
  DateTimeColumn get reviewDueAt => dateTime().nullable()();

  /// False once the local change has been mirrored to Firestore. Everything is
  /// written locally first and synced opportunistically, so the app never
  /// blocks on the network.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {questionId};
}

/// Rolling per-category counters behind the "topic familiarity" display.
class TopicFamiliarityRows extends Table {
  TextColumn get categoryId => text()();
  IntColumn get seen => integer().withDefault(const Constant(0))();
  IntColumn get completed => integer().withDefault(const Constant(0))();
  IntColumn get correct => integer().withDefault(const Constant(0))();
  IntColumn get incorrect => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {categoryId};
}

/// Cache for lazily generated content — deep dives and alternate explanations.
///
/// Keyed by question plus variant so the same request is never paid for twice.
/// This is the single biggest lever on staying inside the free Gemini quota.
class GeneratedContentRows extends Table {
  /// `<questionId>::<kind>`.
  TextColumn get id => text()();
  TextColumn get questionId => text()();

  /// Variant discriminator: `deep_dive`, `simple`, `eli10`, `analogy`, and so on.
  TextColumn get kind => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local AI usage counters, bucketed by UTC day.
///
/// Purely for cost control and diagnostics: the app uses these to back off
/// before it runs into a hard quota error, and to show honest state when
/// generation is unavailable. Nothing here is personal data.
class AiUsageRows extends Table {
  /// `yyyy-MM-dd` in UTC.
  TextColumn get day => text()();
  IntColumn get requests => integer().withDefault(const Constant(0))();
  IntColumn get failures => integer().withDefault(const Constant(0))();
  IntColumn get quotaFailures => integer().withDefault(const Constant(0))();
  IntColumn get cacheHits => integer().withDefault(const Constant(0))();
  IntColumn get questionsGenerated =>
      integer().withDefault(const Constant(0))();
  IntColumn get questionsRejected => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {day};
}
