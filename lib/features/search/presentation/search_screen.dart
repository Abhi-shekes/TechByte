import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../../explore/presentation/explore_screen.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';

final searchResultsProvider =
    FutureProvider.family<List<QuestionWithState>, String>(
      (ref, query) => ref.watch(questionRepositoryProvider).search(query),
    );

/// Suggested terms, drawn from the categories the user actually reads.
///
/// Replaces a hardcoded list of eight terms that had no relationship to what
/// was on the device — suggesting "kafka" to someone who has only ever read
/// hardware questions is a dead end dressed as a shortcut.
final searchSuggestionsProvider = FutureProvider<List<Category>>((ref) async {
  final progress = await ref.watch(topicProgressProvider.future);
  final engaged = progress.entries.where((e) => e.value.seen > 0).toList()
    ..sort((a, b) => b.value.seen.compareTo(a.value.seen));

  if (engaged.isEmpty) {
    // Nothing read yet: offer the categories with the most to offer.
    final stocked =
        progress.entries.where((e) => e.value.available > 0).toList()
          ..sort((a, b) => b.value.available.compareTo(a.value.available));
    return stocked.take(6).map((e) => e.key).toList();
  }
  return engaged.take(6).map((e) => e.key).toList();
});

/// Search across everything stored on the device.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Committed query. Debounced so a fast typist does not run a query per
  /// keystroke — cheap here since it is local, but it also stops the result
  /// list flickering through partial matches.
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppDurations.debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _useSuggestion(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search questions, topics, tags…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: _query.length < 2
          ? _Suggestions(onSelected: _useSuggestion)
          : switch (ref.watch(searchResultsProvider(_query))) {
              AsyncLoading() => const QuestionListSkeleton(count: 4),
              AsyncError(:final error) => AppErrorState(
                title: "Search didn't run",
                message:
                    'Something went wrong searching this device. Trying again '
                    'usually fixes it.',
                detail: error.toString(),
                onRetry: () => ref.invalidate(searchResultsProvider(_query)),
              ),
              AsyncData(:final value) when value.isEmpty => AppEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                message:
                    'Nothing on this device matches "$_query". More questions '
                    'arrive as you keep swiping.',
              ),
              AsyncData(:final value) => ListView.builder(
                padding: Space.pagePadding,
                itemCount: value.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return SectionHeader(
                      '${value.length} '
                      '${value.length == 1 ? 'result' : 'results'}',
                    );
                  }
                  return _ResultTile(card: value[index - 1], query: _query);
                },
              ),
            },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.card, required this.query});

  final QuestionWithState card;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = card.question;
    final accent = AppPalette.forCategory(
      question.category.id,
      isDark: theme.brightness == Brightness.dark,
    );

    return QuestionTile(
      question: question,
      isSaved: card.isSaved,
      onTap: () => DeepDiveSheet.show(context, question),
      titleOverride: _Highlighted(
        text: question.question,
        query: query,
        style: theme.textTheme.titleMedium,
        highlight: accent,
      ),
      meta: [StatusChip(label: question.category.label, color: accent)],
    );
  }
}

/// Highlights every occurrence of the query inside a result title.
///
/// Matching is done on a lowercased copy while the original casing is
/// rendered, so highlighting never alters the text the user reads.
class _Highlighted extends StatelessWidget {
  const _Highlighted({
    required this.text,
    required this.query,
    required this.highlight,
    this.style,
  });

  final String text;
  final String query;
  final Color highlight;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();

    if (needle.isEmpty || !haystack.contains(needle)) {
      return Text(text, style: style);
    }

    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = haystack.indexOf(needle, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + needle.length),
          style: TextStyle(color: highlight, fontWeight: FontWeight.w700),
        ),
      );
      start = index + needle.length;
    }

    return Text.rich(TextSpan(children: spans), style: style);
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final suggestions = ref.watch(searchSuggestionsProvider);

    return ListView(
      padding: Space.pagePadding,
      children: [
        const SectionHeader('Try'),
        if (suggestions case AsyncData(:final value))
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final category in value)
                ActionChip(
                  label: Text(category.label),
                  avatar: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppPalette.forCategory(
                        category.id,
                        isDark: isDark,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  onPressed: () => onSelected(category.label),
                ),
            ],
          ),
        const SizedBox(height: Space.xxl),
        Text(
          'Search runs entirely on this device, so it works offline and costs '
          'nothing.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
