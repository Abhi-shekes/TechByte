import '../../questions/domain/question_enums.dart';

/// A production incident to reason about.
///
/// The metrics matter as much as the prose: a good scenario gives numbers that
/// *rule things out*. "CPU 25%, memory 45%" is what makes "just scale up" the
/// wrong answer, and that tension is the whole exercise.
class DebugScenario {
  const DebugScenario({
    required this.id,
    required this.title,
    required this.situation,
    required this.metrics,
    required this.prompt,
    required this.category,
    this.difficulty = Difficulty.hard,
  });

  final String id;
  final String title;

  /// What is happening, in a few sentences.
  final String situation;

  /// Observed signals, label → value. Rendered as a monospace block.
  final List<({String label, String value})> metrics;

  /// What the user is asked to do — usually "what do you investigate first?".
  final String prompt;

  final Category category;
  final Difficulty difficulty;

  factory DebugScenario.fromJson(Map<String, dynamic> json, {String? id}) {
    final metrics = switch (json['metrics']) {
      final List<dynamic> l =>
        l
            .whereType<Map<String, dynamic>>()
            .map(
              (m) => (
                label: (m['label'] as String?)?.trim() ?? '',
                value: (m['value'] as String?)?.trim() ?? '',
              ),
            )
            .where((m) => m.label.isNotEmpty && m.value.isNotEmpty)
            .toList(growable: false),
      _ => const <({String label, String value})>[],
    };

    return DebugScenario(
      id: id ?? (json['id'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? '',
      situation: (json['situation'] as String?)?.trim() ?? '',
      metrics: metrics,
      prompt:
          (json['prompt'] as String?)?.trim() ??
          'What would you investigate first, and why?',
      category: Category.fromId((json['category'] as String?)?.trim() ?? ''),
      difficulty: Difficulty.fromId(
        (json['difficulty'] as String?)?.trim() ?? '',
      ),
    );
  }

  /// A scenario without metrics is just a question with extra words, so it is
  /// rejected rather than shown.
  bool get isUsable =>
      situation.length >= 40 && metrics.isNotEmpty && title.isNotEmpty;
}

/// Bundled scenarios, so Practice works offline and before any AI request.
///
/// Same rationale as the seed questions: the mode must be usable on first
/// launch, and these define the shape generated scenarios are prompted to match.
abstract final class SeedDebugScenarios {
  static List<DebugScenario> all() => const [
    DebugScenario(
      id: 'dbg_api_latency',
      title: 'API latency jumped 40×',
      situation:
          'A REST endpoint that normally responds in 100 ms is taking 4 '
          'seconds. It started 20 minutes ago, there was no deploy, and '
          'traffic is at its usual level for this hour.',
      metrics: [
        (label: 'p50 latency', value: '4.1 s (was 100 ms)'),
        (label: 'App CPU', value: '25%'),
        (label: 'App memory', value: '45%'),
        (label: 'Database CPU', value: '30%'),
        (label: 'Error rate', value: '0.2% (normal)'),
        (label: 'Requests/sec', value: 'unchanged'),
      ],
      prompt: 'What do you investigate first, and why?',
      category: Category.backend,
    ),
    DebugScenario(
      id: 'dbg_kafka_lag',
      title: 'Consumer lag climbing steadily',
      situation:
          'A Kafka consumer group has been falling behind for the last hour. '
          'Lag grows by roughly 5,000 messages a minute. The consumers are '
          'running and not throwing errors.',
      metrics: [
        (label: 'Consumer lag', value: '310,000 and rising'),
        (label: 'Consumer CPU', value: '15%'),
        (label: 'Partitions', value: '12'),
        (label: 'Active consumers', value: '12'),
        (label: 'Rebalances (1h)', value: '47'),
        (label: 'Producer rate', value: 'unchanged'),
      ],
      prompt: 'What is the most likely cause, and what would you check?',
      category: Category.distributedSystems,
    ),
    DebugScenario(
      id: 'dbg_memory_leak',
      title: 'Pods restarting every few hours',
      situation:
          'A service restarts roughly every four hours. Memory climbs steadily '
          'from deploy until the restart, then the cycle repeats. No errors '
          'appear in the application logs before it goes.',
      metrics: [
        (label: 'Memory at start', value: '180 MB'),
        (label: 'Memory before restart', value: '1.9 GB'),
        (label: 'Memory limit', value: '2 GB'),
        (label: 'Exit code', value: '137'),
        (label: 'CPU', value: '20% steady'),
        (label: 'Request rate', value: 'flat'),
      ],
      prompt: 'What does this pattern tell you, and how would you confirm it?',
      category: Category.devops,
    ),
    DebugScenario(
      id: 'dbg_intermittent_500',
      title: 'Intermittent 500s after scaling up',
      situation:
          'After scaling from 4 replicas to 20 to handle a traffic spike, the '
          'error rate went up rather than down. Roughly one request in twelve '
          'returns a 500. Scaling back down makes it stop.',
      metrics: [
        (label: 'Replicas', value: '20 (was 4)'),
        (label: 'Error rate', value: '8%'),
        (label: 'App CPU', value: '12%'),
        (label: 'Database CPU', value: '95%'),
        (label: 'DB connections', value: '400 / 400'),
        (label: 'Errors', value: 'connection timeout'),
      ],
      prompt: 'Why did adding capacity make things worse?',
      category: Category.databases,
    ),
  ];
}
