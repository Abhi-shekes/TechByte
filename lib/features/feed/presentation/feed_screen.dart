import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../../services/ai/ai_result.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question.dart';
import '../application/daily_session_controller.dart';
import '../application/feed_controller.dart';
import 'widgets/daily_session_card.dart';
import 'widgets/question_card.dart';

/// The home feed: one full-screen question per page, swiped vertically.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _pageController = PageController();

  /// The swipe hint is a teaching aid, not a permanent label.
  static const _hintCardCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedControllerProvider);
    final prefs = ref.watch(userPreferencesProvider);

    return Scaffold(
      body: switch (async) {
        AsyncLoading() => const FeedCardSkeleton(),
        AsyncError(:final error) => AppErrorState(
          title: "The feed couldn't load",
          message:
              'Something went wrong building your feed. Trying again usually '
              'fixes it.',
          detail: error.toString(),
          onRetry: () => ref.invalidate(feedControllerProvider),
        ),
        AsyncData(:final value) when value.isEmpty => const _FeedEmpty(),
        AsyncData(:final value) => Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: value.cards.length,
              onPageChanged: ref
                  .read(feedControllerProvider.notifier)
                  .onPageChanged,
              itemBuilder: (context, index) {
                final card = value.cards[index];
                return QuestionCard(
                  // Keyed by question so recycling a page element for a
                  // different question resets its reveal state.
                  key: ValueKey(card.question.id),
                  card: card,
                  hapticsEnabled: prefs.hapticsEnabled,
                  showSwipeHint: index < _hintCardCount,
                  header: const DailySessionCard(),
                  onReveal: () => _reveal(card.question),
                  onToggleSave: () => _toggleSave(card),
                  onGoDeeper: () {
                    ref
                        .read(analyticsServiceProvider)
                        .deepDiveOpened(card.question);
                    DeepDiveSheet.show(context, card.question);
                  },
                  onShare: () => _share(card.question),
                  onReport: () => _report(card.question.id),
                );
              },
            ),
            if (value.aiNotice != null)
              Positioned(
                left: Space.gutter,
                right: Space.gutter,
                bottom: Space.md,
                child: _AiNotice(reason: value.aiNotice!),
              ),
          ],
        ),
      },
    );
  }

  Future<void> _reveal(Question question) async {
    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.answerRevealed(question));
    unawaited(analytics.questionCompleted(question));

    await ref.read(feedControllerProvider.notifier).reveal(question.id);
    // Completing a question may finish the daily set, so recompute progress.
    await ref.read(dailySessionProvider.notifier).refresh();
  }

  Future<void> _toggleSave(QuestionWithState card) async {
    if (!card.isSaved) {
      unawaited(
        ref.read(analyticsServiceProvider).questionSaved(card.question),
      );
    }
    await ref
        .read(feedControllerProvider.notifier)
        .toggleSaved(card.question.id);
  }

  /// Share text built to look like the card, not like a link dump.
  Future<void> _share(Question question) async {
    final buffer = StringBuffer()
      ..writeln('TECHBYTE')
      ..writeln()
      ..writeln(question.question)
      ..writeln()
      ..writeln(question.shortAnswer)
      ..writeln()
      ..write('Think. Learn. Repeat.');

    unawaited(ref.read(analyticsServiceProvider).questionShared(question));
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  Future<void> _report(String questionId) async {
    final question = await ref
        .read(questionRepositoryProvider)
        .byId(questionId);
    if (question != null) {
      unawaited(ref.read(analyticsServiceProvider).questionReported(question));
    }
    await ref.read(feedControllerProvider.notifier).report(questionId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thanks — that question will stop appearing.'),
      ),
    );
  }
}

/// Non-blocking explanation of why new questions stopped arriving.
///
/// Shown rather than hidden: running out of free quota is an expected state in
/// this app, and silently repeating old questions would be worse than saying so.
class _AiNotice extends StatelessWidget {
  const _AiNotice({required this.reason});

  final AiUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel.notice(
      depth: Depth.overlay,
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              '${reason.message} · showing saved questions',
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

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.inbox_rounded,
      title: 'Nothing left to ask',
      message:
          'You have seen everything stored on this device. New questions '
          'arrive when you are online.',
    );
  }
}
