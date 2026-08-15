import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/app/theme/app_theme.dart';
import 'package:techbyte/app/theme/app_tokens.dart';
import 'package:techbyte/app/ui/ui.dart';
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

Widget _wrap(Widget child, {bool reducedMotion = false, double scale = 1.0}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MotionScope(
        reducedMotion: reducedMotion,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('touch targets', () {
    testWidgets('feed card icon buttons clear the WCAG minimum', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          QuestionCard(
            card: const QuestionWithState(question: _question),
            onReveal: () {},
            onToggleSave: () {},
            onGoDeeper: () {},
            onShare: () {},
            onReport: () {},
          ),
        ),
      );

      // These previously used `visualDensity: compact`, which shrank them below
      // the minimum at the top corner of the screen — the hardest place to hit.
      for (final element in find.byType(IconButton).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(
          size.height,
          greaterThanOrEqualTo(Sizes.touchTarget),
          reason: 'an IconButton is only ${size.height}px tall',
        );
        expect(size.width, greaterThanOrEqualTo(Sizes.touchTarget));
      }
    });
  });

  group('reduced motion', () {
    testWidgets('collapses every duration to zero', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
          reducedMotion: true,
        ),
      );

      expect(Motion.fast(captured), Duration.zero);
      expect(Motion.base(captured), Duration.zero);
      expect(Motion.reveal(captured), Duration.zero);
      expect(Motion.of(captured, AppDurations.slow), Duration.zero);
    });

    testWidgets('leaves durations intact when not requested', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(Motion.reveal(captured), AppDurations.reveal);
      expect(Motion.base(captured), AppDurations.base);
    });

    testWidgets('the reveal settles instantly when motion is reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          QuestionCard(
            card: const QuestionWithState(question: _question),
            onReveal: () {},
            onToggleSave: () {},
            onGoDeeper: () {},
            onShare: () {},
            onReport: () {},
          ),
          reducedMotion: true,
        ),
      );

      await tester.tap(find.text(_question.question));
      // One frame, not a settle: with motion reduced there is nothing to wait
      // for, so the answer must already be at full height.
      await tester.pump();

      final height = tester
          .getSize(
            find.descendant(
              of: find.byType(QuestionCard),
              matching: find.byType(SizeTransition),
            ),
          )
          .height;
      expect(height, greaterThan(0));
    });
  });

  group('large text', () {
    testWidgets('the feed card lays out at the maximum supported scale', (
      tester,
    ) async {
      // 1.6 is the ceiling the app clamps the platform scale to.
      await tester.pumpWidget(
        _wrap(
          QuestionCard(
            card: const QuestionWithState(question: _question),
            onReveal: () {},
            onToggleSave: () {},
            onGoDeeper: () {},
            onShare: () {},
            onReport: () {},
          ),
          scale: 1.6,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('shared state components lay out at the maximum scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AppEmptyState(
            icon: Icons.inbox_rounded,
            title: 'Nothing left to ask',
            message:
                'You have seen everything stored on this device. New '
                'questions arrive when you are online.',
          ),
          scale: 1.6,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('meter rows announce a value', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const MeterRow(
            label: 'Networking',
            value: 0.72,
            color: Colors.blue,
            valueLabel: '72%',
            semanticValue: '72 percent familiar',
          ),
        ),
      );

      // Previously every progress bar in the app was silent to a screen
      // reader: it exposed neither a label nor a value.
      final node = tester.getSemantics(find.byType(MeterRow));
      expect(node.label, contains('Networking'));
      expect(node.value, '72 percent familiar');

      handle.dispose();
    });
  });
}
