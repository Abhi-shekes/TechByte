import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import '../../features/questions/domain/question.dart';
import '../../features/questions/domain/question_enums.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The local, offline-first database.
///
/// Everything the feed needs is read from here. Firestore is a sync target,
/// never a read path on the hot swipe loop.
@DriftDatabase(
  tables: [
    QuestionRows,
    QuestionInteractions,
    TopicFamiliarityRows,
    GeneratedContentRows,
    AiUsageRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test constructor — pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'techbyte.sqlite'));

    // Recommended by sqlite3_flutter_libs: keep temp files somewhere writable
    // on Android, and work around old Android SQLite quirks.
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    sqlite3.tempDirectory = (await getTemporaryDirectory()).path;

    return NativeDatabase.createInBackground(file);
  });
}

/// Mapping helpers between the Drift row type and the domain [Question].
///
/// Kept as extensions rather than generated converters so the domain model
/// stays free of any persistence imports.
extension QuestionRowMapper on QuestionRow {
  Question toDomain() => Question(
    id: id,
    type: QuestionType.fromId(type),
    category: Category.fromId(category),
    subcategory: subcategory,
    difficulty: Difficulty.fromId(difficulty),
    question: question,
    shortAnswer: shortAnswer,
    whyItMatters: whyItMatters,
    realWorldExample: realWorldExample,
    technicalDetails: technicalDetails,
    interviewAngle: interviewAngle,
    followUpQuestion: followUpQuestion,
    tags: switch (jsonDecode(tags)) {
      final List<dynamic> l => l.whereType<String>().toList(growable: false),
      _ => const <String>[],
    },
    source: QuestionSource.fromId(source),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension QuestionCompanionMapper on Question {
  QuestionRowsCompanion toCompanion() => QuestionRowsCompanion.insert(
    id: id,
    type: type.id,
    category: category.id,
    subcategory: Value(subcategory),
    difficulty: difficulty.id,
    question: question,
    shortAnswer: shortAnswer,
    whyItMatters: Value(whyItMatters),
    realWorldExample: Value(realWorldExample),
    technicalDetails: Value(technicalDetails),
    interviewAngle: Value(interviewAngle),
    followUpQuestion: Value(followUpQuestion),
    tags: Value(jsonEncode(tags)),
    source: source.id,
    createdAt: Value(createdAt ?? DateTime.now()),
    updatedAt: Value(updatedAt ?? DateTime.now()),
  );
}
