import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The accent rule plus uppercase label that identifies a category.
///
/// Written four times — the feed card header, the Explore tile, sign-in and
/// splash — each at a slightly different bar size. Sharing it is what makes the
/// splash-to-sign-in transition actually continuous, which the splash screen's
/// comment already claimed it was.
class CategoryMark extends StatelessWidget {
  const CategoryMark({
    super.key,
    required this.label,
    required this.color,
    this.size = MarkSize.small,
    this.trailing,
  });

  final String label;
  final Color color;
  final MarkSize size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _Rule(color: color, size: size),
        SizedBox(width: size.gap),
        Flexible(
          child: Text(
            label.toUpperCase(),
            style:
                (size == MarkSize.large
                        ? theme.textTheme.labelLarge
                        : theme.textTheme.labelSmall)
                    ?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing case final widget?) widget,
      ],
    );
  }
}

/// The rule on its own, for the splash screen where there is no label beside it.
class CategoryRule extends StatelessWidget {
  const CategoryRule({
    super.key,
    required this.color,
    this.size = MarkSize.large,
  });

  final Color color;
  final MarkSize size;

  @override
  Widget build(BuildContext context) => _Rule(color: color, size: size);
}

class _Rule extends StatelessWidget {
  const _Rule({required this.color, required this.size});

  final Color color;
  final MarkSize size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}

enum MarkSize {
  /// Above a question, in a tile, in a list header.
  small(width: 3, height: 18, gap: Space.sm + 2),

  /// The brand lockup on splash and sign-in.
  large(width: 4, height: 30, gap: Space.md);

  const MarkSize({
    required this.width,
    required this.height,
    required this.gap,
  });

  final double width;
  final double height;
  final double gap;
}
