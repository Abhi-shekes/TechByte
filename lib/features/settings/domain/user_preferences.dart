import 'package:flutter/material.dart';

import '../../questions/domain/question_enums.dart';

/// Everything the user chose in onboarding or settings.
///
/// Deliberately small and local. These values shape the feed but are not
/// required for it to work, so a first launch with defaults is a perfectly good
/// experience and onboarding can be skipped.
@immutable
class UserPreferences {
  const UserPreferences({
    this.topics = const {},
    this.level = ExperienceLevel.intermediate,
    this.goal = LearningGoal.all,
    this.themeMode = ThemeMode.system,
    this.hapticsEnabled = true,
    this.reducedMotion = false,
    this.aiGenerationEnabled = true,
    this.dailyReminderEnabled = false,
    this.reminderHour = 9,
    this.reminderMinute = 30,
    this.onboardingComplete = false,
  });

  /// Categories the user opted into. Empty means "everything", which is also
  /// the default — the feed is at its best when it can range widely.
  final Set<Category> topics;

  final ExperienceLevel level;
  final LearningGoal goal;
  final ThemeMode themeMode;
  final bool hapticsEnabled;

  /// Honoured alongside the platform's own reduce-motion setting.
  final bool reducedMotion;

  /// User-facing kill switch for AI generation. The app remains fully usable
  /// with this off — it simply stops adding new questions to the local pool.
  final bool aiGenerationEnabled;

  /// Off by default. A learning app that starts nagging on day one is a
  /// learning app people uninstall on day two.
  final bool dailyReminderEnabled;

  final int reminderHour;
  final int reminderMinute;

  final bool onboardingComplete;

  UserPreferences copyWith({
    Set<Category>? topics,
    ExperienceLevel? level,
    LearningGoal? goal,
    ThemeMode? themeMode,
    bool? hapticsEnabled,
    bool? reducedMotion,
    bool? aiGenerationEnabled,
    bool? dailyReminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? onboardingComplete,
  }) {
    return UserPreferences(
      topics: topics ?? this.topics,
      level: level ?? this.level,
      goal: goal ?? this.goal,
      themeMode: themeMode ?? this.themeMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      aiGenerationEnabled: aiGenerationEnabled ?? this.aiGenerationEnabled,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
}
