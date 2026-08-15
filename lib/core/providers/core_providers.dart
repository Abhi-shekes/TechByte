import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/questions/data/question_repository.dart';
import '../../features/settings/data/preferences_repository.dart';
import '../../features/settings/domain/user_preferences.dart';
import '../../services/ai/ai_usage_tracker.dart';
import '../../services/ai/gemini_service.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/sync/sync_service.dart';
import '../storage/app_database.dart';

/// Overridden in `main` once SharedPreferences has loaded.
///
/// Kept synchronous so every consumer — including the theme, which is needed
/// for the very first frame — can read preferences without an async boundary.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(sharedPreferencesProvider)),
);

final questionRepositoryProvider = Provider<QuestionRepository>(
  (ref) => QuestionRepository(ref.watch(appDatabaseProvider)),
);

final aiUsageTrackerProvider = Provider<AiUsageTracker>(
  (ref) => AiUsageTracker(ref.watch(appDatabaseProvider)),
);

final geminiServiceProvider = Provider<GeminiService>(
  (ref) => GeminiService(usageTracker: ref.watch(aiUsageTrackerProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(questions: ref.watch(questionRepositoryProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// The signed-in user, or null. Drives routing.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// User preferences, held in memory and written through on every change.
final userPreferencesProvider =
    NotifierProvider<UserPreferencesNotifier, UserPreferences>(
      UserPreferencesNotifier.new,
    );

class UserPreferencesNotifier extends Notifier<UserPreferences> {
  @override
  UserPreferences build() => ref.watch(preferencesRepositoryProvider).load();

  Future<void> update(
    UserPreferences Function(UserPreferences current) transform,
  ) async {
    final next = transform(state);
    state = next;
    await ref.read(preferencesRepositoryProvider).save(next);
  }

  Future<void> completeOnboarding() =>
      update((p) => p.copyWith(onboardingComplete: true));
}

/// Remaining local AI budget for today, for the profile screen.
final aiBudgetRemainingProvider = FutureProvider<int>(
  (ref) => ref.watch(aiUsageTrackerProvider).remainingBudget(),
);
