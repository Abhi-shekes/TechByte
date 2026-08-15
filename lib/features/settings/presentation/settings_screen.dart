import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/ai_config.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../feed/application/daily_session_controller.dart';

/// Everything the user can change.
///
/// Split out of Profile, which had grown to eleven decision points in one
/// unbroken scroll — identity, stats, a History link, topic familiarity, seven
/// controls, sign-out and account deletion. Profile now answers "how am I
/// doing?"; this answers "how does it behave?".
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(userPreferencesProvider);
    final budget = ref.watch(aiBudgetRemainingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: Space.pagePadding,
        children: [
          const SectionHeader('Appearance'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Theme'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {prefs.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => ref
                  .read(userPreferencesProvider.notifier)
                  .update((p) => p.copyWith(themeMode: selection.first)),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce motion'),
            subtitle: const Text('Turns off every animation in the app.'),
            value: prefs.reducedMotion,
            onChanged: (value) => ref
                .read(userPreferencesProvider.notifier)
                .update((p) => p.copyWith(reducedMotion: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Haptics'),
            value: prefs.hapticsEnabled,
            onChanged: (value) => ref
                .read(userPreferencesProvider.notifier)
                .update((p) => p.copyWith(hapticsEnabled: value)),
          ),

          const SizedBox(height: Space.xxl),
          const SectionHeader('Reminders'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Daily reminder'),
            subtitle: Text(
              prefs.dailyReminderEnabled
                  ? 'Every day at '
                        '${_formatTime(prefs.reminderHour, prefs.reminderMinute)}'
                  : 'A nudge when your daily set is ready',
            ),
            value: prefs.dailyReminderEnabled,
            onChanged: (value) => _setReminder(context, ref, enabled: value),
          ),
          if (prefs.dailyReminderEnabled) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reminder time'),
              trailing: TextButton(
                onPressed: () => _pickTime(context, ref),
                child: Text(
                  _formatTime(prefs.reminderHour, prefs.reminderMinute),
                ),
              ),
            ),
            const _ReminderStatus(),
          ],

          const SizedBox(height: Space.xxl),
          const SectionHeader('Content'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Generate new questions with AI'),
            subtitle: Text(switch (budget) {
              // Reads the real ceiling rather than the '40' that was hardcoded
              // in the widget layer and would have drifted silently.
              AsyncData(:final value) =>
                '$value of ${AiConfig.dailyRequestBudget} requests left today',
              _ => 'Uses only the free Gemini tier',
            }),
            value: prefs.aiGenerationEnabled,
            onChanged: (value) => ref
                .read(userPreferencesProvider.notifier)
                .update((p) => p.copyWith(aiGenerationEnabled: value)),
          ),

          const SizedBox(height: Space.xxl),
          const SectionHeader('Account'),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            onPressed: () => _signOut(ref),
          ),

          // Deletion is separated by a full section break and boxed in its own
          // danger region. It previously sat ten pixels below Sign out.
          const SizedBox(height: Space.giant),
          AppPanel(
            accent: theme.colorScheme.error,
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delete account', style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.sm),
                Text(
                  'Permanently removes your account and everything stored with '
                  'it. This cannot be undone.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.lg),
                OutlinedButton(
                  onPressed: () => _confirmDelete(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size(0, Sizes.buttonMd),
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Flushes pending changes before signing out, so work done on this device
  /// is not stranded locally behind a sign-out.
  Future<void> _signOut(WidgetRef ref) async {
    final uid = ref.read(authStateProvider).value?.uid;
    await ref.read(syncServiceProvider).push(uid: uid);
    unawaited(ref.read(analyticsServiceProvider).signedOut());
    unawaited(ref.read(analyticsServiceProvider).setUser(null));
    await ref.read(authRepositoryProvider).signOut();
  }

  static String _formatTime(int hour, int minute) {
    final period = hour < 12 ? 'am' : 'pm';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Toggling the reminder on asks for permission first.
  ///
  /// If permission is refused the switch stays off rather than showing as on
  /// while nothing would ever arrive — a toggle that lies is worse than one
  /// that refuses.
  Future<void> _setReminder(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final notifications = ref.read(notificationServiceProvider);

    if (!enabled) {
      await notifications.cancelDailyReminder();
      await ref
          .read(userPreferencesProvider.notifier)
          .update((p) => p.copyWith(dailyReminderEnabled: false));
      return;
    }

    final granted = await notifications.requestPermission();
    if (!context.mounted) return;

    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are blocked for TechByte in Android settings.',
          ),
        ),
      );
      return;
    }

    final prefs = ref.read(userPreferencesProvider);
    await notifications.scheduleDailyReminder(
      hour: prefs.reminderHour,
      minute: prefs.reminderMinute,
    );
    await ref
        .read(userPreferencesProvider.notifier)
        .update((p) => p.copyWith(dailyReminderEnabled: true));
  }

  Future<void> _pickTime(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(userPreferencesProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: prefs.reminderHour,
        minute: prefs.reminderMinute,
      ),
    );
    if (picked == null) return;

    await ref
        .read(userPreferencesProvider.notifier)
        .update(
          (p) => p.copyWith(
            reminderHour: picked.hour,
            reminderMinute: picked.minute,
          ),
        );
    // Rescheduling replaces the existing alarm, since the id is the same.
    await ref
        .read(notificationServiceProvider)
        .scheduleDailyReminder(hour: picked.hour, minute: picked.minute);
  }

  static Future<void> _sendTest(BuildContext context, WidgetRef ref) async {
    final sent = await ref
        .read(notificationServiceProvider)
        .sendTestNotification();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Sent — check your notification shade.'
              : 'Could not post a notification. Check TechByte in Android '
                    'settings.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your TechByte account and the progress, '
          'saved questions and preferences stored with it. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Remote data must go before the auth user does: once the account is
    // deleted the rules no longer authorise the client to touch /users/{uid},
    // so the documents would be stranded permanently.
    final uid = ref.read(authStateProvider).value?.uid;
    await ref.read(syncServiceProvider).deleteRemoteData(uid: uid);

    final outcome = await ref.read(authRepositoryProvider).deleteAccount();
    if (!context.mounted) return;

    switch (outcome) {
      case AccountDeletionOutcome.deleted:
        // Local data is cleared so a different account signing in on this
        // device does not inherit the previous user's history.
        await ref.read(questionRepositoryProvider).clearUserState();
        await ref.read(preferencesRepositoryProvider).clear();
        unawaited(ref.read(analyticsServiceProvider).setUser(null));
      case AccountDeletionOutcome.requiresRecentLogin:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in again, then delete your account.'),
          ),
        );
        await ref.read(authRepositoryProvider).signOut();
      case AccountDeletionOutcome.notSignedIn:
      case AccountDeletionOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete the account.')),
        );
    }
  }
}

/// Whether a reminder is genuinely armed with the OS, and a way to prove it.
///
/// The switch above reflects a stored preference. That preference stayed true
/// while the schedule itself was pinned to UTC — the reminder still arrived,
/// five and a half hours late in India, and every surface in the app insisted
/// it was set for 9:30 am. This reads the pending schedule back from the
/// platform and states the timezone it resolved to, so the two can never
/// disagree silently again.
class _ReminderStatus extends ConsumerStatefulWidget {
  const _ReminderStatus();

  @override
  ConsumerState<_ReminderStatus> createState() => _ReminderStatusState();
}

class _ReminderStatusState extends ConsumerState<_ReminderStatus> {
  Future<DateTime?>? _next;

  @override
  void initState() {
    super.initState();
    _next = ref.read(notificationServiceProvider).nextReminder();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zone = ref.read(notificationServiceProvider).timeZoneName;

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: AppPanel.notice(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<DateTime?>(
              future: _next,
              builder: (context, snapshot) {
                final next = snapshot.data;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      next == null
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        switch (snapshot.connectionState) {
                          ConnectionState.done when next != null =>
                            'Next reminder '
                                '${_relative(next)}, in $zone.',
                          ConnectionState.done =>
                            'No reminder is armed on this device. Turn the '
                                'switch off and on to schedule one.',
                          _ => 'Checking the schedule…',
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.sm),
            TextButton.icon(
              onPressed: () => SettingsScreen._sendTest(context, ref),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send a test notification'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, Sizes.buttonSm),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relative(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final label = day == today
        ? 'today'
        : day.difference(today).inDays == 1
        ? 'tomorrow'
        : 'on ${when.day}/${when.month}';

    return '$label at ${SettingsScreen._formatTime(when.hour, when.minute)}';
  }
}
