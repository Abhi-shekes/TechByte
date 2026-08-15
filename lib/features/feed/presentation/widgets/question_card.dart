import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/ui/ui.dart';
import '../../../questions/data/question_repository.dart';
import '../../../questions/domain/question.dart';

/// One full-screen card in the feed.
///
/// Two states: "think", showing only the question, and "revealed", showing the
/// answer and its supporting sections. The gap between them is the whole
/// product — the card deliberately withholds the answer until asked.
class QuestionCard extends StatefulWidget {
  const QuestionCard({
    super.key,
    required this.card,
    required this.onReveal,
    required this.onToggleSave,
    required this.onGoDeeper,
    required this.onShare,
    required this.onReport,
    this.hapticsEnabled = true,
    this.showSwipeHint = false,
    this.header,
  });

  final QuestionWithState card;
  final VoidCallback onReveal;
  final VoidCallback onToggleSave;
  final VoidCallback onGoDeeper;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final bool hapticsEnabled;

  /// Only the first few cards of a session teach the swipe. After that the
  /// hint is noise on every screen.
  final bool showSwipeHint;

  /// Sits between the category mark and the question — currently the daily
  /// progress strip. Injected rather than built here so this stays a pure
  /// presentational widget with no provider dependency of its own.
  final Widget? header;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Local rather than derived from the interaction row, so the reveal
  /// animation starts on the same frame as the tap instead of waiting for a
  /// database round trip.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _revealed = widget.card.interaction?.revealed ?? false;
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.reveal,
      value: _revealed ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here rather than in initState because it depends on inherited
    // widgets. Covers both the app preference and the platform switch.
    _controller.duration = Motion.reveal(context);
  }

  @override
  void didUpdateWidget(covariant QuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different question reused this element: reset to the think state.
    if (oldWidget.card.question.id != widget.card.question.id) {
      _revealed = widget.card.interaction?.revealed ?? false;
      _controller.value = _revealed ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_revealed) return;
    if (widget.hapticsEnabled) HapticFeedback.selectionClick();
    setState(() => _revealed = true);
    _controller.forward();
    widget.onReveal();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final question = widget.card.question;
    final accent = AppPalette.forCategory(question.category.id, isDark: isDark);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutterReading,
            Space.sm,
            Space.gutterReading,
            Space.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                question: question,
                accent: accent,
                isSaved: widget.card.isSaved,
                onToggleSave: widget.onToggleSave,
                onShare: widget.onShare,
                onReport: widget.onReport,
                revealProgress: _controller,
              ),
              // In the layout rather than floating over it. As a free
              // `Positioned` overlay this could collide with a long question
              // on a short screen.
              if (widget.header case final header?)
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: header,
                ),
              Expanded(
                // The answer and the one action that belongs to it share this
                // space rather than queueing for it. A row of buttons pinned
                // under the scroll view cost ~90px of every card — on the one
                // screen where vertical room is the scarcest thing there is,
                // and where the answer is the entire product.
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      physics: _revealed
                          ? const ClampingScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const SizedBox(height: Space.xxl),
                      Text(
                        question.question,
                        // Sized to the question rather than fixed at 34px.
                        // A one-line "What is DNS?" wants to be big; a
                        // 140-character question at the same size filled a
                        // small phone on its own and pushed the reveal button
                        // to the edge of the screen.
                        style: _questionStyle(theme, question.question),
                      ),
                      const SizedBox(height: Space.xl),
                      // Both states occupy the same slot; the answer expands
                      // from zero height so the question never jumps.
                      SizeTransition(
                        sizeFactor: CurvedAnimation(
                          parent: _controller,
                          curve: AppCurves.emphasized,
                        ),
                        axisAlignment: -1,
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _controller,
                            curve: const Interval(
                              0.25,
                              1,
                              curve: AppCurves.standard,
                            ),
                          ),
                          child: _AnswerBody(question: question),
                        ),
                      ),
                          // The swipe hint moved into the scroll rather than
                          // under it: it belongs at the point you finish
                          // reading, and inline it costs nothing on the cards
                          // that have stopped needing it.
                          if (_revealed && widget.showSwipeHint) ...[
                            const SizedBox(height: Space.xxl),
                            Center(
                              child: Text(
                                'Swipe up for the next question',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          // Clears the floating action, so the last line of an
                          // answer can always be scrolled out from under it.
                          const SizedBox(height: Space.colossal),
                        ],
                      ),
                    ),

                    // Fades in with the answer it belongs to, and only then —
                    // there is nothing to go deeper into while the question is
                    // still unanswered.
                    Positioned(
                      right: 0,
                      bottom: Space.sm,
                      child: FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _controller,
                          curve: const Interval(
                            0.5,
                            1,
                            curve: AppCurves.standard,
                          ),
                        ),
                        child: IgnorePointer(
                          ignoring: !_revealed,
                          child: _GoDeeper(
                            accent: accent,
                            onTap: widget.onGoDeeper,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_revealed) _ThinkFooter(accent: accent, onReveal: _reveal),
            ],
          ),
        ),
      ),
    );
  }

  /// Steps the display size down as the question gets longer.
  static TextStyle? _questionStyle(ThemeData theme, String question) =>
      switch (question.characters.length) {
        > 110 => theme.textTheme.displaySmall,
        > 64 => theme.textTheme.displayMedium,
        _ => theme.textTheme.displayLarge,
      };
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.question,
    required this.accent,
    required this.isSaved,
    required this.onToggleSave,
    required this.onShare,
    required this.onReport,
    required this.revealProgress,
  });

  final Question question;
  final Color accent;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final Animation<double> revealProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = question.subcategory == null
        ? question.category.label
        : '${question.category.label} · ${question.subcategory}';

    return Row(
      children: [
        Expanded(
          // The mark brightens as the answer expands, so the causal link
          // between the tap and the reveal is visible at the top of the screen
          // too — not only in the body that is growing below the fold.
          child: AnimatedBuilder(
            animation: revealProgress,
            builder: (context, child) {
              final lifted = Color.lerp(
                accent.withValues(alpha: 0.72),
                accent,
                revealProgress.value,
              )!;
              return CategoryMark(label: label, color: lifted);
            },
          ),
        ),
        IconButton(
          onPressed: onToggleSave,
          icon: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: isSaved ? accent : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: isSaved ? 'Remove bookmark' : 'Save question',
        ),
        PopupMenuButton<String>(
          icon: Icon(
            Icons.more_horiz_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: 'More',
          onSelected: (value) => switch (value) {
            'share' => onShare(),
            'report' => onReport(),
            _ => null,
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'report', child: Text('Report a problem')),
          ],
        ),
      ],
    );
  }
}

class _AnswerBody extends StatelessWidget {
  const _AnswerBody({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppPalette.forCategory(
      question.category.id,
      isDark: theme.brightness == Brightness.dark,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Short answer', color: accent),
        Text(question.shortAnswer, style: theme.textTheme.bodyLarge),
        for (final section in question.detailSections) ...[
          const SizedBox(height: Space.xxl),
          SectionHeader(section.heading),
          // Technical detail reads as reference material, so it gets the
          // monospace treatment to visually separate it from the prose above.
          if (section.heading == 'Technical detail')
            AppPanel(child: MonoText(section.body))
          else
            Text(section.body, style: theme.textTheme.bodyMedium),
        ],
        // "Go deeper" used to live here, at the very bottom of a scroll that
        // can run several screens long. It moved to the persistent footer,
        // where it is reachable without scrolling to find it.
        if (question.followUpQuestion case final followUp?) ...[
          const SizedBox(height: Space.xxl),
          Text(
            followUp,
            style: theme.textTheme.titleMedium?.copyWith(color: accent),
          ),
        ],
      ],
    );
  }
}

class _ThinkFooter extends StatelessWidget {
  const _ThinkFooter({required this.accent, required this.onReveal});

  final Color accent;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Think about it…',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Space.md),
        FilledButton(
          onPressed: onReveal,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: AppPalette.onAccentFor(isDark: isDark),
          ),
          child: const Text('Reveal answer'),
        ),
      ],
    );
  }
}

/// "Go deeper", floating over the answer.
///
/// The strip under the scroll view previously held this, a share button and a
/// next button — roughly 90px of permanent chrome on the screen with the least
/// room to spare, where the answer itself is the product. Share already lives
/// in the card's overflow menu and "next" is the swipe the whole feed is built
/// on, so neither needed a second home. Only this one had nowhere else to be.
///
/// Floating rather than inline is what buys the space back: the answer scrolls
/// underneath it and past it, so the action costs no layout at all.
class _GoDeeper extends StatelessWidget {
  const _GoDeeper({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  static const _size = Sizes.touchTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Go deeper',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Go deeper',
          child: Material(
            // Opaque, with a shadow: it sits over live text, and a translucent
            // control would leave words legible through the one thing on
            // screen that has to stay tappable.
            color: theme.colorScheme.surfaceContainer,
            shape: CircleBorder(
              side: BorderSide(color: accent.withValues(alpha: 0.45)),
            ),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: _size,
                height: _size,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
