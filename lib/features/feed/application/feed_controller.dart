import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/ai_config.dart';
import '../../../app/config/feed_config.dart';
import '../../../core/providers/core_providers.dart';
import 'daily_session_controller.dart';
import '../../questions/data/question_repository.dart';
import '../../questions/domain/question_enums.dart';
import '../../../services/ai/ai_result.dart';
import '../domain/feed_selector.dart';

/// Immutable snapshot of the feed.
@immutable
class FeedState {
  const FeedState({
    this.cards = const [],
    this.currentIndex = 0,
    this.isGenerating = false,
    this.aiNotice,
  });

  /// The queue of cards, current one at [currentIndex]. Grows forward as the
  /// user swipes; earlier entries are kept so back-swiping works.
  final List<QuestionWithState> cards;
  final int currentIndex;

  /// True while a background generation run is in flight. Surfaced subtly —
  /// generation must never gate a swipe.
  final bool isGenerating;

  /// Set when generation last failed or was skipped, so the UI can explain
  /// itself honestly instead of silently showing the same questions again.
  final AiUnavailableReason? aiNotice;

  bool get isEmpty => cards.isEmpty;

  QuestionWithState? get current =>
      currentIndex < cards.length ? cards[currentIndex] : null;

  FeedState copyWith({
    List<QuestionWithState>? cards,
    int? currentIndex,
    bool? isGenerating,
    AiUnavailableReason? aiNotice,
    bool clearNotice = false,
  }) {
    return FeedState(
      cards: cards ?? this.cards,
      currentIndex: currentIndex ?? this.currentIndex,
      isGenerating: isGenerating ?? this.isGenerating,
      aiNotice: clearNotice ? null : (aiNotice ?? this.aiNotice),
    );
  }
}

final feedConfigProvider = Provider<FeedConfig>((ref) => const FeedConfig());

final feedControllerProvider = AsyncNotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

/// Drives the vertical feed.
///
/// The contract that shapes this class: a swipe must never wait on anything.
/// Cards are selected from an in-memory pool that was loaded up front, and
/// both database writes and AI generation are fired off without being awaited
/// on the swipe path.
class FeedController extends AsyncNotifier<FeedState> {
  late FeedSelector _selector;
  late FeedConfig _config;

  /// Everything eligible, loaded from the database. Refreshed after generation.
  List<QuestionWithState> _pool = const [];

  /// Guards against overlapping generation runs, which would double-spend the
  /// AI budget for the same refill.
  bool _generating = false;

  @override
  Future<FeedState> build() async {
    _config = ref.watch(feedConfigProvider);
    _selector = FeedSelector(config: _config);

    final repo = ref.watch(questionRepositoryProvider);
    await repo.ensureSeeded();
    await _loadPool();

    final initial = _extend(const FeedState(), to: _config.bufferSize);
    unawaited(ref.read(analyticsServiceProvider).feedStarted());
    if (initial.cards.isNotEmpty) {
      final first = initial.cards.first.question;
      unawaited(_markSeen(first.id));
      unawaited(ref.read(analyticsServiceProvider).questionViewed(first));
    }
    return initial;
  }

  Future<void> _loadPool() async {
    _pool = await ref.read(questionRepositoryProvider).candidates();
  }

  /// Appends cards until the queue holds [to] entries beyond the current index.
  FeedState _extend(FeedState current, {required int to}) {
    final cards = [...current.cards];
    final queued = cards.map((c) => c.question.id).toSet();
    final context = _feedContext();

    final target = current.currentIndex + to;
    while (cards.length < target) {
      final next = _selector.next(
        pool: _pool,
        context: context,
        alreadyQueued: queued,
        recentCategories: cards
            .map((c) => c.question.category)
            .toList(growable: false),
      );
      if (next == null) break;
      cards.add(next);
      queued.add(next.question.id);
    }

    return current.copyWith(cards: cards);
  }

  FeedContext _feedContext() {
    final prefs = ref.read(userPreferencesProvider);
    return FeedContext(
      topicProgress: _topicProgress,
      preferredCategories: prefs.topics,
      level: prefs.level,
      goal: prefs.goal,
    );
  }

  Map<Category, TopicProgress> _topicProgress = const {};

  /// Called by the PageView when the visible card changes.
  ///
  /// Deliberately synchronous in its state update: the new page must render
  /// immediately, so persistence and prefetching are dispatched without await.
  void onPageChanged(int index) {
    final current = state.value;
    if (current == null) return;

    final previous = current.currentIndex;
    var next = current.copyWith(currentIndex: index);

    // A forward swipe past an unrevealed card counts as a skip.
    if (index > previous && previous < current.cards.length) {
      final left = current.cards[previous];
      if (!(left.interaction?.revealed ?? false)) {
        unawaited(
          ref.read(questionRepositoryProvider).markSkipped(left.question.id),
        );
        unawaited(
          ref.read(analyticsServiceProvider).questionSkipped(left.question),
        );
      }
    }

    if (index < next.cards.length) {
      final question = next.cards[index].question;
      unawaited(_markSeen(question.id));
      unawaited(ref.read(analyticsServiceProvider).questionViewed(question));
    }

    next = _extend(next, to: _config.bufferSize);
    state = AsyncData(next);

    _maybeGenerate();
  }

  Future<void> _markSeen(String questionId) async {
    await ref.read(questionRepositoryProvider).markSeen(questionId);
  }

  Future<void> reveal(String questionId) async {
    final repo = ref.read(questionRepositoryProvider);
    await repo.markRevealed(questionId);
    await repo.markCompleted(questionId);
    await _refreshCard(questionId);
  }

  Future<void> toggleSaved(String questionId) async {
    final current = state.value;
    if (current == null) return;

    final card = current.cards.firstWhere(
      (c) => c.question.id == questionId,
      orElse: () => current.cards.first,
    );
    await ref
        .read(questionRepositoryProvider)
        .setSaved(questionId, saved: !card.isSaved);
    await _refreshCard(questionId);
  }

  Future<void> report(String questionId) async {
    await ref.read(questionRepositoryProvider).report(questionId);
    await _loadPool();
  }

  /// Re-reads one card's interaction row and swaps it into the queue, so the
  /// bookmark and completion states stay accurate without rebuilding the feed.
  Future<void> _refreshCard(String questionId) async {
    final current = state.value;
    if (current == null) return;

    final interaction = await ref
        .read(questionRepositoryProvider)
        .interaction(questionId);

    final cards = [
      for (final card in current.cards)
        if (card.question.id == questionId)
          QuestionWithState(question: card.question, interaction: interaction)
        else
          card,
    ];
    state = AsyncData(current.copyWith(cards: cards));
  }

  /// Tops the local pool up with generated questions when it runs low.
  ///
  /// Fire-and-forget, guarded, and entirely optional: if generation is
  /// disabled, out of budget, or offline, the feed keeps running on what is
  /// already stored. That fallback chain is the point.
  void _maybeGenerate() {
    if (_generating) return;

    final unseen = _pool.where((q) => !q.wasSeen).length;
    if (unseen >= AiConfig.refillThreshold) return;

    final prefs = ref.read(userPreferencesProvider);
    if (!prefs.aiGenerationEnabled) return;

    _generating = true;
    unawaited(_generate());
  }

  Future<void> _generate() async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(isGenerating: true, clearNotice: true),
      );
    }

    try {
      final gemini = ref.read(geminiServiceProvider);
      final repo = ref.read(questionRepositoryProvider);
      final prefs = ref.read(userPreferencesProvider);

      final result = await gemini.generateQuestions(
        categories: prefs.topics.toList(growable: false),
        level: prefs.level,
        goal: prefs.goal,
        avoidQuestions: await repo.recentQuestionTexts(),
      );

      switch (result) {
        case AiSuccess(:final value):
          if (value.isNotEmpty) {
            await repo.insertAll(value);
            await _loadPool();
          }
          unawaited(
            ref
                .read(analyticsServiceProvider)
                .generationSucceeded(value.length),
          );
          _finishGeneration(notice: null);
        case AiUnavailable(:final reason):
          unawaited(
            ref.read(analyticsServiceProvider).generationUnavailable(reason),
          );
          _finishGeneration(notice: reason);
      }
    } on Exception {
      _finishGeneration(notice: AiUnavailableReason.unknown);
    } finally {
      _generating = false;
    }
  }

  void _finishGeneration({required AiUnavailableReason? notice}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        isGenerating: false,
        aiNotice: notice,
        clearNotice: notice == null,
      ),
    );
  }

  /// Pull-to-refresh: reload progress and the pool, then rebuild the queue.
  Future<void> refresh() async {
    _topicProgress = await ref.read(questionRepositoryProvider).topicProgress();
    await _loadPool();
    final current = state.value ?? const FeedState();
    state = AsyncData(
      _extend(current.copyWith(clearNotice: true), to: _config.bufferSize),
    );
  }
}
