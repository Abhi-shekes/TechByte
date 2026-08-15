import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// One destination in [AppNavBar].
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;

  /// Not drawn — the dock is icon-only, by design. It is the tooltip and the
  /// screen-reader name, so every destination still has one.
  final String label;

  /// Surfaced as a single accent dot rather than a number. A count badge is
  /// the loudest object a nav bar can carry, and the only question this dock
  /// needs to answer at a glance is "is there anything waiting".
  final int badgeCount;
}

/// The app's bottom navigation: a floating command dock.
///
/// Not a bottom navigation bar, and deliberately not Material's. Three things
/// define it, in the order a viewer notices them:
///
/// 1. **The silhouette.** Large radii across the top, square corners across
///    the bottom. An asymmetric shape is instantly identifiable and costs
///    nothing; a uniformly rounded rectangle is what every other app ships.
/// 2. **Separation by rule, not by container.** Thin vertical dividers set the
///    destinations apart, so the row reads as one instrument with segments
///    rather than five buttons that happen to be adjacent.
/// 3. **A minimal active state.** No pill, no capsule, no circle, no card.
///    Selection is carried by colour and by the glyph switching from outline
///    to solid — two channels, neither of which adds an object to the screen.
///    The colour is animated as a travelling emphasis, so moving between
///    destinations still reads as motion rather than a flip.
///
/// It floats: inset from all four edges, over a broad soft shadow, capped in
/// width so that on a tablet it stays a dock instead of stretching into a
/// toolbar.
class AppNavBar extends StatefulWidget {
  const AppNavBar({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
    this.hapticsEnabled = true,
  });

  final int currentIndex;
  final List<AppNavDestination> destinations;
  final ValueChanged<int> onSelected;

  /// Mirrors the user's haptics preference; a tab change is a selection event,
  /// which is the lightest feedback the platform offers.
  final bool hapticsEnabled;

  /// Beyond this the dock stops growing and centres instead. A control panel
  /// that spans a 1200px window is a toolbar, which is the one thing this is
  /// not meant to become.
  static const _maxWidth = 640.0;

  /// Dock heights. Comfortably past the WCAG target minimum at the small end,
  /// so a destination never needs padding of its own to be hittable.
  static const _height = 64.0;
  static const _heightWide = 76.0;

  /// Proportion of the dock's height that a separator spans. Short: the rule
  /// is there to divide, and one that reaches the edges would box each
  /// destination in — which is the container the design is avoiding.
  static const _separatorRatio = 0.34;

  /// The dock is dark in both themes.
  ///
  /// Not an oversight and not a theme bug. Every other surface in TechByte
  /// follows the colour scheme; this one is an instrument sitting *over* the
  /// interface, and its whole character comes from being a dark object on
  /// whatever ground it floats above. Painted in the light scheme it is
  /// `surfaceContainer` on `surfaceContainerLowest` — #F1F4F7 on #FBFCFD —
  /// which is a 1.04:1 difference, so the silhouette that defines the design
  /// simply disappears.
  ///
  /// The values are the dark palette's, which is also what makes this safe:
  /// they were designed and contrast-verified against exactly this
  /// background, so the foregrounds clear 4.5:1 here in either theme.
  static const _surface = AppPalette.darkSurfaceRaised;
  static const _border = AppPalette.darkOutline;
  static const _separator = AppPalette.darkOutline;
  static const _active = AppPalette.accentDark;
  static const _idle = AppPalette.darkTextSecondary;

  @override
  State<AppNavBar> createState() => _AppNavBarState();
}

class _AppNavBarState extends State<AppNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Where the emphasis started this journey, in destination units.
  /// Fractional after an interrupted travel — tapping a third destination
  /// mid-flight continues from wherever the colour actually is.
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.currentIndex.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.base,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(AppNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == oldWidget.currentIndex) return;

    _from = _position;
    _to = widget.currentIndex.toDouble();
    _controller
      ..duration = Motion.of(context, AppDurations.base)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The emphasis's current position in destination units.
  double get _position {
    final t = AppCurves.standard.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  void _select(int index) {
    if (index != widget.currentIndex && widget.hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
    // Forwarded even when unchanged — the shell uses a repeat tap to pop the
    // destination back to its root.
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final wide = width >= 600;
    final height = wide ? AppNavBar._heightWide : AppNavBar._height;

    // Inset scales with the screen so the dock keeps its proportions rather
    // than its margins: generous room on a tablet, tighter on a small phone,
    // never so tight that it reads as edge-to-edge.
    final inset = wide
        ? Space.huge
        : width >= 380
        ? Space.xxl
        : Space.lg;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, Space.xs, inset, Space.md),
        // `heightFactor: 1` is load-bearing, not a tweak. Scaffold lays its
        // `bottomNavigationBar` out under *loose* constraints whose maxHeight
        // is the whole screen, and a bare Center expands to fill whatever it
        // is offered — so the dock claimed the entire viewport, the body was
        // given zero height, and the app rendered as five icons floating in
        // the middle of an empty screen. The factor makes it size to the
        // child, leaving the width free to centre on.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppNavBar._maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppNavBar._surface,
                borderRadius: Radii.dockTop,
                border: Border.all(color: AppNavBar._border),
                // Always the light-mode shadow recipe: a soft broad cast that
                // lifts the dock off the page. The dark-mode recipe is a
                // single heavy black blur, which is right for a sheet on a
                // near-black ground and invisible under a dark object on a
                // white one.
                boxShadow: Depth.overlay.shadows(Brightness.light),
              ),
              child: ClipRRect(
                borderRadius: Radii.dockTop,
                // Transparent Material so a press inks inside the dock's own
                // silhouette rather than a rectangle overhanging its corners.
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    height: height,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => Row(
                        children: [
                          for (
                            var i = 0;
                            i < widget.destinations.length;
                            i++
                          ) ...[
                            if (i > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                indent: height * AppNavBar._separatorRatio,
                                endIndent: height * AppNavBar._separatorRatio,
                                color: AppNavBar._separator,
                              ),
                            Expanded(
                              child: _NavItem(
                                destination: widget.destinations[i],
                                // How close the emphasis is to this
                                // destination right now. Colour is a
                                // function of the travelling value rather
                                // than of a boolean, so it arrives with the
                                // movement instead of switching on at the
                                // end of it.
                                proximity: (1 - (_position - i).abs()).clamp(
                                  0.0,
                                  1.0,
                                ),
                                selected: i == widget.currentIndex,
                                iconSize: wide ? 24 : 22,
                                onTap: () => _select(i),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.proximity,
    required this.selected,
    required this.iconSize,
    required this.onTap,
  });

  final AppNavDestination destination;

  /// 1 when the emphasis is on this destination, 0 when a whole destination
  /// away.
  final double proximity;

  /// The authoritative selection, for semantics and for the glyph swap. The
  /// emphasis can be halfway between two destinations; the route cannot.
  final bool selected;

  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Fixed rather than scheme-derived, because the dock is dark in both
    // themes — see `AppNavBar._surface`.
    final colour =
        Color.lerp(AppNavBar._idle, AppNavBar._active, proximity) ??
        AppNavBar._active;

    // Outline when idle, solid when selected. The second channel matters:
    // colour alone would leave the active destination indistinguishable to
    // anyone who cannot separate the accent from the muted foreground.
    Widget icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: iconSize,
      color: colour,
    );

    if (destination.badgeCount > 0) {
      icon = Badge(backgroundColor: AppNavBar._active, child: icon);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: destination.badgeCount > 0
          ? '${destination.label}, ${destination.badgeCount} due'
          : destination.label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: destination.label,
          // The dock's own height is the target, so every destination is a
          // full-height column rather than an icon with a hit box round it.
          child: InkWell(
            onTap: onTap,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
