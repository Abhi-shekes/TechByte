import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../feed/application/daily_session_controller.dart';
import '../../questions/data/question_repository.dart';
import '../../review/domain/spaced_repetition.dart';
import '../application/practice_controller.dart';

final _dueQuestionsProvider = FutureProvider<List<QuestionWithState>>(
  (ref) => ref.watch(questionRepositoryProvider).dueForReview(),
);

/// Questions due for another look.
///
/// Self-graded rather than AI-graded on purpose. Review is high-frequency by
/// design — spending an AI request every time someone re-checks a question
/// they already failed would burn the daily budget on the cheapest possible
/// judgement, and "did I actually know that?" is one the user can make.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_dueQuestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: switch (async) {
        AsyncLoading() => const QuestionListSkeleton(count: 3),
        AsyncError(:final error) => AppErrorState(
          title: "Review didn't load",
          message:
              'Something went wrong reading what is due. Trying again usually '
              'fixes it.',
          detail: error.toString(),
          onRetry: () => ref.invalidate(_dueQuestionsProvider),
        ),
        AsyncData(:final value) when value.isEmpty => const _AllCaughtUp(),
        AsyncData(:final value) => ListView.builder(
          padding: Space.pagePadding,
          itemCount: value.length,
          itemBuilder: (context, index) => _ReviewCard(card: value[index]),
        ),
      },
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.card});

  final QuestionWithState card;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _revealed = false;
  bool _answered = false;

  Future<void> _grade({required bool correct}) async {
    setState(() => _answered = true);

    final schedule = await ref
        .read(questionRepositoryProvider)
        .recordAnswer(widget.card.question.id, correct: correct);

    unawaited(
      ref
          .read(analyticsServiceProvider)
          .reviewAnswered(correct: correct, stage: schedule.stage),
    );
    ref.invalidate(dueForReviewCountProvider);
    if (!mounted) return;

    final days = schedule.dueAt.difference(DateTime.now()).inDays + 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          correct
              ? 'Nice — back in about $days ${days == 1 ? 'day' : 'days'}.'
              : 'No problem — back tomorrow.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final question = widget.card.question;
    final accent = AppPalette.forCategory(question.category.id, isDark: isDark);
    final stage = widget.card.interaction?.reviewStage ?? 0;

    if (_answered) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryMark(
                label: question.category.label,
                color: accent,
                trailing: Text(
                  'Stage ${stage + 1} of ${SpacedRepetition.intervals.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              Text(question.question, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Space.lg),

              if (!_revealed)
                OutlinedButton(
                  onPressed: () => setState(() => _revealed = true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, Sizes.buttonMd),
                  ),
                  child: const Text('Show answer'),
                )
              else ...[
                Text(question.shortAnswer, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Space.xl),
                Text(
                  'Did you actually know that?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _grade(correct: false),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Not really'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.dangerFor(isDark: isDark),
                          minimumSize: const Size(0, Sizes.buttonMd),
                          side: BorderSide(
                            color: AppPalette.dangerFor(
                              isDark: isDark,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _grade(correct: true),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('I knew it'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.successFor(
                            isDark: isDark,
                          ),
                          foregroundColor: AppPalette.onSuccessFor(
                            isDark: isDark,
                          ),
                          minimumSize: const Size(0, Sizes.buttonMd),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppEmptyState(
      icon: Icons.check_circle_outline_rounded,
      iconColor: AppPalette.successFor(isDark: isDark),
      title: 'All caught up',
      message:
          'Nothing is due for review. Questions you get wrong in Practice '
          'come back here after a day, then three, then a week.',
    );
  }
}
