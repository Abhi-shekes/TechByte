import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// One search affordance for the whole app.
///
/// Explore hid search behind an app-bar icon that pushed a full screen, while
/// Saved embedded a live-filtering field that scrolled away with the list —
/// same task, two mental models, two different-looking controls. Both now use
/// this. What differs is scope, which the hint text states, not the shape of
/// the control.
class AppSearchBar extends StatelessWidget {
  /// Filters a list in place as the user types.
  const AppSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
  }) : onTap = null;

  /// Opens a dedicated search screen. Reads as a field, behaves as a button —
  /// which is the standard pattern for search that changes context.
  const AppSearchBar.navigational({
    super.key,
    required this.hintText,
    required this.onTap,
  }) : onChanged = null,
       controller = null;

  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (onTap case final tap?) {
      return Semantics(
        button: true,
        label: hintText,
        child: InkWell(
          onTap: tap,
          borderRadius: Radii.mdAll,
          child: Container(
            // A minimum rather than a fixed height: at a large font scale the
            // hint is taller than 52px, and a hard height clipped it.
            constraints: const BoxConstraints(minHeight: Sizes.buttonLg),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: Radii.mdAll,
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Space.md),
                // "Search every question" is wider than a 320px phone once the
                // font scale passes ~1.3, and without a flex factor the Row
                // overflowed by the difference rather than shortening the hint.
                Expanded(
                  child: Text(
                    hintText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainer,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
      ),
    );
  }
}
