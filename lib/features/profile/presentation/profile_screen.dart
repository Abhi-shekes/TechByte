import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../explore/presentation/explore_screen.dart';
import '../../history/presentation/history_screen.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';
import '../../saved/presentation/saved_screen.dart';
import '../../settings/presentation/settings_screen.dart';

final progressSummaryProvider = FutureProvider<ProgressSummary>(
  (ref) => ref.watch(questionRepositoryProvider).progressSummary(),
);

/// Progress and topic familiarity.
///
/// Answers one question — how am I doing? — and the answer now leads with the
/// number that actually says so. The screen used to open on an avatar and an
/// email address (things the user already knows about themselves) followed by
/// three bare figures on the page background, then a wall of identical bars.
/// Nothing was emphasised, so nothing was read.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final summary = ref.watch(progressSummaryProvider);
    final topics = ref.watch(topicProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(progressSummaryProvider)
            ..invalidate(topicProgressProvider);
        },
        child: ListView(
          padding: Space.pagePadding,
          children: [
            _AccountHeader(
              displayName: user?.displayName,
              email: user?.email,
              photoUrl: user?.photoURL,
            ),
            const SizedBox(height: Space.xl),

            switch (summary) {
              AsyncData(:final value) => _ProgressCard(summary: value),
              _ => const AppSkeleton(
                width: double.infinity,
                height: 132,
                borderRadius: Radii.xlAll,
              ),
            },
            const SizedBox(height: Space.md),

            const _QuickLinks(),
            const SizedBox(height: Space.xxxl),

            const SectionHeader(
              'Topic familiarity',
              description:
                  'How much of what you have seen you finished — not a skill '
                  'score.',
            ),
            switch (topics) {
              AsyncData(:final value) => _FamiliarityList(progress: value),
              AsyncError() => Text(
                'Topic progress could not be read.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              _ => const _FamiliaritySkeleton(),
            },
          ],
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.displayName,
    required this.email,
    required this.photoUrl,
  });

  final String? displayName;
  final String? email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.accentFor(isDark: isDark);

    return Row(
      children: [
        // A thin accent ring rather than a bigger avatar: it ties the one
        // personal element on the screen to the app's single accent colour
        // without spending more vertical space on it.
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.5), width: 2),
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.surfaceContainer,
            foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl!),
            child: Text(
              (displayName ?? email ?? '?').characters.first.toUpperCase(),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName ?? 'Signed in',
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (email case final address?)
                Text(
                  address,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one figure worth leading with, and the three that support it.
///
/// Completion is the number that answers "how am I doing", so it is the only
/// one given a ring and a headline. Viewed, completed and saved used to sit at
/// `displaySmall` alongside it — four numbers at one weight, which is the same
/// as no hierarchy at all.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.summary});

  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.accentFor(isDark: isDark);

    final ratio = summary.totalAvailable == 0
        ? 0.0
        : (summary.completed / summary.totalAvailable).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          children: [
            Row(
              children: [
                _Ring(value: ratio, color: accent),
                const SizedBox(width: Space.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${summary.completed} finished',
                        style: theme.textTheme.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        summary.totalAvailable == 0
                            ? 'Questions arrive as you use the feed.'
                            : 'of ${summary.totalAvailable} questions on this '
                                  'device',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.lg),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Viewed',
                    value: summary.viewed,
                    emphasis: StatEmphasis.secondary,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Completed',
                    value: summary.completed,
                    emphasis: StatEmphasis.secondary,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Saved',
                    value: summary.saved,
                    emphasis: StatEmphasis.secondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.surfaceContainer,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              letterSpacing: 0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the profile actually leads.
///
/// History was a single `ListTile` in a card, and Saved and Settings were
/// reachable only from the navigation bar and the app bar respectively. Three
/// destinations, three different mechanisms.
class _QuickLinks extends StatelessWidget {
  const _QuickLinks();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LinkTile(
            icon: Icons.history_rounded,
            label: 'History',
            builder: (_) => const HistoryScreen(),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: _LinkTile(
            icon: Icons.bookmark_rounded,
            label: 'Saved',
            builder: (_) => const SavedScreen(),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: _LinkTile(
            icon: Icons.settings_rounded,
            label: 'Settings',
            builder: (_) => const SettingsScreen(),
          ),
        ),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: Radii.xlAll,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: builder)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.lg,
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: Space.sm),
              Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamiliarityList extends StatelessWidget {
  const _FamiliarityList({required this.progress});

  final Map<Category, TopicProgress> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Only categories the user has actually met — a wall of empty bars for
    // eighteen untouched categories tells them nothing.
    final engaged = progress.entries.where((e) => e.value.seen > 0).toList()
      ..sort((a, b) => b.value.familiarity.compareTo(a.value.familiarity));

    if (engaged.isEmpty) {
      return AppPanel.notice(
        child: Text(
          'Answer a few questions and your topics will show up here.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final strongest = engaged.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The list is sorted, so the top row already holds this — but a sorted
        // list only says "strongest" to someone who noticed it was sorted.
        if (strongest.value.familiarity > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: AppPanel.notice(
              accent: AppPalette.forCategory(strongest.key.id, isDark: isDark),
              child: Text(
                'Strongest so far: ${strongest.key.label}, at '
                '${(strongest.value.familiarity * 100).round()}%.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        for (final entry in engaged)
          MeterRow(
            label: entry.key.label,
            value: entry.value.familiarity,
            color: AppPalette.forCategory(entry.key.id, isDark: isDark),
            valueLabel: '${(entry.value.familiarity * 100).round()}%',
            semanticValue:
                '${(entry.value.familiarity * 100).round()} percent '
                'familiar, ${entry.value.completed} of ${entry.value.seen} '
                'completed',
          ),
      ],
    );
  }
}

class _FamiliaritySkeleton extends StatelessWidget {
  const _FamiliaritySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppSkeleton(width: double.infinity, height: 18),
        SizedBox(height: Space.md),
        AppSkeleton(width: double.infinity, height: 18),
        SizedBox(height: Space.md),
        AppSkeleton(width: double.infinity, height: 18),
      ],
    );
  }
}
