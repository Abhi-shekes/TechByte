import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A figure with a label under it.
///
/// Two weights, because the profile screen rendered four numbers at identical
/// size — and one of them was the catalogue size, which is context rather than
/// something the user achieved.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = StatEmphasis.primary,
    this.color,
  });

  final String label;
  final int value;
  final StatEmphasis emphasis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      value: '$value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style:
                  (emphasis == StatEmphasis.primary
                          ? theme.textTheme.displaySmall
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(
                        color: color ?? theme.colorScheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
            const SizedBox(height: Space.xs / 2),
            // Three of these sit side by side in a Row of Expandeds, so at a
            // large font scale the widest label ("COMPLETED", uppercase, with
            // tracking) is wider than a third of a narrow screen. It wraps
            // rather than overflowing, and gives up at two lines.
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

enum StatEmphasis { primary, secondary }
