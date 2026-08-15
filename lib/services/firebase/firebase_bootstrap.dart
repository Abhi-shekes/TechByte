import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Initialises Firebase and installs global error handling.
///
/// Every service used here is available on the free Spark plan. Nothing in
/// this file enables, requires, or upgrades to a paid plan.
abstract final class FirebaseBootstrap {
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _initializeAppCheck();
    _installCrashHandlers();
    await _configureAnalytics();
  }

  /// App Check attests that requests come from a genuine build of this app,
  /// which is what keeps the shared Firebase and Gemini quotas from being
  /// drained by someone else using our project's credentials.
  ///
  /// Release builds attest automatically through Play Integrity — there is no
  /// token to configure, only the signing certificate's SHA-256, which must be
  /// registered in the Firebase console.
  ///
  /// Debug builds have no Play signature to attest, so they present a token
  /// registered by hand instead. Left to itself the SDK generates a fresh
  /// random token on every install, meaning every reinstall needs a new
  /// console entry. Supplying one via
  /// `--dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>` pins it, so a device is
  /// registered once and stays registered.
  static const _debugToken = String.fromEnvironment('APP_CHECK_DEBUG_TOKEN');

  static Future<void> _initializeAppCheck() async {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? AndroidDebugProvider(
                // Null means "let the SDK generate one" — the same behaviour
                // as before, so nothing breaks without the define.
                debugToken: _debugToken.isEmpty ? null : _debugToken,
              )
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (error) {
      // App Check failing must not prevent the app from starting; the
      // backend still enforces its own rules.
      debugPrint('App Check activation failed: $error');
      return;
    }

    unawaited(_reportAttestation());
  }

  /// Mints a token once at startup purely to find out whether attestation
  /// works, and says so.
  ///
  /// `activate` succeeds whether or not this device can actually attest —
  /// registering a provider is a local operation. The failure only appears
  /// later, on the first request that needs a token, as a 403 thrown from deep
  /// inside whichever feature happened to ask first. On this app that was
  /// Gemini, so an unregistered debug build looked like "the AI is broken"
  /// rather than "this device is not on the allow list".
  ///
  /// Deliberately fire-and-forget: it is a diagnostic, and nothing should wait
  /// on it.
  static Future<void> _reportAttestation() async {
    try {
      await FirebaseAppCheck.instance.getToken();
    } catch (error) {
      debugPrint(
        'App Check cannot attest this build, so every Firebase AI request '
        'will fail with 403 "App attestation failed": $error',
      );
      if (kDebugMode) {
        debugPrint(
          _debugToken.isEmpty
              ? 'Debug builds present a randomly generated debug token. Find '
                    'the line "Enter this debug secret into the allow list" in '
                    '`adb logcat -s DebugAppCheckProvider`, register that UUID '
                    'under App Check > Apps > Manage debug tokens, then '
                    'reinstall. To stop it changing on every reinstall, pass '
                    '--dart-define=APP_CHECK_DEBUG_TOKEN=<uuid>.'
              : 'The debug token supplied via APP_CHECK_DEBUG_TOKEN is not on '
                    'the allow list for this Firebase app. Register it under '
                    'App Check > Apps > Manage debug tokens.',
        );
      }
    }
  }

  static void _installCrashHandlers() {
    // Crashlytics is disabled in debug so local stack traces stay in the
    // console and don't pollute release crash statistics.
    unawaited(
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode),
    );

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  static Future<void> _configureAnalytics() async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
  }
}
