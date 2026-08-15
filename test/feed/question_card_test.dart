import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/app/theme/app_theme.dart';
import 'package:techbyte/app/theme/app_tokens.dart';
import 'package:techbyte/core/storage/app_database.dart';
import 'package:techbyte/features/feed/presentation/widgets/question_card.dart';
import 'package:techbyte/features/questions/data/question_repository.dart';
import 'package:techbyte/features/questions/domain/question.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';

const _question = Question(
  id: 'q1',
  type: QuestionType.why,
  category: Category.networking,
  subcategory: 'wifi',
  difficulty: Difficulty.medium,
  question: 'Why can Wi-Fi be slower than Ethernet on the same connection?',
  shortAnswer:
      'Because every device shares one radio channel and must wait '
      'its turn, while Ethernet gives each device its own wire.',
  whyItMatters: 'It reframes home network problems as contention problems.',
  technicalDetails: 'Wi-Fi uses CSMA/CA with random backoff.',
  source: QuestionSource.seed,
);

/// Visible height of the collapsible answer region.
double _answerHeight(WidgetTester tester) {
  return tester
      .getSize(
        find.descendant(
          of: find.byType(QuestionCard),
          matching: find.byType(SizeTransition),
        ),
      )
      .height;
}

QuestionInteraction _revealedInteraction(String id) => QuestionInteraction(
  questionId: id,
  timesSeen: 1,
  revealed: true,
  completed: true,
  skipped: false,
  saved: false,
  reviewStage: 0,
  synced: false,
);

Widget _harness({
  required QuestionWithState card,
  VoidCallback? onReveal,
  VoidCallback? onToggleSave,
  VoidCallback? onGoDeeper,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    // Animations off so the test asserts on the settled state rather than
    // racing the reveal transition. Motion now resolves from this scope rather
    // than a per-widget flag, so every animation in the subtree honours it.
    home: MotionScope(
      reducedMotion: true,
      child: Scaffold(
        body: QuestionCard(
          card: card,
          onReveal: onReveal ?? () {},
          onToggleSave: onToggleSave ?? () {},
          onGoDeeper: onGoDeeper ?? () {},
          onShare: () {},
          onReport: () {},
          showSwipeHint: true,
        ),
      ),
    ),
  );
}

void main() {
  group('QuestionCard', () {
    testWidgets('starts in the think state with the answer hidden', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(card: const QuestionWithState(question: _question)),
      );

      expect(find.text(_question.question), findsOneWidget);
      expect(find.text('Think about it…'), findsOneWidget);
      expect(find.text('Reveal answer'), findsOneWidget);

      // The answer widget stays in the tree; the SizeTransition around it is
      // what collapses to nothing. Measuring the Text would pass regardless,
      // since a clipped child still lays out at its natural size.
      expect(_answerHeight(tester), 0);
    });

    testWidgets('shows the category and subcategory label', (tester) async {
      await tester.pumpWidget(
        _harness(card: const QuestionWithState(question: _question)),
      );

      expect(find.text('NETWORKING · WIFI'), findsOneWidget);
    });

    testWidgets('reveals the answer when the card is tapped', (tester) async {
      var revealCalls = 0;
      await tester.pumpWidget(
        _harness(
          card: const QuestionWithState(question: _question),
          onReveal: () => revealCalls++,
        ),
      );

      await tester.tap(find.text(_question.question));
      await tester.pumpAndSettle();

      expect(revealCalls, 1);
      expect(find.text('Think about it…'), findsNothing);
      // Revealing drops the footer entirely and floats "Go deeper" over the
      // answer, so the strip it used to occupy is the answer's now. Found by
      // tooltip because the control is icon-only.
      expect(find.byTooltip('Go deeper'), findsOneWidget);
      expect(_answerHeight(tester), greaterThan(0));
    });

    testWidgets('reveals via the button as well as the card', (tester) async {
      var revealCalls = 0;
      await tester.pumpWidget(
        _harness(
          card: const QuestionWithState(question: _question),
          onReveal: () => revealCalls++,
        ),
      );

      await tester.tap(find.text('Reveal answer'));
      await tester.pumpAndSettle();

      expect(revealCalls, 1);
    });

    testWidgets('does not fire reveal twice', (tester) async {
      var revealCalls = 0;
      await tester.pumpWidget(
        _harness(
          card: const QuestionWithState(question: _question),
          onReveal: () => revealCalls++,
        ),
      );

      await tester.tap(find.text(_question.question));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_question.question));
      await tester.pumpAndSettle();

      expect(revealCalls, 1);
    });

    testWidgets('renders only the sections the question actually has', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(card: const QuestionWithState(question: _question)),
      );
      await tester.tap(find.text(_question.question));
      await tester.pumpAndSettle();

      expect(find.text('WHY IT MATTERS'), findsOneWidget);
      expect(find.text('TECHNICAL DETAIL'), findsOneWidget);
      // Absent on this question, so its heading must not be rendered empty.
      expect(find.text('REAL WORLD'), findsNothing);
      expect(find.text('INTERVIEW ANGLE'), findsNothing);
    });

    testWidgets('opens already revealed when the question was seen before', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          card: QuestionWithState(
            question: _question,
            interaction: _revealedInteraction(_question.id),
          ),
        ),
      );

      expect(find.text('Think about it…'), findsNothing);
      expect(_answerHeight(tester), greaterThan(0));
    });

    testWidgets('bookmark reflects saved state and reports taps', (
      tester,
    ) async {
      var saveCalls = 0;
      await tester.pumpWidget(
        _harness(
          card: const QuestionWithState(question: _question),
          onToggleSave: () => saveCalls++,
        ),
      );

      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      expect(saveCalls, 1);
    });
  });
}
