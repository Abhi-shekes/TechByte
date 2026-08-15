import 'package:flutter/material.dart';

/// Every layout constant the UI is allowed to use.
///
/// The rule this file exists to enforce: no literal spacing, radius or duration
/// values in `features/**/presentation/`. Before this existed the app used six
/// different page gutters and fifteen different vertical gaps, because nothing
/// made the right value easier to reach for than an arbitrary one.
abstract final class Space {
  /// 4pt base. Steps are spaced widely enough that picking the wrong one is
  /// visible in review — a scale with 2pt increments is a scale nobody follows.
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
  static const giant = 48.0;
  static const colossal = 64.0;

  /// Horizontal page padding for lists and detail screens.
  static const gutter = 20.0;

  /// Horizontal page padding where display-size type sets the line length —
  /// the feed card and onboarding. Wider because a 34px question needs a
  /// shorter measure, not because those screens are special.
  static const gutterReading = 24.0;

  /// Standard scroll-view padding. Bottom is generous so the last item clears
  /// the navigation bar.
  static const pagePadding = EdgeInsets.fromLTRB(gutter, sm, gutter, xxxl);
  static const readingPadding = EdgeInsets.fromLTRB(
    gutterReading,
    sm,
    gutterReading,
    xxxl,
  );
}

/// Corner radii. 14 and 18 previously appeared alongside these and are gone.
abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;

  /// The navigation dock's top corners. Large enough to read as a deliberate
  /// silhouette rather than a rounded rectangle — roughly 40% of the dock's
  /// own height, which is what makes the square bottom corners land as a
  /// choice instead of an oversight.
  static const xxl = 28.0;

  static const full = 999.0;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const xlAll = BorderRadius.all(Radius.circular(xl));
  static const fullAll = BorderRadius.all(Radius.circular(full));

  /// Rounded across the top, square across the bottom.
  static const dockTop = BorderRadius.vertical(top: Radius.circular(xxl));
}

/// Minimum interactive sizes.
abstract final class Sizes {
  /// WCAG 2.2 target size. Applied to every icon button and tappable row.
  static const touchTarget = 44.0;

  /// Button heights. The old theme locked everything to 52, which is right for
  /// a primary CTA and oversized for "Try again" inside a sheet.
  static const buttonLg = 52.0;
  static const buttonMd = 44.0;
  static const buttonSm = 36.0;

  /// Progress meter track height, shared by every meter in the app.
  static const meterTrack = 6.0;

  /// Width of the label column in a meter row.
  static const meterLabel = 132.0;

  /// Width of the trailing value column in a meter row.
  static const meterValue = 44.0;
}

/// Durations and curves.
///
/// Use [Motion.of] rather than these constants directly — it collapses them to
/// zero when the user has asked for reduced motion.
abstract final class AppDurations {
  /// State flips: chips, switches, selection.
  static const fast = Duration(milliseconds: 140);

  /// Navigation, sheets, most transitions.
  static const base = Duration(milliseconds: 220);

  /// The answer reveal. The one deliberately slow moment in the app; it is the
  /// product's signature interaction and reads as considered rather than laggy.
  static const reveal = Duration(milliseconds: 380);

  /// Long scroll animations that carry the eye across a screen.
  static const slow = Duration(milliseconds: 400);

  /// Text-input debounce. Not motion — never routed through [Motion], because
  /// reduce-motion should not make search fire on every keystroke.
  static const debounce = Duration(milliseconds: 220);
}

abstract final class AppCurves {
  static const standard = Curves.easeOutCubic;

  /// Reserved for the reveal, so nothing else moves quite like it.
  static const emphasized = Curves.easeOutQuint;
}

/// Resolves durations against the user's motion preference.
///
/// Exposed as an [InheritedWidget] rather than read from Riverpod at each call
/// site so that plain [StatelessWidget]s deep in the tree can honour the
/// setting without becoming Consumers. Previously only `QuestionCard` checked
/// the preference at all, which meant switching it on stopped one animation out
/// of three — arguably worse than not offering it.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.reducedMotion,
    required super.child,
  });

  final bool reducedMotion;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    // The platform switch is checked here too, so callers get one answer.
    return (scope?.reducedMotion ?? false) ||
        MediaQuery.disableAnimationsOf(context);
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) =>
      oldWidget.reducedMotion != reducedMotion;
}

abstract final class Motion {
  /// The only correct way to get a duration inside a widget.
  static Duration of(BuildContext context, Duration duration) =>
      MotionScope.of(context) ? Duration.zero : duration;

  static Duration fast(BuildContext context) => of(context, AppDurations.fast);
  static Duration base(BuildContext context) => of(context, AppDurations.base);
  static Duration reveal(BuildContext context) =>
      of(context, AppDurations.reveal);
}

/// The three depth tiers.
///
/// The app was uniformly flat — every surface was elevation 0 with a 1px
/// outline, so a modal sheet, a card and a floating overlay read identically.
/// Only [overlay] casts a shadow; in dark mode it lifts tone and brightens its
/// border instead, because a shadow on a near-black ground is invisible.
enum Depth {
  /// Scaffold background. No border, no shadow.
  ground,

  /// Cards, panels, tiles. Hairline border, no shadow.
  raised,

  /// Sheets, menus, snackbars, floating strips.
  overlay;

  Color background(ColorScheme scheme) => switch (this) {
    Depth.ground => scheme.surfaceContainerLowest,
    Depth.raised => scheme.surface,
    Depth.overlay => scheme.surfaceContainer,
  };

  BoxBorder? border(ColorScheme scheme) => switch (this) {
    Depth.ground => null,
    Depth.raised => Border.all(color: scheme.outline),
    Depth.overlay => Border.all(color: scheme.outlineVariant),
  };

  List<BoxShadow> shadows(Brightness brightness) => switch (this) {
    Depth.ground || Depth.raised => const [],
    Depth.overlay =>
      brightness == Brightness.dark
          ? const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ]
          : const [
              BoxShadow(
                color: Color(0x0F0D1117),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x1A0D1117),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
  };
}
