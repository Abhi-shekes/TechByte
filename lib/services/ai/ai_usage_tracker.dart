import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../../app/config/ai_config.dart';
import '../../core/storage/app_database.dart';

/// Tracks AI usage locally and decides whether another request is allowed.
///
/// This is the enforcement half of the free-tier requirement. The provider has
/// its own quota, but relying on it means discovering the limit by being
/// rejected. Counting locally lets the app stop first, and lets it tell the
/// user honestly why generation paused.
class AiUsageTracker {
  AiUsageTracker(this._db);

  final AppDatabase _db;

  static final _dayFormat = DateFormat('yyyy-MM-dd');

  /// Set when a provider quota error is seen; suppresses further attempts
  /// until it elapses. In memory only — a restart retries once, which is the
  /// behaviour you want if the quota window has since rolled over.
  DateTime? _backoffUntil;

  String get _today => _dayFormat.format(DateTime.now().toUtc());

  /// Whether a generation request may be made right now.
  Future<bool> canRequest() async {
    final backoff = _backoffUntil;
    if (backoff != null && DateTime.now().isBefore(backoff)) return false;

    final usage = await todayUsage();
    return usage.requests < AiConfig.dailyRequestBudget;
  }

  /// Requests remaining in today's local budget.
  Future<int> remainingBudget() async {
    final usage = await todayUsage();
    return (AiConfig.dailyRequestBudget - usage.requests).clamp(
      0,
      AiConfig.dailyRequestBudget,
    );
  }

  Future<AiUsageRow> todayUsage() async {
    final day = _today;
    final existing = await (_db.select(
      _db.aiUsageRows,
    )..where((t) => t.day.equals(day))).getSingleOrNull();
    if (existing != null) return existing;

    await _db
        .into(_db.aiUsageRows)
        .insert(
          AiUsageRowsCompanion.insert(day: day),
          mode: InsertMode.insertOrIgnore,
        );
    return (_db.select(
      _db.aiUsageRows,
    )..where((t) => t.day.equals(day))).getSingle();
  }

  Future<void> recordRequest() => _increment(requests: 1);

  Future<void> recordFailure({required bool isQuota}) async {
    if (isQuota) {
      _backoffUntil = DateTime.now().add(AiConfig.quotaBackoff);
    }
    await _increment(failures: 1, quotaFailures: isQuota ? 1 : 0);
  }

  Future<void> recordCacheHit() => _increment(cacheHits: 1);

  Future<void> recordGenerationOutcome({
    required int accepted,
    required int rejected,
  }) => _increment(questionsGenerated: accepted, questionsRejected: rejected);

  /// Clears the quota backoff. Exposed for an explicit user-initiated retry.
  void clearBackoff() => _backoffUntil = null;

  Future<void> _increment({
    int requests = 0,
    int failures = 0,
    int quotaFailures = 0,
    int cacheHits = 0,
    int questionsGenerated = 0,
    int questionsRejected = 0,
  }) async {
    final day = _today;
    await _db.transaction(() async {
      final current = await todayUsage();
      await (_db.update(
        _db.aiUsageRows,
      )..where((t) => t.day.equals(day))).write(
        AiUsageRowsCompanion(
          requests: Value(current.requests + requests),
          failures: Value(current.failures + failures),
          quotaFailures: Value(current.quotaFailures + quotaFailures),
          cacheHits: Value(current.cacheHits + cacheHits),
          questionsGenerated: Value(
            current.questionsGenerated + questionsGenerated,
          ),
          questionsRejected: Value(
            current.questionsRejected + questionsRejected,
          ),
        ),
      );
    });
  }
}
