import 'package:drift/native.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techbyte/app/theme/app_theme.dart';
import 'package:techbyte/app/theme/app_tokens.dart';
import 'package:techbyte/app/ui/ui.dart';
import 'package:techbyte/core/analytics/analytics_service.dart';
import 'package:techbyte/core/providers/core_providers.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/explore/presentation/explore_screen.dart';
import 'package:techbyte/features/feed/application/daily_session_controller.dart';
import 'package:techbyte/features/practice/presentation/practice_screen.dart';
import 'package:techbyte/features/profile/presentation/profile_screen.dart';

import '../helpers/sqlite_test_setup.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

const _destinations = [
  AppNavDestination(
    icon: Icons.bolt_outlined,
    selectedIcon: Icons.bolt_rounded,
    label: 'Home',
  ),
  AppNavDestination(
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
    label: 'Explore',
  ),
  AppNavDestination(
    icon: Icons.fitness_center_outlined,
    selectedIcon: Icons.fitness_center_rounded,
    label: 'Practice',
    badgeCount: 3,
  ),
  AppNavDestination(
    icon: Icons.bookmark_border_rounded,
    selectedIcon: Icons.bookmark_rounded,
    label: 'Saved',
  ),
  AppNavDestination(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

/// The narrowest phone the app is expected to run on, and the widest font
/// scale it clamps to. Every layout assertion here uses both at once, because
/// each alone was already survivable — it is the combination that broke.
const _narrow = Size(320, 640);

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Widget wrap(Widget child, {double scale = 1.0, bool reducedMotion = true}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        analyticsServiceProvider.overrideWithValue(
          AnalyticsService(analytics: _MockFirebaseAnalytics(), enabled: false),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: child,
        // `copyWith` rather than a fresh MediaQueryData: building one from
        // scratch zeroes the surface size, and half the layouts under test
        // read it. Wrapping the builder's `navigator` rather than the screen
        // keeps the Overlay that tooltips and sheets need.
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: MotionScope(
            reducedMotion: reducedMotion,
            child: navigator ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('AppNavBar', () {
    testWidgets('lays out at the maximum font scale on a narrow phone', (
      tester,
    ) async {
      await setSurface(tester, _narrow);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 2,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
          scale: 1.6,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('takes only the height it needs, leaving the rest to the body', (
      tester,
    ) async {
      await setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Container(key: const ValueKey('body')),
            bottomNavigationBar: AppNavBar(
              currentIndex: 0,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      // Scaffold lays the bottom slot out under loose constraints whose
      // maxHeight is the entire screen — not infinity. Anything in here that
      // expands to fill (a bare Center, an Expanded, a Column with
      // MainAxisSize.max) therefore eats the whole viewport and starves the
      // body, which renders as a navigation bar alone on a blank screen. The
      // dock's own layout never asserted its height, so exactly that shipped.
      final dock = tester.getSize(find.byType(AppNavBar));
      expect(dock.height, lessThan(140), reason: 'the dock swallowed the page');

      final body = tester.getSize(find.byKey(const ValueKey('body')));
      expect(body.height, greaterThan(600));
    });

    testWidgets('divides adjacent destinations with a rule, not a container', (
      tester,
    ) async {
      await setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 0,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      // Between each adjacent pair, and nowhere else — a trailing separator
      // would box the last destination against the dock's edge.
      expect(
        find.byType(VerticalDivider),
        findsNWidgets(_destinations.length - 1),
      );
    });

    testWidgets('carries selection on the icon alone, with no indicator', (
      tester,
    ) async {
      await setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 2,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Solid glyph for the selected destination, outline for the rest. The
      // active state adds no object to the dock — no pill, capsule or card —
      // so this and the accent colour are the whole of it.
      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fitness_center_outlined), findsNothing);
      expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    });

    testWidgets('stays a dock rather than stretching on a wide screen', (
      tester,
    ) async {
      await setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 0,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      final dock = tester.getSize(find.byType(VerticalDivider).first);
      expect(dock.height, greaterThan(0));

      final row = tester.getSize(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.byType(Row),
        ),
      );
      expect(
        row.width,
        lessThanOrEqualTo(720),
        reason: 'a dock that spans a 1280px window is a toolbar',
      );
    });

    testWidgets('every destination clears the WCAG target minimum', (
      tester,
    ) async {
      await setSurface(tester, _narrow);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 0,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
          scale: 1.6,
        ),
      );

      for (final element in find.byType(InkWell).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.height, greaterThanOrEqualTo(Sizes.touchTarget));
      }
    });

    testWidgets('reports the due count and the selection to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 2,
              destinations: _destinations,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      // The count is drawn as a bare accent dot, so the number itself only
      // exists for a screen reader — which is exactly where it has to be.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Practice, 3 due')),
        matchesSemantics(
          label: 'Practice, 3 due',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('the active emphasis travels between destinations', (tester) async {
      Widget bar(int index) => wrap(
        Scaffold(
          bottomNavigationBar: AppNavBar(
            currentIndex: index,
            destinations: _destinations,
            onSelected: (_) {},
          ),
        ),
        reducedMotion: false,
      );

      await tester.pumpWidget(bar(0));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(bar(3));
      await tester.pump();

      // The point of the whole widget: selection is a journey the eye can
      // follow, not two indicators cross-fading in place.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the journey collapses when motion is reduced', (tester) async {
      Widget bar(int index) => wrap(
        Scaffold(
          bottomNavigationBar: AppNavBar(
            currentIndex: index,
            destinations: _destinations,
            onSelected: (_) {},
          ),
        ),
      );

      await tester.pumpWidget(bar(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(bar(3));
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('selecting a destination reports its index', (tester) async {
      int? selected;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            bottomNavigationBar: AppNavBar(
              currentIndex: 0,
              destinations: _destinations,
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      );

      // By semantics rather than by text: the dock is icon-only, so the label
      // exists for a screen reader and a tooltip and is never drawn.
      await tester.tap(find.bySemanticsLabel('Saved'));
      expect(selected, 3);
    });
  });

  /// Scrolls a screen to its end a screenful at a time, failing on the first
  /// frame that overflows. Content below the fold is not built until it is
  /// scrolled to, so a single pump only ever proves the top of a screen safe.
  Future<void> scrollThrough(WidgetTester tester, Finder scrollable) async {
    for (var i = 0; i < 8; i++) {
      expect(tester.takeException(), isNull, reason: 'overflow after $i drags');
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  }

  group('Explore', () {
    testWidgets('the category grid lays out at the maximum font scale', (
      tester,
    ) async {
      await setSurface(tester, _narrow);
      await tester.pumpWidget(wrap(const ExploreScreen(), scale: 1.6));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsWidgets);

      // A fixed `childAspectRatio` made the cell height a function of screen
      // width alone, so the tile's text ran past the bottom of the card at any
      // scale much above 1.
      await scrollThrough(tester, find.byType(CustomScrollView));
    });
  });

  group('Practice', () {
    testWidgets('the mode cards lay out at the maximum font scale', (
      tester,
    ) async {
      await setSurface(tester, _narrow);
      await tester.pumpWidget(wrap(const PracticeScreen(), scale: 1.6));
      await tester.pumpAndSettle();

      expect(find.text('Interview'), findsOneWidget);
      await scrollThrough(tester, find.byType(ListView));
    });
  });

  group('Profile', () {
    testWidgets('lays out at the maximum font scale', (tester) async {
      await setSurface(tester, _narrow);
      await tester.pumpWidget(wrap(const ProfileScreen(), scale: 1.6));
      await tester.pumpAndSettle();

      // Three quick links across a 320px phone, and a stat row of three, are
      // the two rows most likely to run out of horizontal room.
      expect(find.text('History'), findsOneWidget);
      await scrollThrough(tester, find.byType(ListView));
    });
  });
}
