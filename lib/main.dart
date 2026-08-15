import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/analytics/analytics_service.dart';
import 'core/providers/core_providers.dart';
import 'features/feed/application/daily_session_controller.dart';
import 'services/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  await FirebaseBootstrap.initialize();

  // Loaded before the first frame so the theme and onboarding state are known
  // immediately — otherwise launch flashes the wrong theme.
  final prefs = await SharedPreferences.getInstance();

  // Constructed here rather than lazily so the launch event is recorded before
  // the first frame, and so one instance is shared by every consumer.
  final analytics = AnalyticsService();
  unawaited(analytics.appOpened());

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
      child: const TechByteApp(),
    ),
  );
}
