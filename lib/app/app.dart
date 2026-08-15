import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

class TechByteApp extends ConsumerStatefulWidget {
  const TechByteApp({super.key});

  @override
  ConsumerState<TechByteApp> createState() => _TechByteAppState();
}

class _TechByteAppState extends ConsumerState<TechByteApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_rearmDailyReminder());
  }

  /// Re-schedules the daily reminder on every launch, if it is switched on.
  ///
  /// A repeating `zonedSchedule` survives reboots and normally needs no help,
  /// but it was previously only ever armed from the moment the switch was
  /// flipped. So anyone who enabled it before the timezone fix still had a
  /// schedule pinned to UTC, and anyone whose alarm the OS dropped — an app
  /// update, a battery optimiser, a restore to a new device — had no way to
  /// get it back short of toggling the switch off and on. Re-arming is
  /// idempotent: the id is fixed, so this replaces rather than duplicates.
  Future<void> _rearmDailyReminder() async {
    final prefs = ref.read(userPreferencesProvider);
    if (!prefs.dailyReminderEnabled) return;

    await ref
        .read(notificationServiceProvider)
        .scheduleDailyReminder(
          hour: prefs.reminderHour,
          minute: prefs.reminderMinute,
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Backgrounding is the natural moment to flush pending changes.
  ///
  /// Chosen over a timer deliberately: the user has stopped interacting, so
  /// there is nothing to slow down, and it costs one batched write per session
  /// rather than one per interval. A periodic sync would spend Firestore quota
  /// on a device that changed nothing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }

    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    unawaited(ref.read(syncServiceProvider).push(uid: uid));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(
      userPreferencesProvider.select((p) => p.themeMode),
    );
    final reducedMotion = ref.watch(
      userPreferencesProvider.select((p) => p.reducedMotion),
    );

    return MaterialApp.router(
      title: 'TechByte',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      builder: (context, child) {
        // Respect the platform font scale, but stop very large settings from
        // pushing a question card into an unreadable layout.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.6,
            ),
          ),
          // Published here so any widget can honour the motion preference via
          // `Motion.of` without becoming a Consumer.
          child: MotionScope(
            reducedMotion: reducedMotion,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
