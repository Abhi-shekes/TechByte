import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';
import '../../features/questions/domain/question.dart';

/// A question in a list.
///
/// Saved, Search and History each built a near-identical `Card` + `ListTile`
/// that opened the deep-dive sheet, with small gratuitous differences in the
/// trailing slot and subtitle padding. A question should look the same wherever
/// it appears.
class QuestionTile extends StatelessWidget {
  const QuestionTile({
    super.key,
    required this.question,
    required this.onTap,
    this.titleOverride,
    this.meta,
    this.trailing,
    this.isSaved = false,
  });

  final Question question;
  final VoidCallback onTap;

  /// Replaces the plain title — used by Search to highlight the matched term.
  final Widget? titleOverride;

  /// A row of chips under the answer preview: category, state, counts.
  final List<Widget>? meta;

  /// Overrides the default trailing bookmark indicator.
  final Widget? trailing;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppPalette.forCategory(
      question.category.id,
      isDark: theme.brightness == Brightness.dark,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.xlAll,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleOverride ??
                          Text(
                            question.question,
                            style: theme.textTheme.titleMedium,
                          ),
                      const SizedBox(height: Space.sm),
                      Text(
                        question.shortAnswer,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (meta case final chips? when chips.isNotEmpty) ...[
                        const SizedBox(height: Space.md),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: chips,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing case final widget?) ...[
                  const SizedBox(width: Space.md),
                  widget,
                ] else if (isSaved) ...[
                  const SizedBox(width: Space.md),
                  Icon(Icons.bookmark_rounded, size: 18, color: accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
