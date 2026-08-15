import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:techbyte/services/notifications/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

class _MockMessaging extends Mock implements FirebaseMessaging {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reminders are scheduled in the device zone, not UTC', () async {
    // `initialize` swallows the plugin failure that a host-VM test produces —
    // the timezone work it does first is what matters here.
    await NotificationService(messaging: _MockMessaging()).initialize();

    // The regression: `initializeTimeZones()` loads the database and leaves
    // `tz.local` at UTC. Every reminder was therefore scheduled at the chosen
    // wall-clock time *in UTC*, so a 9:30 am reminder arrived at 3:00 pm in
    // India — the reminder was not missing, it was hours late, and nothing in
    // the app admitted it.
    expect(
      tz.local.currentTimeZone.offset,
      DateTime.now().timeZoneOffset.inMilliseconds,
      reason: 'tz.local must match the device offset',
    );
  });
}
