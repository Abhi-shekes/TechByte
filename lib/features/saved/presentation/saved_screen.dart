import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';

final savedQuestionsProvider = StreamProvider<List<QuestionWithState>>(
  (ref) => ref.watch(questionRepositoryProvider).watchSaved(),
);

/// Bookmarked questions, grouped by category.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(savedQuestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: switch (async) {
        AsyncLoading() => const QuestionListSkeleton(),
        AsyncError(:final error) => AppErrorState(
          title: "Saved didn't load",
          message:
              'Something went wrong reading your bookmarks. Trying again '
              'usually fixes it.',
          detail: error.toString(),
          onRetry: () => ref.invalidate(savedQuestionsProvider),
        ),
        AsyncData(:final value) => _buildList(context, value),
      },
    );
  }

  Widget _buildList(BuildContext context, List<QuestionWithState> saved) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (saved.isEmpty) {
      return const AppEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'Nothing saved yet',
        message: 'Tap the bookmark on any question to keep it here.',
      );
    }

    // Local search only — the saved set is small and already on-device, so
    // there is no reason to spend an AI request on it.
    final filtered = _query.isEmpty
        ? saved
        : saved
              .where((s) {
                final q = s.question;
                final haystack =
                    '${q.question} ${q.shortAnswer} ${q.category.label} '
                            '${q.subcategory ?? ''} ${q.tags.join(' ')}'
                        .toLowerCase();
                return haystack.contains(_query.toLowerCase());
              })
              .toList(growable: false);

    final grouped = <Category, List<QuestionWithState>>{};
    for (final item in filtered) {
      grouped.putIfAbsent(item.question.category, () => []).add(item);
    }

    return ListView(
      padding: Space.pagePadding,
      children: [
        AppSearchBar(
          hintText: 'Search saved',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: Space.xl),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.huge),
            child: Center(
              child: Text(
                'No saved questions match "$_query".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final entry in grouped.entries) ...[
          SectionHeader(
            entry.key.label,
            color: AppPalette.forCategory(entry.key.id, isDark: isDark),
          ),
          for (final item in entry.value)
            QuestionTile(
              question: item.question,
              onTap: () => DeepDiveSheet.show(context, item.question),
              trailing: IconButton(
                icon: const Icon(Icons.bookmark_remove_rounded),
                tooltip: 'Remove bookmark',
                onPressed: () => ref
                    .read(questionRepositoryProvider)
                    .setSaved(item.question.id, saved: false),
              ),
            ),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}
