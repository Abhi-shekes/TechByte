import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// An uppercase eyebrow with an optional one-line explanation beneath it.
///
/// Uses `labelLarge`, one of the roles added to close the eleven inline
/// font-size overrides the app was carrying.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.description,
    this.color,
    this.trailing,
  });

  final String title;
  final String? description;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color ?? theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing case final widget?) widget,
            ],
          ),
          if (description case final text?) ...[
            const SizedBox(height: Space.xs),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small pill. Used for counts, states and severities.
///
/// Always takes an icon alongside its colour, so status is never carried by
/// hue alone — History previously rendered "Completed" as green text with no
/// second channel.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.fullAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final glyph?) ...[
            Icon(glyph, size: 12, color: color),
            const SizedBox(width: Space.xs),
          ],
          // Flexible inside a `MainAxisSize.min` Row: the chip still shrinks
          // to its label when there is room, and gives the label up when there
          // is not. A long one — a rubric dimension, a category name — used to
          // push the whole chip past the edge of whatever contained it.
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
