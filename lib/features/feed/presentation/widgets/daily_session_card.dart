import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/ui/ui.dart';
import '../../application/daily_session_controller.dart';

/// "Today's Tech 10" progress, as a single strip above the question.
///
/// Deliberately the smallest thing on the screen. The question is the product
/// and the daily set is context for it, so this used to be inverted: a boxed
/// card with a 26px ring, a `bodyMedium` title and a `bodySmall` subtitle took
/// three lines and roughly 70px off the top of every card, competing with the
/// thing it was supposed to introduce.
///
/// The bar carries the count instead of a sentence. Ten ticks are read at a
/// glance and cost one line, which is also why the numbers can drop to the
/// smallest type in the scale without becoming the point.
class DailySessionCard extends ConsumerWidget {
  const DailySessionCard({super.key});

  /// Above this many questions the ticks stop being countable and a plain
  /// meter is more honest.
  static const _maxTicks = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final session = ref.watch(dailySessionProvider).value;

    if (session == null || session.total == 0) {
      return const SizedBox.shrink();
    }

    final done = session.isComplete;
    final color = done
        ? AppPalette.successFor(isDark: isDark)
        : AppPalette.accentFor(isDark: isDark);

    return Semantics(
      label: "Today's Tech 10",
      value: done
          ? 'Complete'
          : '${session.completed} of ${session.total} done',
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (session.total <= _maxTicks)
              _Ticks(
                total: session.total,
                completed: session.completed,
                color: color,
                muted: theme.colorScheme.outlineVariant,
              )
            else
              SizedBox(
                width: 72,
                child: MeterBar(
                  value: session.progress,
                  color: color,
                  semanticLabel: "Today's Tech 10",
                  semanticValue: '',
                ),
              ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                done
                    ? "TODAY'S TECH 10 · DONE"
                    : "TODAY'S TECH 10 · ${session.completed}/${session.total} "
                          '· ~${session.estimatedMinutes} MIN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: done ? color : theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (done)
              Icon(Icons.check_circle_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

/// One tick per question in the set, filled as they are completed.
class _Ticks extends StatelessWidget {
  const _Ticks({
    required this.total,
    required this.completed,
    required this.color,
    required this.muted,
  });

  final int total;
  final int completed;
  final Color color;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 3),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: i < completed ? color : muted,
                borderRadius: const BorderRadius.all(Radius.circular(1.5)),
              ),
            ),
          ),
      ],
    );
  }
}
