import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../../services/ai/ai_result.dart';
import '../../deep_dive/presentation/deep_dive_sheet.dart';
import '../application/practice_controller.dart';
import '../domain/answer_evaluation.dart';
import '../domain/practice_mode.dart';

/// Whether a question is bookmarked, live.
///
/// A stream rather than a one-shot read so the bookmark button in a session
/// agrees with the one in the feed without either having to know about the
/// other.
final _isSavedProvider = StreamProvider.family<bool, String>(
  (ref, questionId) => ref
      .watch(questionRepositoryProvider)
      .watchInteraction(questionId)
      .map((interaction) => interaction?.saved ?? false),
);

/// One graded practice session: read the problem, write an answer, get scored.
class PracticeSessionScreen extends ConsumerStatefulWidget {
  const PracticeSessionScreen({super.key, required this.mode});

  final PracticeMode mode;

  @override
  ConsumerState<PracticeSessionScreen> createState() =>
      _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends ConsumerState<PracticeSessionScreen> {
  final _answerController = TextEditingController();
  final _scrollController = ScrollController();
  final _answerFocus = FocusNode();

  bool _hintRevealed = false;

  @override
  void initState() {
    super.initState();
    // Deferred: the controller mutates provider state, which cannot happen
    // during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(practiceControllerProvider.notifier).start(widget.mode);
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    _scrollController.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref
        .read(practiceControllerProvider.notifier)
        .submit(_answerController.text);
    if (!mounted) return;

    // Bring the verdict into view rather than leaving it below the fold.
    // Honours reduced motion, which this animation previously ignored.
    await _scrollToEnd();
  }

  Future<void> _scrollToEnd() async {
    if (!_scrollController.hasClients) return;
    final duration = Motion.of(context, AppDurations.slow);
    if (duration == Duration.zero) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    } else {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: duration,
        curve: AppCurves.standard,
      );
    }
  }

  Future<void> _next() async {
    await ref.read(practiceControllerProvider.notifier).next();
  }

  Future<void> _skip() async {
    await ref.read(practiceControllerProvider.notifier).skip();
  }

  /// Re-answer the same question, with the ideal answer still fresh.
  void _retry() {
    ref.read(practiceControllerProvider.notifier).retry();
    _answerFocus.requestFocus();
  }

  /// Drops one of the mode's openers in at the cursor.
  ///
  /// Inserted at the caret rather than appended, so it works as a way to
  /// restructure an answer halfway through and not only as a way to start one.
  void _insertScaffold(String snippet) {
    final text = _answerController.text;
    final selection = _answerController.selection;
    final at = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;

    final before = text.substring(0, at);
    final after = text.substring(at);

    // Whatever came before decides the joint: nothing and a fresh line need no
    // separator, a finished sentence gets a paragraph break, anything else a
    // single space. Without this the chips produced "…own wordsFor example,".
    final trimmed = before.trimRight();
    final separator = trimmed.isEmpty
        ? ''
        : (trimmed.endsWith('.') ||
              trimmed.endsWith('?') ||
              trimmed.endsWith('!'))
        ? '\n\n'
        : (before.endsWith(' ') || before.endsWith('\n'))
        ? ''
        : ' ';

    final insertion = '$separator$snippet';
    final head = '$before$insertion';

    _answerController.value = TextEditingValue(
      text: '$head$after',
      selection: TextSelection.collapsed(offset: head.length),
    );
    _answerFocus.requestFocus();
  }

  void _onStateChanged(PracticeState? previous, PracticeState next) {
    // A new task means a new blank answer, a re-armed hint and a reset clock.
    // The answer box used to be cleared by `_next` only, so skipping — or a
    // reload of any other kind — carried the previous answer over.
    if (previous?.task?.promptText != next.task?.promptText) {
      _answerController.clear();
      if (_hintRevealed) setState(() => _hintRevealed = false);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(practiceControllerProvider, _onStateChanged);

    final state = ref.watch(practiceControllerProvider);
    final task = state.task;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode.label),
        actions: [
          if (state.completed > 0)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Center(child: _SessionPill(state: state)),
            ),
        ],
      ),
      body: state.isLoading
          ? const _TaskSkeleton()
          : task == null
          ? _NothingToPractise(
              mode: widget.mode,
              notice: state.notice,
              onRetry: () => ref
                  .read(practiceControllerProvider.notifier)
                  .start(widget.mode),
            )
          : ListView(
              controller: _scrollController,
              padding: Space.pagePadding,
              children: [
                _TaskPrompt(task: task),
                const SizedBox(height: Space.xl),

                if (state.evaluation == null) ...[
                  _Composer(
                    mode: widget.mode,
                    task: task,
                    controller: _answerController,
                    focusNode: _answerFocus,
                    isGrading: state.isGrading,
                    hintRevealed: _hintRevealed,
                    onRevealHint: () => setState(() => _hintRevealed = true),
                    onScaffold: _insertScaffold,
                    onSubmit: _submit,
                    onSkip: _skip,
                  ),
                ],

                if (state.notice case final reason?) ...[
                  const SizedBox(height: Space.lg),
                  _Notice(
                    reason: reason,
                    onRetry: reason.isRetryable && state.evaluation == null
                        ? _submit
                        : null,
                  ),
                ],

                if (state.evaluation case final evaluation?) ...[
                  _EvaluationView(
                    evaluation: evaluation,
                    answer: _answerController.text,
                  ),
                  const SizedBox(height: Space.xl),
                  _AfterActions(task: task, onNext: _next, onRetry: _retry),
                ],
              ],
            ),
    );
  }
}

/// Session so far, in the app bar.
class _SessionPill extends StatelessWidget {
  const _SessionPill({required this.state});

  final PracticeState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final average = state.averageScore;

    return StatusChip(
      label: average == null
          ? '${state.completed} done'
          : '${state.completed} · avg ${average.toStringAsFixed(1)}',
      color: AppPalette.accentFor(isDark: isDark),
      icon: Icons.timeline_rounded,
    );
  }
}

// ---------------------------------------------------------------------------
// The prompt
// ---------------------------------------------------------------------------

class _TaskPrompt extends StatelessWidget {
  const _TaskPrompt({required this.task});

  final PracticeTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return switch (task) {
      InterviewTask(:final question) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryMark(
            label: 'Interviewer',
            color: AppPalette.forCategory(question.category.id, isDark: isDark),
          ),
          const SizedBox(height: Space.lg),
          Text(question.question, style: theme.textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          // Context the grader has and the user did not: which topic this is
          // and how hard it is meant to be. A bare question with no framing was
          // the single most "unfinished" thing on this screen.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              StatusChip(
                label: question.category.label,
                color: AppPalette.forCategory(
                  question.category.id,
                  isDark: isDark,
                ),
                icon: Icons.folder_outlined,
              ),
              StatusChip(
                label: question.difficulty.label,
                color: theme.colorScheme.onSurfaceVariant,
                icon: Icons.equalizer_rounded,
              ),
              StatusChip(
                label: question.type.label,
                color: theme.colorScheme.onSurfaceVariant,
                icon: Icons.style_outlined,
              ),
            ],
          ),
        ],
      ),
      DebugTask(:final scenario) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryMark(
            label: 'Incident',
            color: AppPalette.dangerFor(isDark: isDark),
          ),
          const SizedBox(height: Space.lg),
          Text(scenario.title, style: theme.textTheme.displayMedium),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              StatusChip(
                label: 'Live incident',
                color: AppPalette.dangerFor(isDark: isDark),
                icon: Icons.sensors_rounded,
              ),
              StatusChip(
                label: scenario.category.label,
                color: AppPalette.forCategory(
                  scenario.category.id,
                  isDark: isDark,
                ),
                icon: Icons.folder_outlined,
              ),
              StatusChip(
                label: scenario.difficulty.label,
                color: theme.colorScheme.onSurfaceVariant,
                icon: Icons.equalizer_rounded,
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(scenario.situation, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Space.xl),
          _Telemetry(metrics: scenario.metrics),
          const SizedBox(height: Space.xl),
          // The ask, given the weight of a heading rather than sitting as one
          // more paragraph under the numbers.
          AppPanel(
            accent: AppPalette.dangerFor(isDark: isDark),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: AppPalette.dangerFor(isDark: isDark),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    scenario.prompt,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    };
  }
}

/// The observed signals, as a readable table.
///
/// Metrics are the whole exercise — they are what rules causes out — so they
/// get a titled panel with a row per signal rather than an unlabelled block.
/// The label column used to be a hard-coded 150px, which at a large font scale
/// squeezed the values into a two-character-wide ribbon.
class _Telemetry extends StatelessWidget {
  const _Telemetry({required this.metrics});

  final List<({String label, String value})> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'WHAT THE DASHBOARDS SHOW',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0)
              Divider(height: Space.md * 2, color: theme.colorScheme.outline),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flex rather than a fixed width: both columns keep their
                // proportion at every font scale and neither can be crushed.
                Expanded(
                  flex: 5,
                  child: Text(
                    metrics[i].label,
                    style: AppTypography.monoSmall(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 6,
                  child: Text(
                    metrics[i].value,
                    style: AppTypography.monoSmall(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Writing the answer
// ---------------------------------------------------------------------------

/// Everything between reading the problem and being graded.
///
/// Previously this was an instruction line, a bare `TextField` and one button.
/// Nothing told you how long an answer should be, nothing helped when you were
/// stuck, and the only way past a question you could not answer was to leave
/// the screen. The four additions here — pacing, openers, a hint and a skip —
/// each remove one of those dead ends, and none of them spends an AI request.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.mode,
    required this.task,
    required this.controller,
    required this.focusNode,
    required this.isGrading,
    required this.hintRevealed,
    required this.onRevealHint,
    required this.onScaffold,
    required this.onSubmit,
    required this.onSkip,
  });

  final PracticeMode mode;
  final PracticeTask task;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isGrading;
  final bool hintRevealed;
  final VoidCallback onRevealHint;
  final ValueChanged<String> onScaffold;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.accentFor(isDark: isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PacingBar(
          key: ValueKey(task.promptText),
          target: task.targetDuration,
          running: !isGrading,
        ),
        const SizedBox(height: Space.lg),

        Text(
          mode.instruction,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.md),

        // Openers. Tapping one writes it at the cursor, so the shape the
        // rubric rewards is available before the answer is written rather than
        // described afterwards.
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final scaffold in mode.scaffolds)
              ActionChip(
                label: Text(scaffold.label),
                avatar: Icon(Icons.add_rounded, size: 14, color: accent),
                onPressed: isGrading
                    ? null
                    : () => onScaffold(scaffold.snippet),
              ),
          ],
        ),
        const SizedBox(height: Space.md),

        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 12,
          minLines: 6,
          textCapitalization: TextCapitalization.sentences,
          enabled: !isGrading,
          decoration: InputDecoration(
            hintText: mode.answerHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: Space.sm),

        // Rebuilt on every keystroke, but only this strip and the button are
        // inside the listener — the prompt above does not need to know that a
        // character was typed.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final ready =
                value.text.trim().length >= PracticeController.minAnswerLength;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WordCount(text: value.text, target: mode.targetWords),
                const SizedBox(height: Space.lg),
                FilledButton.icon(
                  onPressed: isGrading || !ready ? null : onSubmit,
                  icon: isGrading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    isGrading
                        ? 'Grading…'
                        : ready
                        ? 'Submit for grading'
                        : 'Keep going — a sentence or two',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, Sizes.buttonLg),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: Space.sm),
        Row(
          children: [
            if (task.hint case final hint? when hint.trim().isNotEmpty)
              Expanded(
                child: TextButton.icon(
                  onPressed: isGrading || hintRevealed ? null : onRevealHint,
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: Text(hintRevealed ? 'Hint shown' : 'Give me a hint'),
                ),
              ),
            Expanded(
              child: TextButton.icon(
                onPressed: isGrading ? null : onSkip,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: const Text('Skip this one'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),

        if (hintRevealed && task.hint != null) ...[
          const SizedBox(height: Space.sm),
          AppPanel(
            accent: AppPalette.warningFor(isDark: isDark),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_rounded,
                  size: 18,
                  color: AppPalette.warningFor(isDark: isDark),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(task.hint!, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Elapsed time against the length the mode is asking for.
///
/// Owns its own ticker so the one-second rebuild stays inside this widget
/// rather than repainting the prompt, the answer box and the chips every
/// second. It is a pace, not a deadline: passing the target turns the bar
/// amber and nothing else happens.
class _PacingBar extends StatefulWidget {
  const _PacingBar({super.key, required this.target, required this.running});

  final Duration target;
  final bool running;

  @override
  State<_PacingBar> createState() => _PacingBarState();
}

class _PacingBarState extends State<_PacingBar> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.running) _start();
  }

  @override
  void didUpdateWidget(_PacingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running == oldWidget.running) return;
    widget.running ? _start() : _stop();
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ratio = widget.target.inSeconds == 0
        ? 0.0
        : _elapsed.inSeconds / widget.target.inSeconds;
    final over = ratio > 1;
    final color = over
        ? AppPalette.warningFor(isDark: isDark)
        : AppPalette.accentFor(isDark: isDark);

    return Semantics(
      label: 'Time spent',
      value:
          '${_elapsed.inSeconds} seconds of '
          '${widget.target.inSeconds}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 14, color: color),
            const SizedBox(width: Space.sm),
            Text(
              '${_format(_elapsed)} / ${_format(widget.target)}',
              style: AppTypography.monoSmall(color: color),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: ClipRRect(
                borderRadius: Radii.fullAll,
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            if (over) ...[
              const SizedBox(width: Space.sm),
              Text(
                'over',
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Words written against the length a complete answer usually runs to.
class _WordCount extends StatelessWidget {
  const _WordCount({required this.text, required this.target});

  final String text;
  final int target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final reached = words >= target;

    return Row(
      children: [
        Icon(
          reached ? Icons.check_circle_rounded : Icons.short_text_rounded,
          size: 14,
          color: reached
              ? AppPalette.successFor(isDark: isDark)
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            reached
                ? '$words words — that is a full answer'
                : '$words of about $target words',
            style: theme.textTheme.bodySmall?.copyWith(
              color: reached
                  ? AppPalette.successFor(isDark: isDark)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// After grading
// ---------------------------------------------------------------------------

/// What to do with a verdict once you have read it.
///
/// The screen used to offer exactly one: next question. Answering again with
/// the ideal answer fresh is the most valuable thing available at this moment,
/// and bookmarking one you got wrong is the second, so both are here.
class _AfterActions extends ConsumerWidget {
  const _AfterActions({
    required this.task,
    required this.onNext,
    required this.onRetry,
  });

  final PracticeTask task;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = switch (task) {
      InterviewTask(:final question) => question,
      DebugTask() => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Next question'),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Answer again'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Sizes.buttonMd),
                ),
              ),
            ),
            if (question != null) ...[
              const SizedBox(width: Space.md),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final saved =
                        ref.watch(_isSavedProvider(question.id)).value ?? false;

                    return OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(questionRepositoryProvider)
                            .setSaved(question.id, saved: !saved);
                        await HapticFeedback.selectionClick();
                      },
                      icon: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 18,
                      ),
                      label: Text(saved ? 'Saved' : 'Save'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, Sizes.buttonMd),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
        if (question != null) ...[
          const SizedBox(height: Space.sm),
          TextButton.icon(
            onPressed: () => DeepDiveSheet.show(context, question),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Read the full explanation'),
          ),
        ],
      ],
    );
  }
}

class _EvaluationView extends StatelessWidget {
  const _EvaluationView({required this.evaluation, required this.answer});

  final AnswerEvaluation evaluation;
  final String answer;

  /// The verdict carries an icon as well as a colour, so "strong" and "weak"
  /// are still distinguishable without relying on green versus red.
  (Color, IconData) _band(bool isDark) => switch (evaluation.band) {
    EvaluationBand.strong => (
      AppPalette.successFor(isDark: isDark),
      Icons.verified_rounded,
    ),
    EvaluationBand.solid => (
      AppPalette.successFor(isDark: isDark),
      Icons.check_circle_rounded,
    ),
    EvaluationBand.partial => (
      AppPalette.warningFor(isDark: isDark),
      Icons.adjust_rounded,
    ),
    EvaluationBand.weak => (
      AppPalette.dangerFor(isDark: isDark),
      Icons.error_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (color, icon) = _band(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (answer.trim().isNotEmpty) ...[
          const SectionHeader('Your answer'),
          Text(
            answer.trim(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xxl),
        ],

        // Verdict.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              evaluation.overall.toStringAsFixed(1),
              style: theme.textTheme.displayMedium?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm, left: Space.xs),
              child: Text(
                '/ 10',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: StatusChip(
                label: evaluation.band.label,
                color: color,
                icon: icon,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),

        // Dimensions.
        for (final dimension in evaluation.dimensions)
          MeterRow(
            label: dimension.label,
            value: dimension.score / 10,
            color: color,
            valueLabel: dimension.score.toStringAsFixed(0),
            semanticValue: '${dimension.score.toStringAsFixed(0)} out of 10',
          ),

        const SizedBox(height: Space.sm),
        _Bullets(
          heading: 'Strengths',
          items: evaluation.strengths,
          color: AppPalette.successFor(isDark: isDark),
          icon: Icons.add_rounded,
        ),
        _Bullets(
          heading: 'Missing',
          items: evaluation.missing,
          color: AppPalette.warningFor(isDark: isDark),
          icon: Icons.remove_rounded,
        ),

        const SizedBox(height: Space.sm),
        const SectionHeader('Ideal answer'),
        AppPanel(
          child: Text(evaluation.idealAnswer, style: theme.textTheme.bodyLarge),
        ),

        if (evaluation.followUpQuestion case final followUp?) ...[
          const SizedBox(height: Space.xl),
          const SectionHeader('Follow-up'),
          Text(followUp, style: theme.textTheme.titleMedium),
        ],
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({
    required this.heading,
    required this.items,
    required this.color,
    required this.icon,
  });

  final String heading;
  final List<String> items;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(heading, color: color),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    // 3px is an optical nudge to sit the glyph on the
                    // text baseline, not a spacing value.
                    padding: const EdgeInsets.only(top: 3, right: Space.sm),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  Expanded(
                    child: Text(item, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskSkeleton extends StatelessWidget {
  const _TaskSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: Space.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeleton(width: 110, height: 12),
          SizedBox(height: Space.lg),
          AppSkeleton(width: double.infinity, height: 26),
          SizedBox(height: Space.sm),
          AppSkeleton(width: 240, height: 26),
          SizedBox(height: Space.xxl),
          AppSkeleton(
            width: double.infinity,
            height: 160,
            borderRadius: Radii.mdAll,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.reason, this.onRetry});

  final AiUnavailableReason reason;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppPanel(
      accent: AppPalette.warningFor(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reason.message, style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.sm),
          Text(
            switch (reason) {
              AiUnavailableReason.quotaExhausted =>
                'Grading needs an AI request, and TechByte runs entirely on '
                    'free quota. Your answer was not lost — try again '
                    'tomorrow, or keep reading the feed.',
              AiUnavailableReason.offline =>
                'Grading needs a connection. Your answer is still in the box, '
                    'so it will submit as soon as you are back online.',
              AiUnavailableReason.notConfigured =>
                'Grading could not authenticate with the AI service on this '
                    'build. Your answer was not lost.',
              _ => 'Grading could not run just now. Your answer was not lost.',
            },
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRetry case final retry?) ...[
            const SizedBox(height: Space.md),
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try grading again'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Sizes.buttonMd),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NothingToPractise extends StatelessWidget {
  const _NothingToPractise({
    required this.mode,
    required this.onRetry,
    this.notice,
  });

  final PracticeMode mode;
  final VoidCallback onRetry;
  final AiUnavailableReason? notice;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.fitness_center_rounded,
      title: 'Nothing to practise',
      message: notice == null
          ? 'No ${mode.label.toLowerCase()} questions are available on this '
                'device yet. Swipe through the feed for a while and they will '
                'appear here.'
          : '${notice!.message}. No ${mode.label.toLowerCase()} question '
                'could be prepared just now.',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Try again'),
      ),
    );
  }
}
