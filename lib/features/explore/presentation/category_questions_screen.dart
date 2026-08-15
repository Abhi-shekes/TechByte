import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';

final categoryQuestionsProvider =
    FutureProvider.family<List<QuestionWithState>, Category>((
      ref,
      category,
    ) async {
      final all = await ref
          .watch(questionRepositoryProvider)
          .candidates(categories: {category}, limit: 300);

      // Unseen first: the point of opening a category is to find something new
      // in it, and burying that under everything already read would make the
      // screen feel like an archive rather than a way in.
      return all..sort((a, b) {
        if (a.wasSeen != b.wasSeen) return a.wasSeen ? 1 : -1;
        return a.question.question.compareTo(b.question.question);
      });
    });

/// Every question in one category.
///
/// This screen is the reason the Explore grid exists. Without it the grid was
/// eighteen inviting tiles that did nothing when tapped — the most engaging
/// surface in the app was a dead end, with no route from a topic to its
/// content.
class CategoryQuestionsScreen extends ConsumerWidget {
  const CategoryQuestionsScreen({super.key, required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.forCategory(category.id, isDark: isDark);
    final async = ref.watch(categoryQuestionsProvider(category));

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(categoryQuestionsProvider(category)),
        child: switch (async) {
          AsyncLoading() => const QuestionListSkeleton(),
          AsyncError(:final error) => AppErrorState(
            title: "That topic didn't load",
            message:
                'Something went wrong reading ${category.label}. Trying again '
                'usually fixes it.',
            detail: error.toString(),
            onRetry: () => ref.invalidate(categoryQuestionsProvider(category)),
          ),
          AsyncData(:final value) when value.isEmpty => AppEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nothing here yet',
            message:
                'No ${category.label} questions are stored on this device. '
                'They arrive as you keep swiping the feed.',
          ),
          AsyncData(:final value) => ListView.builder(
            padding: Space.pagePadding,
            itemCount: value.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final unseen = value.where((c) => !c.wasSeen).length;
                return SectionHeader(
                  '${value.length} '
                  '${value.length == 1 ? 'question' : 'questions'}',
                  description: unseen == 0
                      ? 'You have seen all of these.'
                      : '$unseen still unseen.',
                  color: accent,
                );
              }

              final card = value[index - 1];
              return QuestionTile(
                question: card.question,
                isSaved: card.isSaved,
                meta: [
                  if (card.isCompleted)
                    StatusChip(
                      label: 'Completed',
                      color: AppPalette.successFor(isDark: isDark),
                      icon: Icons.check_circle_rounded,
                    )
                  else if (card.wasSeen)
                    StatusChip(
                      label: 'Seen',
                      color: theme.colorScheme.onSurfaceVariant,
                      icon: Icons.visibility_rounded,
                    ),
                  StatusChip(
                    label: card.question.difficulty.label,
                    color: theme.colorScheme.onSurfaceVariant,
                    icon: Icons.equalizer_rounded,
                  ),
                ],
                onTap: () => DeepDiveSheet.show(context, card.question),
              );
            },
          ),
        },
      ),
    );
  }
}
