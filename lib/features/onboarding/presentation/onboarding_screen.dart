import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/providers/core_providers.dart';
import '../../feed/application/daily_session_controller.dart';
import '../../questions/domain/question_enums.dart';

/// Three quick choices: topics, level, goal.
///
/// Every one is skippable and changeable later. Onboarding shapes the feed but
/// must never be a gate — the defaults produce a perfectly good feed on their
/// own, so there is no reason to make someone answer before they see value.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  final _topics = <Category>{};
  ExperienceLevel _level = ExperienceLevel.intermediate;
  LearningGoal _goal = LearningGoal.all;

  /// The subset offered up front. The full taxonomy is available in Explore;
  /// showing all eighteen here would make the first screen feel like paperwork.
  static const _offeredTopics = <Category>[
    Category.programming,
    Category.aiMl,
    Category.hardware,
    Category.networking,
    Category.cybersecurity,
    Category.cloud,
    Category.databases,
    Category.mobile,
    Category.operatingSystems,
    Category.electronics,
  ];

  Future<void> _finish() async {
    await ref
        .read(userPreferencesProvider.notifier)
        .update(
          (p) => p.copyWith(
            topics: _topics,
            level: _level,
            goal: _goal,
            onboardingComplete: true,
          ),
        );
    unawaited(ref.read(analyticsServiceProvider).onboardingCompleted());
  }

  void _next() {
    if (_page == 2) {
      _finish();
      return;
    }
    // Previously a hardcoded 280ms that ignored the motion preference
    // entirely, so switching Reduce motion on stopped the reveal animation and
    // left this one running.
    final duration = Motion.base(context);
    if (duration == Duration.zero) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(duration: duration, curve: AppCurves.standard);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutterReading,
                Space.md,
                Space.md,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Onboarding progress',
                      value: 'Step ${_page + 1} of 3',
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: Radii.fullAll,
                          child: LinearProgressIndicator(
                            value: (_page + 1) / 3,
                            minHeight: 4,
                            backgroundColor: theme.colorScheme.surfaceContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Step(
                    title: 'What are you curious about?',
                    subtitle:
                        'Pick a few, or none at all — leaving this empty means '
                        'everything is fair game.',
                    child: Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final topic in _offeredTopics)
                          FilterChip(
                            label: Text(topic.label),
                            // The first time the user meets the category
                            // colour language, which every later screen relies
                            // on to identify a topic at a glance.
                            avatar: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppPalette.forCategory(
                                  topic.id,
                                  isDark: theme.brightness == Brightness.dark,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            selected: _topics.contains(topic),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _topics.add(topic);
                              } else {
                                _topics.remove(topic);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  _Step(
                    title: 'How deep should we go?',
                    subtitle:
                        'This sets the usual difficulty. You will still meet '
                        'the occasional stretch question.',
                    child: RadioGroup<ExperienceLevel>(
                      groupValue: _level,
                      onChanged: (value) =>
                          setState(() => _level = value ?? _level),
                      child: Column(
                        children: [
                          for (final level in ExperienceLevel.values)
                            RadioListTile<ExperienceLevel>(
                              contentPadding: EdgeInsets.zero,
                              value: level,
                              title: Text(level.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _Step(
                    title: 'What brings you here?',
                    subtitle:
                        'Shapes how often interview-style questions show up.',
                    child: RadioGroup<LearningGoal>(
                      groupValue: _goal,
                      onChanged: (value) =>
                          setState(() => _goal = value ?? _goal),
                      child: Column(
                        children: [
                          for (final goal in LearningGoal.values)
                            RadioListTile<LearningGoal>(
                              contentPadding: EdgeInsets.zero,
                              value: goal,
                              title: Text(goal.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutterReading,
                Space.sm,
                Space.gutterReading,
                Space.xl,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_page == 2 ? 'Start swiping' : 'Continue'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutterReading,
        Space.xxxl,
        Space.gutterReading,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.displayMedium),
          const SizedBox(height: Space.md),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xxxl),
          child,
        ],
      ),
    );
  }
}
