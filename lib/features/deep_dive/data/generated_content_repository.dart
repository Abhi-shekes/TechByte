import '../../../core/storage/app_database.dart';

/// Local cache for lazily generated content — deep dives and the alternate
/// explanations from "Explain differently".
///
/// This cache is the main reason the app stays inside a free AI quota. The
/// same question asked twice costs one request, ever; every later request for
/// it is served from here, on-device and offline.
class GeneratedContentRepository {
  GeneratedContentRepository(this._db);

  final AppDatabase _db;

  String _key(String questionId, String kind) => '$questionId::$kind';

  Future<String?> read(String questionId, String kind) async {
    final row = await (_db.select(
      _db.generatedContentRows,
    )..where((t) => t.id.equals(_key(questionId, kind)))).getSingleOrNull();
    return row?.body;
  }

  Future<void> write(String questionId, String kind, String body) async {
    await _db
        .into(_db.generatedContentRows)
        .insertOnConflictUpdate(
          GeneratedContentRowsCompanion.insert(
            id: _key(questionId, kind),
            questionId: questionId,
            kind: kind,
            body: body,
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Removes everything generated for a question. Used when content is
  /// reported, so a bad answer does not leave stale derivatives behind.
  Future<void> clearFor(String questionId) async {
    await (_db.delete(
      _db.generatedContentRows,
    )..where((t) => t.questionId.equals(questionId))).go();
  }
}
