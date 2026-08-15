import 'package:drift/native.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techbyte/core/analytics/analytics_service.dart';
import 'package:techbyte/core/providers/core_providers.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/feed/application/daily_session_controller.dart';
import 'package:techbyte/features/practice/application/practice_controller.dart';
import 'package:techbyte/features/practice/domain/answer_evaluation.dart';
import 'package:techbyte/features/practice/domain/debug_scenario.dart';
import 'package:techbyte/features/practice/domain/practice_mode.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';
import 'package:techbyte/services/ai/ai_result.dart';
import 'package:techbyte/services/ai/ai_usage_tracker.dart';
import 'package:techbyte/services/ai/gemini_service.dart';

import '../helpers/sqlite_test_setup.dart';

class _MockFirebaseAI extends Mock implements FirebaseAI {}

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

/// Reproduces what App Check does to this app.
///
/// `FirebaseAppCheck.getToken()` throws a `FirebaseException` while the
/// request headers are being built — before Gemini is reached, and from a
/// different plugin than the one whose errors the AI layer knows about.
class _AttestationFailure extends GeminiService {
  _AttestationFailure({required super.usageTracker, required super.firebaseAI});

  @override
  Future<AiResult<DebugScenario>> generateDebugScenario({
    List<Category> categories = const [],
    List<String> avoidTitles = const [],
  }) async {
    throw FirebaseException(
      plugin: 'firebase_app_check',
      code: 'unknown',
      message: 'Error returned from API. code: 403 body: App attestation '
          'failed.',
    );
  }

  @override
  Future<AiResult<AnswerEvaluation>> evaluateAnswer({
    required PracticeMode mode,
    required String question,
    required String referenceAnswer,
    required String userAnswer,
  }) async {
    throw FirebaseException(
      plugin: 'firebase_app_check',
      code: 'unknown',
      message: 'Error returned from API. code: 403 body: App attestation '
          'failed.',
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        analyticsServiceProvider.overrideWithValue(
          AnalyticsService(analytics: _MockFirebaseAnalytics(), enabled: false),
        ),
        geminiServiceProvider.overrideWithValue(
          _AttestationFailure(
            usageTracker: AiUsageTracker(db),
            firebaseAI: _MockFirebaseAI(),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('when the AI layer throws instead of returning', () {
    test('debugging still starts, on a bundled scenario', () async {
      await container
          .read(practiceControllerProvider.notifier)
          .start(PracticeMode.debugging);

      final state = container.read(practiceControllerProvider);

      // The regression: generation threw, the exception escaped every catch
      // between here and the screen, and `isLoading` was never cleared — so
      // Practice → Debugging showed its skeleton forever.
      expect(state.isLoading, isFalse);
      expect(state.hasTask, isTrue, reason: 'should fall back to a seed');
      expect(state.task, isA<DebugTask>());
    });

    test('grading fails as a notice rather than a stuck spinner', () async {
      await container
          .read(practiceControllerProvider.notifier)
          .start(PracticeMode.debugging);

      await container
          .read(practiceControllerProvider.notifier)
          .submit(
            'I would check the connection pool before adding more replicas.',
          );

      final state = container.read(practiceControllerProvider);
      expect(state.isGrading, isFalse);
      expect(state.notice, isNotNull);
      expect(state.evaluation, isNull);
    });
  });

  group('session bookkeeping', () {
    test('skipping advances without counting as an answer', () async {
      final notifier = container.read(practiceControllerProvider.notifier);
      await notifier.start(PracticeMode.debugging);
      await notifier.skip();

      final state = container.read(practiceControllerProvider);
      expect(state.skipped, 1);
      expect(state.completed, 0);
      expect(state.isLoading, isFalse);
    });

    test('an answer too short to grade is not sent', () async {
      final notifier = container.read(practiceControllerProvider.notifier);
      await notifier.start(PracticeMode.debugging);
      await notifier.submit('no');

      // Short-circuited before the throwing service, so there is no notice —
      // which is also the proof that no AI request was spent on it.
      final state = container.read(practiceControllerProvider);
      expect(state.notice, isNull);
      expect(state.isGrading, isFalse);
    });
  });
}
