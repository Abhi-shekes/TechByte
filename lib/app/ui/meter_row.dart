import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Label, track, value — the app's one progress meter.
///
/// Previously three implementations with three bar heights (4, 5 and 6) and two
/// label widths, in profile familiarity, practice dimensions and explore tiles.
/// None of them carried a [Semantics] value, so a screen reader heard nothing
/// at all from any of them.
class MeterRow extends StatelessWidget {
  const MeterRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.valueLabel,
    this.semanticValue,
  });

  final String label;

  /// 0–1.
  final double value;
  final Color color;

  /// The trailing text — "72%", "8", "3 of 12".
  final String valueLabel;

  /// What a screen reader announces. Defaults to [valueLabel], but callers
  /// should pass something self-contained where the visual label is terse.
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      value: semanticValue ?? valueLabel,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Row(
          children: [
            SizedBox(
              width: Sizes.meterLabel,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: Radii.fullAll,
                  child: LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    minHeight: Sizes.meterTrack,
                    backgroundColor: theme.colorScheme.surfaceContainer,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            SizedBox(
              width: Sizes.meterValue,
              child: Text(
                valueLabel,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bare track, for places with no room for a label — the Explore tile.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.value,
    required this.color,
    required this.semanticLabel,
    required this.semanticValue,
  });

  final double value;
  final Color color;
  final String semanticLabel;
  final String semanticValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: semanticLabel,
      value: semanticValue,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: Radii.fullAll,
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: Sizes.meterTrack,
            backgroundColor: theme.colorScheme.surfaceContainer,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
    );
  }
}
