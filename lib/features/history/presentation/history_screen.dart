import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../../questions/data/question_repository.dart';

/// Everything the user has already seen, newest first.
final historyProvider = FutureProvider<List<QuestionWithState>>((ref) async {
  final all = await ref
      .watch(questionRepositoryProvider)
      .candidates(limit: 500);

  final seen = all.where((c) => c.wasSeen).toList()
    ..sort((a, b) {
      final aSeen = a.interaction?.lastSeenAt;
      final bSeen = b.interaction?.lastSeenAt;
      if (aSeen == null && bSeen == null) return 0;
      if (aSeen == null) return 1;
      if (bSeen == null) return -1;
      return bSeen.compareTo(aSeen);
    });

  return seen;
});

/// Reading history.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(historyProvider),
        child: switch (async) {
          AsyncLoading() => const QuestionListSkeleton(),
          AsyncError(:final error) => AppErrorState(
            title: "History didn't load",
            message:
                'Something went wrong reading your history. Trying again '
                'usually fixes it.',
            detail: error.toString(),
            onRetry: () => ref.invalidate(historyProvider),
          ),
          AsyncData(:final value) when value.isEmpty => const AppEmptyState(
            icon: Icons.history_rounded,
            title: 'Nothing here yet',
            message: 'Questions you have seen will appear here.',
          ),
          AsyncData(:final value) => ListView.builder(
            padding: Space.pagePadding,
            itemCount: value.length,
            itemBuilder: (context, index) => _HistoryTile(card: value[index]),
          ),
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.card});

  final QuestionWithState card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.forCategory(
      card.question.category.id,
      isDark: isDark,
    );
    final interaction = card.interaction;
    final timesSeen = interaction?.timesSeen ?? 0;

    // The state that actually distinguishes one history entry from another:
    // finished it, or scrolled past it. Each carries an icon as well as a
    // colour, so the distinction survives for anyone who cannot separate the
    // green from the grey.
    final (label, color, icon) = switch (card) {
      _ when card.isCompleted => (
        'Completed',
        AppPalette.successFor(isDark: isDark),
        Icons.check_circle_rounded,
      ),
      _ when interaction?.skipped ?? false => (
        'Skipped',
        theme.colorScheme.onSurfaceVariant,
        Icons.skip_next_rounded,
      ),
      _ => (
        'Seen',
        theme.colorScheme.onSurfaceVariant,
        Icons.visibility_rounded,
      ),
    };

    return QuestionTile(
      question: card.question,
      isSaved: card.isSaved,
      onTap: () => DeepDiveSheet.show(context, card.question),
      meta: [
        StatusChip(label: card.question.category.label, color: accent),
        StatusChip(label: label, color: color, icon: icon),
        if (timesSeen > 1)
          StatusChip(
            label: '$timesSeen×',
            color: theme.colorScheme.onSurfaceVariant,
            icon: Icons.repeat_rounded,
          ),
      ],
    );
  }
}
