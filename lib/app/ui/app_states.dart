import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The empty state.
///
/// Six of these were written by hand with different gaps (8 vs 10 vs 14),
/// different alignment, and an icon in only one of the six. These are the
/// screens a new user sees first — before any content exists, the empty state
/// *is* the product.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.iconColor,
    this.action,
  });

  final String title;
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final glyph?) ...[
              Icon(
                glyph,
                size: 40,
                color: iconColor ?? theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Space.lg),
            ],
            Text(
              title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action case final widget?) ...[
              const SizedBox(height: Space.xl),
              widget,
            ],
          ],
        ),
      ),
    );
  }
}

/// The error state.
///
/// Four screens rendered `Center(child: Text('$error'))` — a raw Dart exception
/// with no styling and no way to recover. The technical detail is kept, because
/// it is the only useful thing in a bug report, but it is demoted behind a
/// disclosure and never shown first.
class AppErrorState extends StatefulWidget {
  const AppErrorState({
    super.key,
    required this.onRetry,
    this.title = "That didn't load",
    this.message =
        'Something went wrong reading your questions. Trying again usually '
        'fixes it.',
    this.detail,
  });

  final VoidCallback? onRetry;
  final String title;
  final String message;
  final String? detail;

  @override
  State<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends State<AppErrorState> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: Space.lg),
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.onRetry case final retry?) ...[
              const SizedBox(height: Space.xl),
              FilledButton(onPressed: retry, child: const Text('Try again')),
            ],
            if (widget.detail case final detail?) ...[
              const SizedBox(height: Space.md),
              TextButton(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                child: Text(_showDetail ? 'Hide details' : 'Show details'),
              ),
              if (_showDetail)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: SelectableText(
                    detail,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
