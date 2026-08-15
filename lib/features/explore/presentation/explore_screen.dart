import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';
import '../../search/presentation/search_screen.dart';
import 'category_questions_screen.dart';

final topicProgressProvider = FutureProvider<Map<Category, TopicProgress>>(
  (ref) => ref.watch(questionRepositoryProvider).topicProgress(),
);

/// Browse the taxonomy: every category, what it holds, and how far through it
/// the user is.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topicProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(topicProgressProvider),
        child: switch (async) {
          AsyncLoading() => const TileGridSkeleton(),
          AsyncError(:final error) => AppErrorState(
            title: "Topics didn't load",
            message:
                'Something went wrong reading your topics. Trying again '
                'usually fixes it.',
            detail: error.toString(),
            onRetry: () => ref.invalidate(topicProgressProvider),
          ),
          AsyncData(:final value) => _CategoryGrid(progress: value),
        },
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.progress});

  final Map<Category, TopicProgress> progress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Started topics first, then the rest. Declaration order put eighteen
    // identical tiles on screen with nothing to distinguish where the user
    // actually is — sorting by engagement makes the grid answer "where was I?"
    // before it answers "what exists?".
    final started = <Category>[];
    final untouched = <Category>[];
    for (final category in Category.values) {
      final seen = progress[category]?.seen ?? 0;
      (seen > 0 ? started : untouched).add(category);
    }
    started.sort(
      (a, b) => (progress[b]?.seen ?? 0).compareTo(progress[a]?.seen ?? 0),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: AppSearchBar.navigational(
              hintText: 'Search every question',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              ),
            ),
          ),
        ),
        if (started.isNotEmpty) ...[
          _Header(
            title: 'In progress',
            description: 'Topics you have already met.',
          ),
          _Grid(categories: started, progress: progress, isDark: isDark),
        ],
        if (untouched.isNotEmpty) ...[
          _Header(
            title: started.isEmpty ? 'All topics' : 'Not started',
            description: started.isEmpty
                ? 'Tap any topic to see what is inside it.'
                : null,
          ),
          _Grid(categories: untouched, progress: progress, isDark: isDark),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.xxxl)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: SectionHeader(title, description: description),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.categories,
    required this.progress,
    required this.isDark,
  });

  final List<Category> categories;
  final Map<Category, TopicProgress> progress;
  final bool isDark;

  /// Everything in a tile that is not text: padding, the accent rule, the gaps
  /// between the three blocks, and the meter track.
  static const _tileChrome =
      Space.lg * 2 + _CategoryTile.ruleHeight + Space.lg + Space.xs +
      Space.md + Sizes.meterTrack;

  @override
  Widget build(BuildContext context) {
    // A fixed `childAspectRatio` was the bug: the tile's content is text, so
    // its height is a function of the user's font scale, while the ratio made
    // the cell a function of the screen width alone. At any scale above ~1.1
    // the title and the meter ran past the bottom of the card. Deriving a
    // `mainAxisExtent` from the same scaler the text will use keeps the two in
    // step, and the tile itself no longer depends on the number being right.
    final scaler = MediaQuery.textScalerOf(context);
    final width = MediaQuery.sizeOf(context).width;

    final extent =
        _tileChrome +
        // Two lines of `titleMedium` (16 / 1.4) plus one of `bodySmall`
        // (13 / 1.45) — the tallest the tile's text can legitimately get.
        scaler.scale(16 * 1.4 * 2) +
        scaler.scale(13 * 1.45);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          // Three across on a tablet or an unfolded device, where two tiles
          // stretched to half a 900px pane look like empty banners.
          crossAxisCount: width >= 600 ? 3 : 2,
          mainAxisSpacing: Space.md,
          crossAxisSpacing: Space.md,
          mainAxisExtent: extent,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryTile(
            category: category,
            progress: progress[category],
            accent: AppPalette.forCategory(category.id, isDark: isDark),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.progress,
    required this.accent,
  });

  /// Height of the accent rule at the top of the tile. Shared with the grid,
  /// which has to account for it when it sizes the cell.
  static const ruleHeight = 3.0;

  final Category category;
  final TopicProgress? progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = progress?.available ?? 0;
    final seen = progress?.seen ?? 0;
    final ratio = available == 0 ? 0.0 : (seen / available).clamp(0.0, 1.0);
    final detail = available == 0
        ? 'No questions yet'
        : '$seen of $available explored';

    // A Card with an InkWell rather than a bare Container: the tile inherits
    // the card radius instead of hand-rolling a different one, and it now
    // presses like the tappable thing it always looked like.
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CategoryQuestionsScreen(category: category),
          ),
        ),
        borderRadius: Radii.xlAll,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: ruleHeight,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
              const Spacer(),
              // Flexible rather than a bare Text: if the grid's estimate is
              // ever a pixel short — a font fallback with taller metrics, a
              // scaler the platform reports mid-frame — the title gives up
              // space instead of the card overflowing.
              Flexible(
                child: Text(
                  category.label,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.md),
              MeterBar(
                value: ratio,
                color: accent,
                semanticLabel: category.label,
                semanticValue: detail,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
