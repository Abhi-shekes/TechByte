import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Local reminders and push registration.
///
/// The daily reminder is a **local** scheduled notification, not a push. That
/// is deliberate: a server-driven reminder would need a scheduler and a
/// backend, and the product constraint is ₹0 infrastructure. The device
/// already knows what time it is.
///
/// Firebase Messaging is initialised only to register a token, so
/// announcements can be sent from the console later without a release. Nothing
/// in the app depends on a push ever arriving.
class NotificationService {
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    FirebaseMessaging? messaging,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _messaging = messaging ?? FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _plugin;
  final FirebaseMessaging _messaging;

  static const _dailyReminderId = 1001;
  static const _testNotificationId = 1002;

  static const _channel = AndroidNotificationChannel(
    'daily_reminder',
    'Daily reminder',
    description: 'A nudge when your daily set of questions is ready.',
    importance: Importance.defaultImportance,
  );

  bool _initialised = false;

  /// Prepares the plugin and timezone database.
  ///
  /// Safe to call more than once. Never throws: a device that refuses to set
  /// up notifications must not prevent the app from starting.
  Future<void> initialize() async {
    if (_initialised) return;

    try {
      tz.initializeTimeZones();
      _configureLocalTimeZone();

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      _initialised = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Points `tz.local` at the device's actual zone.
  ///
  /// This is the bug that made the daily reminder look broken.
  /// `initializeTimeZones` loads the database and nothing else — `tz.local`
  /// stays at **UTC** until it is set. Every reminder was therefore scheduled
  /// at the chosen wall-clock time in UTC, so a 9:30 am reminder arrived at
  /// 3:00 pm in India and 4:30 am in California. It was not that notifications
  /// never fired; they fired at the wrong time of day, which is worse, because
  /// nothing in the app said so.
  ///
  /// Resolved from the current UTC offset rather than by adding a plugin for
  /// the IANA zone name. A daily reminder only needs the right wall clock, and
  /// any zone sharing this offset gives that. The abbreviation is preferred
  /// where it matches, so India lands on Asia/Kolkata rather than the first
  /// +05:30 entry in the table, and DST changes are then handled correctly.
  static void _configureLocalTimeZone() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inMilliseconds;
    final abbreviation = now.timeZoneName;

    tz.Location? byOffset;

    for (final location in tz.timeZoneDatabase.locations.values) {
      final zone = location.currentTimeZone;
      if (zone.offset != offset) continue;
      if (zone.abbreviation == abbreviation) {
        tz.setLocalLocation(location);
        return;
      }
      byOffset ??= location;
    }

    if (byOffset != null) tz.setLocalLocation(byOffset);
  }

  /// Asks for notification permission.
  ///
  /// Required from Android 13 (API 33). Returns false when denied, which the
  /// settings toggle reflects rather than silently pretending it worked.
  Future<bool> requestPermission() async {
    await initialize();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  /// Schedules the daily reminder at [hour]:[minute], local time.
  ///
  /// Uses an inexact alarm on purpose. Exact alarms need a special permission
  /// on Android 12+ that Google reserves for genuine alarm clocks, and a
  /// reminder that arrives a few minutes late is entirely fine.
  Future<bool> scheduleDailyReminder({int hour = 9, int minute = 30}) async {
    await initialize();
    if (!_initialised) return false;

    _lastRequest = (hour, minute);

    try {
      await _plugin.zonedSchedule(
        id: _dailyReminderId,
        title: "Today's Tech 10 is ready",
        body: 'Ten questions, about eight minutes.',
        scheduledDate: _nextInstanceOf(hour, minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Daily reminder',
            channelDescription:
                'A nudge when your daily set of questions is ready.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (e) {
      debugPrint('Scheduling daily reminder failed: $e');
      return false;
    }
  }

  Future<void> cancelDailyReminder() async {
    await initialize();
    try {
      await _plugin.cancel(id: _dailyReminderId);
    } catch (e) {
      debugPrint('Cancelling daily reminder failed: $e');
    }
  }

  /// When the reminder will next arrive, or null if none is scheduled.
  ///
  /// Read back from the platform rather than computed, so it answers "is one
  /// actually armed" and not merely "what would we ask for". The settings
  /// screen showed the *preference* before, which stayed reassuringly on
  /// whether or not the OS had ever accepted the schedule.
  Future<DateTime?> nextReminder() async {
    await initialize();
    if (!_initialised) return null;

    try {
      final pending = await _plugin.pendingNotificationRequests();
      final armed = pending.any((r) => r.id == _dailyReminderId);
      if (!armed) return null;

      // The platform does not report the fire time back, so the schedule is
      // recomputed from the same rule that set it.
      return _lastRequest == null
          ? null
          : _nextInstanceOf(_lastRequest!.$1, _lastRequest!.$2);
    } catch (e) {
      debugPrint('Reading pending notifications failed: $e');
      return null;
    }
  }

  /// The hour and minute most recently scheduled, for [nextReminder].
  (int, int)? _lastRequest;

  /// The zone reminders are scheduled in. Surfaced in Settings, because "9:30
  /// am" is only meaningful once you know which 9:30 am the app means.
  String get timeZoneName => _initialised ? tz.local.name : 'UTC';

  /// Delivers a notification immediately, so the user can confirm the channel
  /// works without waiting a day to find out that it does not.
  Future<bool> sendTestNotification() async {
    await initialize();
    if (!_initialised) return false;

    try {
      await _plugin.show(
        id: _testNotificationId,
        title: 'Reminders are working',
        body: 'This is what your daily nudge will look like.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Daily reminder',
            channelDescription:
                'A nudge when your daily set of questions is ready.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Test notification failed: $e');
      return false;
    }
  }

  /// Registers for push. The token is not used yet; requesting it now means
  /// console announcements work without shipping a new build.
  Future<String?> registerForPush() async {
    try {
      await _messaging.requestPermission();
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM registration failed: $e');
      return null;
    }
  }

  /// The next occurrence of a wall-clock time, today or tomorrow.
  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
