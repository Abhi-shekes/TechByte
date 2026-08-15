import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/feed_config.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/providers/core_providers.dart';
import '../domain/daily_session.dart';

final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => AnalyticsService(),
);

final dailySessionProvider =
    AsyncNotifierProvider<DailySessionController, DailySession>(
      DailySessionController.new,
    );

/// Owns "Today's Tech 10".
///
/// The question ids are persisted for the day so the set survives a restart.
/// Completion is *derived* from the interaction table rather than stored
/// separately — one source of truth for "did you finish this question" means
/// the daily card can never disagree with the feed.
class DailySessionController extends AsyncNotifier<DailySession> {
  static const _kIdsKey = 'daily.questionIds';
  static const _kDateKey = 'daily.date';

  @override
  Future<DailySession> build() async {
    final repo = ref.watch(questionRepositoryProvider);
    await repo.ensureSeeded();

    final prefs = ref.watch(sharedPreferencesProvider);
    final today = DailySessionBuilder.normalise(DateTime.now());
    final storedDate = DateTime.tryParse(prefs.getString(_kDateKey) ?? '');
    final storedIds = prefs.getStringList(_kIdsKey);

    final pool = await repo.candidates(limit: 400);
    final completed = await _completedIds();

    // Same day and the stored ids still resolve → reuse them.
    if (storedDate != null &&
        DailySessionBuilder.normalise(storedDate) == today &&
        storedIds != null &&
        storedIds.isNotEmpty) {
      final known = pool.map((p) => p.question.id).toSet();
      final surviving = storedIds.where(known.contains).toList(growable: false);

      if (surviving.length == storedIds.length) {
        return DailySession(
          date: today,
          questionIds: surviving,
          completedIds: completed,
        );
      }
      // Some questions were reported away since this morning; fall through and
      // rebuild rather than showing a short session.
    }

    final session = DailySessionBuilder.build(
      date: today,
      pool: pool,
      count: DailySessionConfig.questionCount,
      completedIds: completed,
    );

    await _persist(prefs, session);
    return session;
  }

  Future<Set<String>> _completedIds() async {
    final repo = ref.read(questionRepositoryProvider);
    final all = await repo.candidates(limit: 400);
    return all.where((c) => c.isCompleted).map((c) => c.question.id).toSet();
  }

  Future<void> _persist(SharedPreferences prefs, DailySession session) async {
    await prefs.setString(_kDateKey, session.date.toIso8601String());
    await prefs.setStringList(_kIdsKey, session.questionIds);
  }

  /// Recomputes completion. Called when returning to the home tab.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;

    final completed = await _completedIds();
    final wasComplete = current.isComplete;
    final next = current.copyWith(completedIds: completed);

    if (!wasComplete && next.isComplete) {
      await ref
          .read(analyticsServiceProvider)
          .dailySessionCompleted(next.total);
    }

    state = AsyncData(next);
  }
}
