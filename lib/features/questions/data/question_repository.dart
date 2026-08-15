import 'package:drift/drift.dart';

import '../../../core/storage/app_database.dart';
import '../../review/domain/spaced_repetition.dart';
import '../domain/question.dart';
import '../domain/question_enums.dart';
import 'question_pack.dart';

/// A question paired with the current user's state for it.
class QuestionWithState {
  const QuestionWithState({required this.question, this.interaction});

  final Question question;
  final QuestionInteraction? interaction;

  bool get isSaved => interaction?.saved ?? false;
  bool get isCompleted => interaction?.completed ?? false;
  bool get wasSeen => (interaction?.timesSeen ?? 0) > 0;
}

/// All reads and writes of question content and per-question user state.
///
/// Local-first without exception: every method here touches SQLite only.
/// Firestore synchronisation is a separate concern layered on top, so the feed
/// never waits on a network round trip.
class QuestionRepository {
  QuestionRepository(this._db);

  final AppDatabase _db;

  /// Inserts the bundled content packs if the table is empty.
  ///
  /// Idempotent, and safe to call on every launch: it is a single COUNT on the
  /// common path, and the packs are only read when that count is zero. Called
  /// before the first frame so the feed is never empty.
  ///
  /// [loader] exists for tests; production always uses the bundled packs.
  Future<void> ensureSeeded({QuestionPackLoader? loader}) async {
    final count = await _db
        .customSelect('SELECT COUNT(*) AS c FROM question_rows')
        .map((row) => row.read<int>('c'))
        .getSingle();
    if (count > 0) return;

    final seeds = await (loader ?? QuestionPack.loadBundled)();
    if (seeds.isEmpty) return;

    await _db.batch((batch) {
      batch.insertAll(
        _db.questionRows,
        seeds.map((q) => q.toCompanion()),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Questions eligible to appear in the feed.
  ///
  /// Excludes reported content and anything in [excludeIds] (the ids already
  /// queued in the current session), so the buffer never shows a duplicate.
  Future<List<QuestionWithState>> candidates({
    Set<String> excludeIds = const {},
    Set<Category> categories = const {},
    int limit = 200,
  }) async {
    final query = _db.select(_db.questionRows).join([
      leftOuterJoin(
        _db.questionInteractions,
        _db.questionInteractions.questionId.equalsExp(_db.questionRows.id),
      ),
    ])..where(_db.questionRows.reported.equals(false));

    if (categories.isNotEmpty) {
      query.where(
        _db.questionRows.category.isIn(categories.map((c) => c.id).toList()),
      );
    }
    if (excludeIds.isNotEmpty) {
      query.where(_db.questionRows.id.isNotIn(excludeIds.toList()));
    }
    query.limit(limit);

    final rows = await query.get();
    return rows
        .map(
          (row) => QuestionWithState(
            question: row.readTable(_db.questionRows).toDomain(),
            interaction: row.readTableOrNull(_db.questionInteractions),
          ),
        )
        .toList(growable: false);
  }

  Future<Question?> byId(String id) async {
    final row = await (_db.select(
      _db.questionRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toDomain();
  }

  /// Inserts validated questions, ignoring ids that already exist.
  ///
  /// Returns the number actually written, which the AI usage counters record
  /// so we can see how much generated content survived validation.
  Future<int> insertAll(List<Question> questions) async {
    if (questions.isEmpty) return 0;
    final before = await _count();
    await _db.batch((batch) {
      batch.insertAll(
        _db.questionRows,
        questions.map((q) => q.toCompanion()),
        mode: InsertMode.insertOrIgnore,
      );
    });
    return await _count() - before;
  }

  Future<int> _count() => _db
      .customSelect('SELECT COUNT(*) AS c FROM question_rows')
      .map((row) => row.read<int>('c'))
      .getSingle();

  /// Question texts already stored, used to seed the duplicate check before
  /// generating more. Capped because the fingerprint comparison is O(n) per
  /// candidate and the newest content is what a generation run is most likely
  /// to collide with.
  Future<List<String>> recentQuestionTexts({int limit = 300}) async {
    final query = _db.select(_db.questionRows)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.question).toList(growable: false);
  }

  Stream<List<QuestionWithState>> watchSaved() {
    final query =
        _db.select(_db.questionRows).join([
            innerJoin(
              _db.questionInteractions,
              _db.questionInteractions.questionId.equalsExp(
                _db.questionRows.id,
              ),
            ),
          ])
          ..where(_db.questionInteractions.saved.equals(true))
          ..orderBy([OrderingTerm.desc(_db.questionInteractions.savedAt)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => QuestionWithState(
              question: row.readTable(_db.questionRows).toDomain(),
              interaction: row.readTable(_db.questionInteractions),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<QuestionInteraction?> interaction(String questionId) => (_db.select(
    _db.questionInteractions,
  )..where((t) => t.questionId.equals(questionId))).getSingleOrNull();

  Stream<QuestionInteraction?> watchInteraction(String questionId) =>
      (_db.select(
        _db.questionInteractions,
      )..where((t) => t.questionId.equals(questionId))).watchSingleOrNull();

  /// Records that a card was surfaced. Increments rather than sets, so the
  /// feed engine can deprioritise questions the user has already met.
  Future<void> markSeen(String questionId) async {
    await _upsert(
      questionId,
      QuestionInteractionsCompanion(
        timesSeen: const Value(1),
        lastSeenAt: Value(DateTime.now()),
        synced: const Value(false),
      ),
      incrementSeen: true,
    );
  }

  Future<void> markRevealed(String questionId) => _upsert(
    questionId,
    QuestionInteractionsCompanion(
      revealed: const Value(true),
      lastSeenAt: Value(DateTime.now()),
      synced: const Value(false),
    ),
  );

  Future<void> markCompleted(String questionId) => _upsert(
    questionId,
    QuestionInteractionsCompanion(
      completed: const Value(true),
      skipped: const Value(false),
      lastSeenAt: Value(DateTime.now()),
      synced: const Value(false),
    ),
  );

  Future<void> markSkipped(String questionId) => _upsert(
    questionId,
    QuestionInteractionsCompanion(
      skipped: const Value(true),
      lastSeenAt: Value(DateTime.now()),
      synced: const Value(false),
    ),
  );

  Future<void> setSaved(String questionId, {required bool saved}) => _upsert(
    questionId,
    QuestionInteractionsCompanion(
      saved: Value(saved),
      savedAt: Value(saved ? DateTime.now() : null),
      synced: const Value(false),
    ),
  );

  /// Records a graded answer and schedules the next review.
  ///
  /// Called from Practice modes, where an answer is actually assessed. The
  /// plain feed never calls this — revealing an answer is not evidence you
  /// knew it, so it must not advance a review stage.
  Future<ReviewSchedule> recordAnswer(
    String questionId, {
    required bool correct,
    DateTime? now,
  }) async {
    final existing = await interaction(questionId);
    final schedule = SpacedRepetition.next(
      currentStage: existing?.reviewStage ?? 0,
      correct: correct,
      now: now,
    );

    await _upsert(
      questionId,
      QuestionInteractionsCompanion(
        lastAnswerCorrect: Value(correct),
        completed: const Value(true),
        reviewStage: Value(schedule.stage),
        reviewDueAt: Value(schedule.dueAt),
        lastSeenAt: Value(now ?? DateTime.now()),
        synced: const Value(false),
      ),
    );

    return schedule;
  }

  /// Questions currently due for review, soonest first.
  Future<List<QuestionWithState>> dueForReview({
    int limit = 20,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();

    final query =
        _db.select(_db.questionRows).join([
            innerJoin(
              _db.questionInteractions,
              _db.questionInteractions.questionId.equalsExp(
                _db.questionRows.id,
              ),
            ),
          ])
          ..where(_db.questionRows.reported.equals(false))
          ..where(
            _db.questionInteractions.reviewDueAt.isSmallerOrEqualValue(clock),
          )
          ..orderBy([OrderingTerm.asc(_db.questionInteractions.reviewDueAt)])
          ..limit(limit);

    final rows = await query.get();
    return rows
        .map(
          (row) => QuestionWithState(
            question: row.readTable(_db.questionRows).toDomain(),
            interaction: row.readTable(_db.questionInteractions),
          ),
        )
        .toList(growable: false);
  }

  /// Interaction rows not yet mirrored to Firestore.
  ///
  /// Capped per call so a device that has been offline for a month uploads in
  /// batches rather than assembling one enormous write.
  Future<List<QuestionInteraction>> unsyncedInteractions({int limit = 400}) =>
      (_db.select(_db.questionInteractions)
            ..where((t) => t.synced.equals(false))
            ..limit(limit))
          .get();

  /// Marks rows as mirrored. Called only after the remote write succeeds, so a
  /// failed upload is retried rather than silently dropped.
  Future<void> markSynced(Iterable<String> questionIds) async {
    final ids = questionIds.toList(growable: false);
    if (ids.isEmpty) return;

    await (_db.update(_db.questionInteractions)
          ..where((t) => t.questionId.isIn(ids)))
        .write(const QuestionInteractionsCompanion(synced: Value(true)));
  }

  /// Applies a remote interaction on top of the local one.
  ///
  /// Resolution is last-write-wins on `lastSeenAt`, with two exceptions that
  /// are merged instead: `timesSeen` takes the larger count, and `saved` is
  /// true if either side has it. Both are additive facts — losing a bookmark
  /// because another device wrote later would be a bug, not a resolution.
  Future<void> mergeRemoteInteraction({
    required String questionId,
    required int timesSeen,
    required bool revealed,
    required bool completed,
    required bool saved,
    DateTime? savedAt,
    DateTime? lastSeenAt,
    bool? lastAnswerCorrect,
    int reviewStage = 0,
    DateTime? reviewDueAt,
  }) async {
    await _db.transaction(() async {
      final local = await interaction(questionId);

      final remoteIsNewer =
          local?.lastSeenAt == null ||
          (lastSeenAt != null && lastSeenAt.isAfter(local!.lastSeenAt!));

      final merged = QuestionInteractionsCompanion(
        timesSeen: Value(
          timesSeen > (local?.timesSeen ?? 0) ? timesSeen : local!.timesSeen,
        ),
        revealed: Value(revealed || (local?.revealed ?? false)),
        completed: Value(completed || (local?.completed ?? false)),
        saved: Value(saved || (local?.saved ?? false)),
        savedAt: Value(savedAt ?? local?.savedAt),
        lastSeenAt: Value(
          remoteIsNewer ? lastSeenAt : (local?.lastSeenAt ?? lastSeenAt),
        ),
        lastAnswerCorrect: Value(
          remoteIsNewer ? lastAnswerCorrect : local?.lastAnswerCorrect,
        ),
        reviewStage: Value(
          remoteIsNewer ? reviewStage : (local?.reviewStage ?? reviewStage),
        ),
        reviewDueAt: Value(
          remoteIsNewer ? reviewDueAt : (local?.reviewDueAt ?? reviewDueAt),
        ),
        // Just reconciled with the server, so nothing is pending.
        synced: const Value(true),
      );

      if (local == null) {
        await _db
            .into(_db.questionInteractions)
            .insert(merged.copyWith(questionId: Value(questionId)));
      } else {
        await (_db.update(
          _db.questionInteractions,
        )..where((t) => t.questionId.equals(questionId))).write(merged);
      }
    });
  }

  /// Wipes all local user state. Part of account deletion and sign-out.
  Future<void> clearUserState() async {
    await _db.delete(_db.questionInteractions).go();
    await _db.delete(_db.generatedContentRows).go();
    await _db.delete(_db.topicFamiliarityRows).go();
  }

  /// Full-text-ish search across the local pool.
  ///
  /// Local rather than AI-backed, per the product rule: the entire corpus is
  /// already on-device, so a substring match is instant, works offline, and
  /// costs nothing. Spending an AI request to find a question the user could
  /// see by scrolling would be the wrong trade.
  ///
  /// Results are ranked by where the match lands — a hit in the question
  /// itself matters more than one buried in the technical detail.
  Future<List<QuestionWithState>> search(String query, {int limit = 60}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    // Escape LIKE wildcards so a user typing "100%" searches for that text
    // rather than matching everything.
    final escaped = trimmed
        .toLowerCase()
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';

    final rows = await _db
        .customSelect(
          '''
      SELECT q.*,
             CASE
               WHEN LOWER(q.question) LIKE :pattern ESCAPE '\\' THEN 0
               WHEN LOWER(q.subcategory) LIKE :pattern ESCAPE '\\' THEN 1
               WHEN LOWER(q.tags) LIKE :pattern ESCAPE '\\' THEN 2
               WHEN LOWER(q.short_answer) LIKE :pattern ESCAPE '\\' THEN 3
               ELSE 4
             END AS rank
      FROM question_rows q
      WHERE q.reported = 0 AND (
            LOWER(q.question)          LIKE :pattern ESCAPE '\\'
         OR LOWER(q.short_answer)      LIKE :pattern ESCAPE '\\'
         OR LOWER(q.why_it_matters)    LIKE :pattern ESCAPE '\\'
         OR LOWER(q.technical_details) LIKE :pattern ESCAPE '\\'
         OR LOWER(q.category)          LIKE :pattern ESCAPE '\\'
         OR LOWER(q.subcategory)       LIKE :pattern ESCAPE '\\'
         OR LOWER(q.tags)              LIKE :pattern ESCAPE '\\'
      )
      ORDER BY rank ASC, q.created_at DESC
      LIMIT :limit
      ''',
          variables: [Variable.withString(pattern), Variable.withInt(limit)],
          readsFrom: {_db.questionRows},
        )
        .get();

    final questions = rows
        .map((row) => _db.questionRows.map(row.data).toDomain())
        .toList(growable: false);

    // Attach interaction state so results can show saved/completed badges.
    final states = <String, QuestionInteraction>{};
    if (questions.isNotEmpty) {
      final found =
          await (_db.select(_db.questionInteractions)..where(
                (t) => t.questionId.isIn(questions.map((q) => q.id).toList()),
              ))
              .get();
      for (final row in found) {
        states[row.questionId] = row;
      }
    }

    return questions
        .map((q) => QuestionWithState(question: q, interaction: states[q.id]))
        .toList(growable: false);
  }

  Future<void> report(String questionId) async {
    await (_db.update(_db.questionRows)..where((t) => t.id.equals(questionId)))
        .write(const QuestionRowsCompanion(reported: Value(true)));
  }

  /// Upserts one interaction row.
  ///
  /// [incrementSeen] exists because `timesSeen` is the one field that must
  /// accumulate; everything else is a straight overwrite.
  Future<void> _upsert(
    String questionId,
    QuestionInteractionsCompanion changes, {
    bool incrementSeen = false,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.questionInteractions,
      )..where((t) => t.questionId.equals(questionId))).getSingleOrNull();

      if (existing == null) {
        // Carry the whole companion through rather than copying named fields.
        // Enumerating them means every column added later is silently dropped
        // on first write — which is exactly how a review schedule set on a
        // never-before-seen question would vanish. Absent values fall back to
        // the column defaults declared in `tables.dart`.
        await _db
            .into(_db.questionInteractions)
            .insert(
              changes.copyWith(
                questionId: Value(questionId),
                timesSeen: incrementSeen
                    ? const Value(1)
                    : const Value.absent(),
              ),
            );
        return;
      }

      await (_db.update(
        _db.questionInteractions,
      )..where((t) => t.questionId.equals(questionId))).write(
        changes.copyWith(
          timesSeen: incrementSeen
              ? Value(existing.timesSeen + 1)
              : const Value.absent(),
        ),
      );
    });
  }

  /// Aggregate counters for the profile screen.
  Future<ProgressSummary> progressSummary() async {
    final row = await _db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM question_interactions WHERE times_seen > 0) AS viewed,
        (SELECT COUNT(*) FROM question_interactions WHERE completed = 1) AS completed,
        (SELECT COUNT(*) FROM question_interactions WHERE saved = 1) AS saved,
        (SELECT COUNT(*) FROM question_rows) AS total
      ''').getSingle();

    return ProgressSummary(
      viewed: row.read<int>('viewed'),
      completed: row.read<int>('completed'),
      saved: row.read<int>('saved'),
      totalAvailable: row.read<int>('total'),
    );
  }

  /// Per-category completion, used for the topic-familiarity bars.
  ///
  /// Deliberately a ratio of completed-to-seen and nothing cleverer — it is
  /// labelled "familiarity", not a skill measurement.
  Future<Map<Category, TopicProgress>> topicProgress() async {
    final rows = await _db.customSelect('''
      SELECT q.category AS category,
             SUM(CASE WHEN i.times_seen > 0 THEN 1 ELSE 0 END) AS seen,
             SUM(CASE WHEN i.completed = 1 THEN 1 ELSE 0 END) AS completed,
             COUNT(q.id) AS available
      FROM question_rows q
      LEFT JOIN question_interactions i ON i.question_id = q.id
      GROUP BY q.category
      ''').get();

    return {
      for (final row in rows)
        Category.fromId(row.read<String>('category')): TopicProgress(
          seen: row.read<int?>('seen') ?? 0,
          completed: row.read<int?>('completed') ?? 0,
          available: row.read<int>('available'),
        ),
    };
  }
}

class ProgressSummary {
  const ProgressSummary({
    required this.viewed,
    required this.completed,
    required this.saved,
    required this.totalAvailable,
  });

  final int viewed;
  final int completed;
  final int saved;
  final int totalAvailable;
}

class TopicProgress {
  const TopicProgress({
    required this.seen,
    required this.completed,
    required this.available,
  });

  final int seen;
  final int completed;
  final int available;

  /// 0–1. Familiarity is completion against what the user has actually met,
  /// falling back to coverage of the category when nothing has been seen yet.
  double get familiarity {
    if (seen == 0) return 0;
    return (completed / seen).clamp(0.0, 1.0);
  }
}
