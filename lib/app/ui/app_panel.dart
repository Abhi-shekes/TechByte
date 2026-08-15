import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// The tinted box with a hairline border.
///
/// This shape was written seven times across the app with four different radii
/// (12, 14, 16, 18) and three different paddings. Nothing enforced it, so each
/// new one drifted further from the last.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.depth = Depth.raised,
    this.borderRadius = Radii.lgAll,
    this.accent,
  });

  /// A non-blocking explanation: quota exhausted, offline, nothing to show.
  const AppPanel.notice({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.lg,
      vertical: Space.md,
    ),
    this.depth = Depth.raised,
    this.borderRadius = Radii.mdAll,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Depth depth;
  final BorderRadius borderRadius;

  /// Draws a 3px leading rule in this colour. Used where the panel belongs to a
  /// category or carries a severity.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget panel = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: depth.background(scheme),
        borderRadius: borderRadius,
        border: depth.border(scheme),
        boxShadow: depth.shadows(theme.brightness),
      ),
      child: child,
    );

    if (accent case final color?) {
      panel = ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            panel,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: color),
            ),
          ],
        ),
      );
    }

    return panel;
  }
}

/// Text styled as reference material, for use inside [AppPanel.mono].
class MonoText extends StatelessWidget {
  const MonoText(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: AppTypography.mono(color: color ?? theme.colorScheme.onSurface),
    );
  }
}
