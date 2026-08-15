import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../../features/practice/domain/practice_mode.dart';
import '../../features/questions/domain/question.dart';
import '../../services/ai/ai_result.dart';
import 'analytics_events.dart';

/// The only thing in the app that talks to Firebase Analytics.
///
/// Two rules shape this class:
///
///   1. **No personal data.** Question text, answer text, email and display
///      name never leave the device. Only taxonomy values, scores and counts
///      are recorded — enough to see which content works, not who read it.
///   2. **Never throws.** Analytics failing must not break a swipe, so every
///      call is fire-and-forget and errors are swallowed rather than surfaced.
class AnalyticsService {
  AnalyticsService({FirebaseAnalytics? analytics, bool? enabled})
    : _analytics = analytics ?? FirebaseAnalytics.instance,
      // Disabled in debug so development traffic does not pollute real
      // product metrics. Matches the Crashlytics policy in FirebaseBootstrap.
      _enabled = enabled ?? !kDebugMode;

  final FirebaseAnalytics _analytics;
  final bool _enabled;

  /// Logs an event. Never awaited by callers on a hot path.
  Future<void> log(
    AnalyticsEvent event, [
    Map<String, Object>? parameters,
  ]) async {
    if (!_enabled) return;
    try {
      await _analytics.logEvent(name: event.name, parameters: parameters);
    } on Exception catch (e) {
      debugPrint('Analytics ${event.name} failed: $e');
    }
  }

  // ---- Feed ------------------------------------------------------------

  Future<void> appOpened() => log(AnalyticsEvent.appOpened);

  Future<void> feedStarted() => log(AnalyticsEvent.feedStarted);

  Future<void> questionViewed(Question question) =>
      log(AnalyticsEvent.questionViewed, _questionParams(question));

  Future<void> answerRevealed(Question question) =>
      log(AnalyticsEvent.answerRevealed, _questionParams(question));

  Future<void> questionCompleted(Question question) =>
      log(AnalyticsEvent.questionCompleted, _questionParams(question));

  Future<void> questionSkipped(Question question) =>
      log(AnalyticsEvent.questionSkipped, _questionParams(question));

  Future<void> questionSaved(Question question) =>
      log(AnalyticsEvent.questionSaved, _questionParams(question));

  Future<void> questionShared(Question question) =>
      log(AnalyticsEvent.questionShared, _questionParams(question));

  Future<void> questionReported(Question question) =>
      log(AnalyticsEvent.questionReported, _questionParams(question));

  // ---- Derived content -------------------------------------------------

  Future<void> deepDiveOpened(Question question) =>
      log(AnalyticsEvent.deepDiveOpened, _questionParams(question));

  Future<void> explanationRequested(Question question, String style) => log(
    AnalyticsEvent.explanationRequested,
    {..._questionParams(question), AnalyticsParam.style: style},
  );

  // ---- Practice --------------------------------------------------------

  Future<void> practiceStarted(PracticeMode mode) => log(
    switch (mode) {
      PracticeMode.interview => AnalyticsEvent.interviewStarted,
      PracticeMode.debugging => AnalyticsEvent.debugStarted,
    },
    {AnalyticsParam.mode: mode.id},
  );

  /// Scores are rounded to whole numbers before logging.
  ///
  /// A one-decimal score across many users is close to a fingerprint of a
  /// specific answer; the integer is all that product analysis needs.
  Future<void> practiceCompleted(
    PracticeMode mode, {
    required double score,
    required bool passed,
  }) => log(
    switch (mode) {
      PracticeMode.interview => AnalyticsEvent.interviewCompleted,
      PracticeMode.debugging => AnalyticsEvent.debugCompleted,
    },
    {
      AnalyticsParam.mode: mode.id,
      AnalyticsParam.score: score.round(),
      AnalyticsParam.passed: passed.toString(),
    },
  );

  Future<void> reviewAnswered({required bool correct, required int stage}) =>
      log(AnalyticsEvent.reviewAnswered, {
        AnalyticsParam.correct: correct.toString(),
        AnalyticsParam.stage: stage,
      });

  Future<void> dailySessionCompleted(int count) =>
      log(AnalyticsEvent.dailySessionCompleted, {AnalyticsParam.count: count});

  // ---- AI --------------------------------------------------------------

  Future<void> generationSucceeded(int accepted) => log(
    AnalyticsEvent.aiGenerationSucceeded,
    {AnalyticsParam.count: accepted},
  );

  /// Records *why* generation was unavailable, which is the signal that shows
  /// whether the free-tier budget is actually sufficient in practice.
  Future<void> generationUnavailable(AiUnavailableReason reason) => log(
    AnalyticsEvent.aiGenerationUnavailable,
    {AnalyticsParam.reason: reason.name},
  );

  // ---- Lifecycle -------------------------------------------------------

  Future<void> onboardingCompleted() => log(AnalyticsEvent.onboardingCompleted);

  Future<void> signedIn() => log(AnalyticsEvent.signedIn);

  Future<void> signedOut() => log(AnalyticsEvent.signedOut);

  /// Associates events with a stable user id.
  ///
  /// The Firebase UID is an opaque identifier that carries no personal
  /// information on its own, unlike an email address, which is why it is the
  /// only identifier ever sent.
  Future<void> setUser(String? uid) async {
    if (!_enabled) return;
    try {
      await _analytics.setUserId(id: uid);
    } on Exception catch (e) {
      debugPrint('Analytics setUserId failed: $e');
    }
  }

  static Map<String, Object> _questionParams(Question question) => {
    AnalyticsParam.category: question.category.id,
    AnalyticsParam.questionType: question.type.id,
    AnalyticsParam.difficulty: question.difficulty.id,
    AnalyticsParam.source: question.source.id,
  };
}
