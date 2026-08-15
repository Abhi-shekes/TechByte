import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../questions/domain/question_enums.dart';
import '../domain/user_preferences.dart';

/// Persists [UserPreferences] locally.
///
/// SharedPreferences rather than the database: these are a handful of scalars
/// read once at startup, and keeping them out of Drift means the theme and
/// onboarding state are available before the database is opened.
class PreferencesRepository {
  PreferencesRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kTopics = 'prefs.topics';
  static const _kLevel = 'prefs.level';
  static const _kGoal = 'prefs.goal';
  static const _kThemeMode = 'prefs.themeMode';
  static const _kHaptics = 'prefs.haptics';
  static const _kReducedMotion = 'prefs.reducedMotion';
  static const _kAiEnabled = 'prefs.aiEnabled';
  static const _kDailyReminder = 'prefs.dailyReminder';
  static const _kReminderHour = 'prefs.reminderHour';
  static const _kReminderMinute = 'prefs.reminderMinute';
  static const _kOnboardingComplete = 'prefs.onboardingComplete';

  UserPreferences load() {
    return UserPreferences(
      topics: (_prefs.getStringList(_kTopics) ?? const [])
          .map(Category.tryFromId)
          .nonNulls
          .toSet(),
      level: ExperienceLevel.fromId(_prefs.getString(_kLevel) ?? ''),
      goal: LearningGoal.fromId(_prefs.getString(_kGoal) ?? ''),
      themeMode: switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      hapticsEnabled: _prefs.getBool(_kHaptics) ?? true,
      reducedMotion: _prefs.getBool(_kReducedMotion) ?? false,
      aiGenerationEnabled: _prefs.getBool(_kAiEnabled) ?? true,
      dailyReminderEnabled: _prefs.getBool(_kDailyReminder) ?? false,
      reminderHour: _prefs.getInt(_kReminderHour) ?? 9,
      reminderMinute: _prefs.getInt(_kReminderMinute) ?? 30,
      onboardingComplete: _prefs.getBool(_kOnboardingComplete) ?? false,
    );
  }

  Future<void> save(UserPreferences prefs) async {
    await Future.wait([
      _prefs.setStringList(
        _kTopics,
        prefs.topics.map((c) => c.id).toList(growable: false),
      ),
      _prefs.setString(_kLevel, prefs.level.id),
      _prefs.setString(_kGoal, prefs.goal.id),
      _prefs.setString(_kThemeMode, prefs.themeMode.name),
      _prefs.setBool(_kHaptics, prefs.hapticsEnabled),
      _prefs.setBool(_kReducedMotion, prefs.reducedMotion),
      _prefs.setBool(_kAiEnabled, prefs.aiGenerationEnabled),
      _prefs.setBool(_kDailyReminder, prefs.dailyReminderEnabled),
      _prefs.setInt(_kReminderHour, prefs.reminderHour),
      _prefs.setInt(_kReminderMinute, prefs.reminderMinute),
      _prefs.setBool(_kOnboardingComplete, prefs.onboardingComplete),
    ]);
  }

  /// Wipes local preferences. Part of account deletion.
  Future<void> clear() async {
    await Future.wait([
      _prefs.remove(_kTopics),
      _prefs.remove(_kLevel),
      _prefs.remove(_kGoal),
      _prefs.remove(_kThemeMode),
      _prefs.remove(_kHaptics),
      _prefs.remove(_kReducedMotion),
      _prefs.remove(_kAiEnabled),
      _prefs.remove(_kDailyReminder),
      _prefs.remove(_kReminderHour),
      _prefs.remove(_kReminderMinute),
      _prefs.remove(_kOnboardingComplete),
    ]);
  }
}
