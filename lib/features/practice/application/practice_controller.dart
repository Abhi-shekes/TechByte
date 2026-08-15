import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../feed/application/daily_session_controller.dart';
import '../../../services/ai/ai_result.dart';
import '../../questions/domain/question.dart';
import '../domain/answer_evaluation.dart';
import '../domain/debug_scenario.dart';
import '../domain/practice_mode.dart';

/// Number of questions currently due for review, for the Practice tab badge.
final dueForReviewCountProvider = FutureProvider<int>((ref) async {
  final due = await ref.watch(questionRepositoryProvider).dueForReview();
  return due.length;
});

/// What the user is being asked in the current session.
///
/// Interview draws a real question from the pool; debugging poses a scenario.
/// They are separate types because the *prompt* differs structurally — a
/// scenario has metrics to reason over, a question does not.
sealed class PracticeTask {
  const PracticeTask();

  String get promptText;
  String get referenceAnswer;

  /// Id used for review scheduling. Null for generated scenarios, which are
  /// not stored in `question_rows` and so cannot carry a review schedule.
  String? get scheduleId;

  /// A nudge, available before answering.
  ///
  /// Built entirely from content already on the device — never a second AI
  /// request. Being stuck is exactly the moment the daily budget should not be
  /// spent twice on one question, and it means the hint works offline.
  String? get hint;

  /// Chip text describing where the task came from.
  String get sourceLabel;

  /// Roughly how long a good answer runs. Drives the on-screen pacing bar.
  Duration get targetDuration;
}

final class InterviewTask extends PracticeTask {
  const InterviewTask(this.question);

  final Question question;

  @override
  String get promptText => question.question;

  @override
  String get referenceAnswer => [
    question.shortAnswer,
    if (question.technicalDetails case final t?) t,
    if (question.interviewAngle case final a?) 'Interviewer looks for: $a',
  ].join('\n\n');

  @override
  String? get scheduleId => question.id;

  @override
  String? get hint => question.interviewAngle ?? question.whyItMatters;

  @override
  String get sourceLabel => question.category.label;

  /// The 60–90 seconds the mode's own instruction asks for, at the top of the
  /// range: the pacing bar should not turn amber on someone who is answering
  /// exactly as told.
  @override
  Duration get targetDuration => const Duration(seconds: 90);
}

final class DebugTask extends PracticeTask {
  const DebugTask(this.scenario);

  final DebugScenario scenario;

  @override
  String get promptText => '${scenario.situation}\n\n${scenario.prompt}';

  /// Seed scenarios ship without a written answer on purpose — the grader is
  /// told to reason from the metrics rather than match a canned solution,
  /// which is also what keeps generated scenarios gradeable.
  @override
  String get referenceAnswer =>
      'No reference answer is provided. Judge the response on whether its '
      'reasoning is consistent with these observations:\n'
      '${scenario.metrics.map((m) => '- ${m.label}: ${m.value}').join('\n')}';

  @override
  String? get scheduleId => null;

  /// Points at the method rather than the answer. A scenario is built so that
  /// the *unremarkable* numbers are the informative ones — a normal CPU is
  /// what makes "scale it up" wrong — and noticing that is the skill being
  /// practised, so the hint names the technique and stops.
  @override
  String? get hint =>
      'Read the numbers that look normal, not just the alarming one. Each '
      'healthy signal rules a cause out, and your answer has to be consistent '
      'with all ${scenario.metrics.length} of them.';

  @override
  String get sourceLabel => scenario.category.label;

  /// Longer than an interview answer: an incident answer has to walk through
  /// hypotheses before it concludes.
  @override
  Duration get targetDuration => const Duration(seconds: 150);
}

@immutable
class PracticeState {
  const PracticeState({
    required this.mode,
    this.task,
    this.evaluation,
    this.isLoading = false,
    this.isGrading = false,
    this.notice,
    this.scores = const <double>[],
    this.skipped = 0,
  });

  final PracticeMode mode;
  final PracticeTask? task;

  /// Set once an answer has been graded.
  final AnswerEvaluation? evaluation;

  /// True while the next task is being fetched or generated.
  final bool isLoading;

  final bool isGrading;

  /// Why grading or loading could not proceed.
  final AiUnavailableReason? notice;

  /// Every score awarded this session, in order.
  ///
  /// Kept as the list rather than a running count because the session strip
  /// shows the shape of the run — three scores climbing 4, 6, 8 is the thing
  /// worth seeing, and a single "3 done" counter threw it away.
  final List<double> scores;

  /// Questions passed on without answering. Not a score, and deliberately not
  /// mixed into one.
  final int skipped;

  bool get hasTask => task != null;

  int get completed => scores.length;

  double? get averageScore =>
      scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;

  double? get bestScore => scores.isEmpty ? null : scores.reduce(max);

  PracticeState copyWith({
    PracticeMode? mode,
    PracticeTask? task,
    AnswerEvaluation? evaluation,
    bool? isLoading,
    bool? isGrading,
    AiUnavailableReason? notice,
    List<double>? scores,
    int? skipped,
    bool clearEvaluation = false,
    bool clearNotice = false,
  }) {
    return PracticeState(
      mode: mode ?? this.mode,
      task: task ?? this.task,
      evaluation: clearEvaluation ? null : (evaluation ?? this.evaluation),
      isLoading: isLoading ?? this.isLoading,
      isGrading: isGrading ?? this.isGrading,
      notice: clearNotice ? null : (notice ?? this.notice),
      scores: scores ?? this.scores,
      skipped: skipped ?? this.skipped,
    );
  }
}

final practiceControllerProvider =
    NotifierProvider<PracticeController, PracticeState>(PracticeController.new);

/// Drives one practice session.
///
/// A plain [Notifier] rather than an AsyncNotifier family: only one session
/// runs at a time, and every transition here is user-initiated (start, submit,
/// next), so modelling it as a state machine the screen drives is clearer than
/// threading an AsyncValue through three different loading conditions.
///
/// Unlike the feed, latency is acceptable here — the user has just spent a
/// minute writing an answer and expects grading to take a moment. So this
/// awaits its AI calls rather than dispatching them, and shows real progress.
class PracticeController extends Notifier<PracticeState> {
  final _random = Random();

  @override
  PracticeState build() =>
      const PracticeState(mode: PracticeMode.interview, isLoading: true);

  /// Begins a session in [mode]. Safe to call again to restart.
  Future<void> start(PracticeMode mode) async {
    state = PracticeState(mode: mode, isLoading: true);
    unawaited(ref.read(analyticsServiceProvider).practiceStarted(mode));
    await _loadNextTask();
  }

  Future<void> _loadNextTask() async {
    final current = state;
    try {
      final next = switch (current.mode) {
        PracticeMode.interview => await _nextInterviewTask(current),
        PracticeMode.debugging => await _nextDebugTask(current),
      };
      state = next.copyWith(isLoading: false);
    } catch (error, stack) {
      // `isLoading` is only ever cleared here, so anything thrown on this path
      // left the screen on its skeleton for the rest of the session — no
      // error, no retry, nothing to tap. Whatever went wrong, the loading
      // state has to end.
      debugPrint('Practice task failed to load: $error\n$stack');
      state = current.copyWith(
        isLoading: false,
        notice: AiUnavailableReason.unknown,
      );
    }
  }

  Future<PracticeState> _nextInterviewTask(PracticeState current) async {
    final repo = ref.read(questionRepositoryProvider);
    await repo.ensureSeeded();

    final pool = await repo.candidates(limit: 400);
    final eligible = pool
        .where((c) => current.mode.sourceTypes.contains(c.question.type))
        .toList(growable: false);

    // Anything with an interview angle is still a fair interview question even
    // if its type is not one of the interview-shaped ones, so it is a better
    // fallback than showing nothing.
    final candidates = eligible.isNotEmpty
        ? eligible
        : pool
              .where((c) => c.question.interviewAngle != null)
              .toList(growable: false);

    if (candidates.isEmpty) {
      return current.copyWith(notice: AiUnavailableReason.unknown);
    }

    final pick = candidates[_random.nextInt(candidates.length)];
    return current.copyWith(
      task: InterviewTask(pick.question),
      clearEvaluation: true,
      clearNotice: true,
    );
  }

  Future<PracticeState> _nextDebugTask(PracticeState current) async {
    final seeds = SeedDebugScenarios.all();
    final prefs = ref.read(userPreferencesProvider);

    // Try to generate a fresh scenario, but never depend on it: the bundled
    // set is a complete experience on its own, which is what keeps this mode
    // working offline and after the daily AI budget is spent.
    if (prefs.aiGenerationEnabled) {
      try {
        final result = await ref
            .read(geminiServiceProvider)
            .generateDebugScenario(
              categories: prefs.topics.toList(growable: false),
              avoidTitles: seeds.map((s) => s.title).toList(growable: false),
            );

        if (result case AiSuccess(:final value)) {
          return current.copyWith(
            task: DebugTask(value),
            clearEvaluation: true,
            clearNotice: true,
          );
        }
      } catch (error) {
        // "Never depend on it" has to include not throwing. A generation
        // failure must cost the user a bundled scenario instead of the mode.
        debugPrint('Debug scenario generation failed: $error');
      }
    }

    final pick = seeds[_random.nextInt(seeds.length)];
    return current.copyWith(
      task: DebugTask(pick),
      clearEvaluation: true,
      clearNotice: true,
    );
  }

  /// The shortest answer worth spending an AI request on.
  ///
  /// Two characters let "no" through, which burned a request from a finite
  /// daily budget to be told it was wrong. A real answer to either mode is a
  /// sentence.
  static const minAnswerLength = 20;

  /// Grades the user's answer and schedules a review from the result.
  Future<void> submit(String answer) async {
    final task = state.task;
    if (task == null || state.isGrading) return;
    if (answer.trim().length < minAnswerLength) return;

    state = state.copyWith(isGrading: true, clearNotice: true);

    try {
      final result = await ref
          .read(geminiServiceProvider)
          .evaluateAnswer(
            mode: state.mode,
            question: task.promptText,
            referenceAnswer: task.referenceAnswer,
            userAnswer: answer.trim(),
          );

      switch (result) {
        case AiSuccess(:final value):
          // Only a graded answer moves the review schedule. Revealing an
          // answer in the feed is not evidence you knew it; this is.
          if (task.scheduleId case final id?) {
            await ref
                .read(questionRepositoryProvider)
                .recordAnswer(id, correct: value.isPass);
            ref.invalidate(dueForReviewCountProvider);
          }
          unawaited(
            ref
                .read(analyticsServiceProvider)
                .practiceCompleted(
                  state.mode,
                  score: value.overall,
                  passed: value.isPass,
                ),
          );
          state = state.copyWith(
            evaluation: value,
            isGrading: false,
            scores: [...state.scores, value.overall],
          );
        case AiUnavailable(:final reason):
          unawaited(
            ref.read(analyticsServiceProvider).generationUnavailable(reason),
          );
          state = state.copyWith(isGrading: false, notice: reason);
      }
    } catch (error, stack) {
      // Same reasoning as `_loadNextTask`: the only thing that clears
      // `isGrading` is this method, so a throw left the Submit button spinning
      // on "Grading…" with the answer stuck behind it.
      debugPrint('Grading failed: $error\n$stack');
      state = state.copyWith(
        isGrading: false,
        notice: AiUnavailableReason.unknown,
      );
    }
  }

  /// Moves to the next task, keeping the session count.
  Future<void> next() async {
    state = state.copyWith(
      isLoading: true,
      clearEvaluation: true,
      clearNotice: true,
    );
    await _loadNextTask();
  }

  /// Moves on without answering.
  ///
  /// Separate from [next] so the session strip can distinguish "I passed on
  /// four of these" from "I answered four", and so skipping never touches the
  /// review schedule.
  Future<void> skip() async {
    if (state.isGrading) return;
    state = state.copyWith(
      isLoading: true,
      skipped: state.skipped + 1,
      clearEvaluation: true,
      clearNotice: true,
    );
    await _loadNextTask();
  }

  /// Clears the verdict so the same question can be answered again.
  ///
  /// Costs another AI request, which is why it is an explicit action rather
  /// than something the Next button does. Re-answering a question you have
  /// just seen the ideal answer to is the single most useful thing available
  /// here, and there was previously no way to do it.
  void retry() {
    if (state.isGrading) return;
    state = state.copyWith(clearEvaluation: true, clearNotice: true);
  }
}
