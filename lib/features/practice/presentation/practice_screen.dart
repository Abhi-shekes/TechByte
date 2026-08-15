import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../application/practice_controller.dart';
import '../domain/practice_mode.dart';
import 'practice_session_screen.dart';
import 'review_screen.dart';

/// Entry point for graded practice: interview, debugging, and spaced review.
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final due = ref.watch(dueForReviewCountProvider);
    final dueCount = due.value ?? 0;
    final budget = ref.watch(aiBudgetRemainingProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(dueForReviewCountProvider)
            ..invalidate(aiBudgetRemainingProvider);
        },
        child: ListView(
          padding: Space.pagePadding,
          children: [
            const SectionHeader(
              'Pick a mode',
              description:
                  'Every mode takes a written answer and grades the reasoning '
                  'in it, not a multiple choice.',
            ),

            _ModeCard(
              icon: Icons.record_voice_over_rounded,
              title: 'Interview',
              description:
                  'Answer a real interview question in your own words. Graded '
                  'on accuracy, completeness, clarity, depth and structure.',
              accent: AppPalette.accentFor(isDark: isDark),
              // The rubric is what the mode actually is, and it was buried in
              // a sentence. As chips it is scannable, and it sets the
              // expectation before the answer rather than after the score.
              rubric: PracticeMode.interview.dimensions,
              action: 'Start answering',
              onTap: () => _open(
                context,
                const PracticeSessionScreen(mode: PracticeMode.interview),
              ),
            ),
            _ModeCard(
              icon: Icons.bug_report_rounded,
              title: 'Debugging',
              description:
                  'Work a production incident from its symptoms. Your '
                  'reasoning is assessed, not just the conclusion you reach.',
              accent: AppPalette.dangerFor(isDark: isDark),
              rubric: PracticeMode.debugging.dimensions,
              action: 'Open an incident',
              onTap: () => _open(
                context,
                const PracticeSessionScreen(mode: PracticeMode.debugging),
              ),
            ),
            _ModeCard(
              icon: Icons.history_toggle_off_rounded,
              title: 'Review',
              description: dueCount == 0
                  ? 'Questions you answered wrong come back here on an '
                        'expanding schedule. Nothing is due right now.'
                  : 'Questions due for another look, on an expanding '
                        'schedule until they stick.',
              accent: AppPalette.warningFor(isDark: isDark),
              badge: dueCount == 0 ? null : '$dueCount due',
              action: 'Start review',
              enabled: dueCount > 0,
              onTap: () => _open(context, const ReviewScreen()),
            ),

            const SizedBox(height: Space.md),
            _BudgetNote(remaining: budget),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

/// What grading will cost today.
///
/// The old line said grading "uses one AI request per answer" without ever
/// saying how many were left, which made a quota stop mid-session look like a
/// failure rather than the documented limit.
class _BudgetNote extends StatelessWidget {
  const _BudgetNote({required this.remaining});

  final int? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final exhausted = remaining != null && remaining! <= 0;

    return AppPanel.notice(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            exhausted ? Icons.battery_alert_rounded : Icons.bolt_outlined,
            size: 18,
            color: exhausted
                ? AppPalette.warningFor(isDark: isDark)
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              switch (remaining) {
                null =>
                  'Grading uses one AI request per answer, from the same free '
                      'daily budget as the feed.',
                <= 0 =>
                  'Today\'s free AI budget is spent, so answers cannot be '
                      'graded until tomorrow. Review still works — it is '
                      'self-graded.',
                final left =>
                  '$left more graded ${left == 1 ? 'answer' : 'answers'} '
                      'today, from the same free budget as the feed.',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.action,
    required this.onTap,
    this.rubric = const <String>[],
    this.badge,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;

  /// Label on the card's own call to action. A card that opens a session
  /// should say so — a chevron alone left "is this a link or a setting?"
  /// unanswered on the one screen where every card does something different.
  final String action;

  final VoidCallback onTap;
  final List<String> rubric;
  final String? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Disabled cards mute their own colours rather than sitting under an
    // Opacity layer. The old 0.55 wrapper dragged the description — the part
    // explaining *why* there is nothing to do — below 4.5:1.
    final titleColor = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    final iconColor = enabled ? accent : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: Radii.xlAll,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The icon sits in an accent-tinted capsule, so the three
                    // modes are told apart by shape and colour before a word
                    // is read.
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.14),
                        borderRadius: Radii.mdAll,
                      ),
                      child: Icon(icon, size: 20, color: iconColor),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Wrap, not Row: at a large font scale the title and
                          // the badge together are wider than the card, and a
                          // Row would have overflowed rather than stacked.
                          Wrap(
                            spacing: Space.md,
                            runSpacing: Space.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: titleColor,
                                ),
                              ),
                              if (badge case final text?)
                                StatusChip(
                                  label: text,
                                  color: accent,
                                  icon: Icons.schedule_rounded,
                                ),
                            ],
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (rubric.isNotEmpty && enabled) ...[
                  const SizedBox(height: Space.lg),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final dimension in rubric)
                        StatusChip(
                          label: dimension,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: Space.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        enabled ? action : 'Nothing due',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: enabled
                              ? accent
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      enabled
                          ? Icons.arrow_forward_rounded
                          : Icons.check_rounded,
                      size: 18,
                      color: enabled
                          ? accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
