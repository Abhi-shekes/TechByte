import '../../../features/practice/domain/practice_mode.dart';
import '../../../features/questions/domain/question_enums.dart';

/// The alternate framings offered by "Explain differently".
enum ExplanationStyle {
  simple('simple', 'Explain simply'),
  likeImTen('eli10', "Explain like I'm 10"),
  analogy('analogy', 'Give an analogy'),
  realWorld('real_world', 'Real-world example'),
  technical('technical', 'Technical explanation'),
  interview('interview', 'Interview explanation');

  const ExplanationStyle(this.id, this.label);

  final String id;
  final String label;
}

/// Every prompt the app sends, in one place.
///
/// Centralised for three reasons: prompts are the main quality lever and need
/// to be reviewable as a set; they must stay consistent with the seed content
/// that defines the voice; and keeping them out of the service makes both
/// testable in isolation.
abstract final class PromptLibrary {
  /// System instruction applied to every request.
  ///
  /// This carries the editorial rule from the product spec. The single most
  /// important line is the ban on definition questions — without it, models
  /// reliably drift toward "What is X?", which is exactly the content this
  /// product exists to avoid.
  static const systemInstruction = '''
You write for TechByte, a short-form technical curiosity app for engineers and technically curious people.

VOICE
- Precise, calm, and concrete. No hype, no exclamation marks, no emoji.
- Never address the reader as "folks", never open with "Ever wondered".
- Assume intelligence. Explain the mechanism, not the vocabulary.

THE ONE RULE
Every question must make a technically curious person genuinely want the answer before they get it.

- BANNED: definition questions. Never "What is RAM?", "What is DNS?", "Explain TCP".
- REQUIRED: questions about mechanism, consequence, surprise or contradiction.

Weak:   What is a CPU cache?
Strong: Why doesn't the CPU simply read RAM every time it needs data?

Weak:   What is DNS?
Strong: If every DNS server went offline for an hour, what would break first?

ACCURACY
- Only state things that are actually true. Prefer omitting a detail to guessing one.
- No invented benchmarks, dates, version numbers or company-specific claims.
- Approximate figures must be clearly approximate ("roughly 200 cycles").

LENGTH
- The short answer must be understandable in under 30 seconds.
- Each supporting section is 1-3 sentences. Never pad to fill a field.
''';

  /// Prompt for a batch of new questions.
  ///
  /// [avoidQuestions] carries the text of questions already in the local pool.
  /// Passing them is what keeps a long feed from circling the same handful of
  /// ideas — the duplicate validator is the backstop, not the primary defence,
  /// because a rejected question has already cost quota.
  static String questionGeneration({
    required int count,
    required List<Category> categories,
    required ExperienceLevel level,
    required LearningGoal goal,
    required List<String> avoidQuestions,
  }) {
    final categoryList = categories.isEmpty
        ? Category.values.map((c) => '${c.id} (${c.label})').join(', ')
        : categories.map((c) => '${c.id} (${c.label})').join(', ');

    final difficulties = level.preferredDifficulties
        .map((d) => d.id)
        .join(' or ');

    final avoidBlock = avoidQuestions.isEmpty
        ? 'No questions have been shown yet.'
        : avoidQuestions.take(120).map((q) => '- $q').join('\n');

    return '''
Write $count new TechByte questions.

CATEGORIES — use only these ids, and spread the batch across several of them:
$categoryList

DIFFICULTY: mostly $difficulties.
READER GOAL: ${goal.label}.

MIX OF TYPES — vary these across the batch, do not use the same type twice in a row:
${QuestionType.values.map((t) => '${t.id} (${t.label})').join(', ')}

ALREADY USED — do not repeat these questions, restate them in different words, or cover the same underlying mechanism:
$avoidBlock

FIELDS
- question: the hook, ending in a question mark. Under 140 characters.
- shortAnswer: the payoff, 2-3 sentences. Must actually answer it, not tease.
- whyItMatters: why this changes how the reader thinks or acts.
- realWorldExample: one concrete, verifiable situation. No invented numbers.
- technicalDetails: the mechanism, for a reader who wants the real explanation.
- interviewAngle: what an interviewer listens for. Omit unless genuinely relevant.
- followUpQuestion: a natural next question. Do not answer it.
- subcategory: a short lowercase slug such as "ssd", "dns", "kafka".
- tags: 2-4 short lowercase slugs.

Return only the JSON array.
''';
  }

  /// Prompt for the Go Deeper chain on an existing question.
  static String deepDive({
    required String question,
    required String shortAnswer,
    String? technicalDetails,
  }) {
    return '''
The reader has just understood this:

QUESTION: $question
ANSWER: $shortAnswer
${technicalDetails == null ? '' : 'DETAIL: $technicalDetails'}

Take them one level deeper into the underlying mechanism.

- Do not restate what they already know above.
- Go down one layer of abstraction, not sideways to a related topic.
- 3-4 short paragraphs, no headings, no bullet lists.
- End with a single sentence naming what the next layer down would be.
''';
  }

  /// Prompt for the "Explain differently" variants.
  static String explanation({
    required String question,
    required String shortAnswer,
    required ExplanationStyle style,
  }) {
    final instruction = switch (style) {
      ExplanationStyle.simple =>
        'Explain it in plain language with no jargon. Short sentences. 2-3 paragraphs.',
      ExplanationStyle.likeImTen =>
        'Explain it to a bright ten-year-old. Use one familiar comparison and keep it accurate — simplified, never wrong. 2 short paragraphs.',
      ExplanationStyle.analogy =>
        'Give one strong analogy and carry it all the way through. Then add one sentence naming where the analogy breaks down.',
      ExplanationStyle.realWorld =>
        'Give a concrete situation an engineer would actually encounter, and walk through what they would observe.',
      ExplanationStyle.technical =>
        'Give the rigorous explanation, including the mechanism and the relevant numbers or protocol details. Assume a professional engineer.',
      ExplanationStyle.interview =>
        'Give the answer as a strong candidate would say it aloud in an interview: structured, roughly 60-90 seconds, leading with the key insight.',
    };

    return '''
QUESTION: $question
ESTABLISHED ANSWER: $shortAnswer

$instruction

Return prose only — no headings, no preamble, no restating the question.
''';
  }

  /// Grades a free-text practice answer.
  ///
  /// The hard part of this prompt is calibration. Left alone, models grade
  /// generously — everything lands between 7 and 9, which makes the score
  /// meaningless and the review schedule useless, since scheduling keys off
  /// whether the answer passed. Hence the explicit anchors.
  static String evaluateAnswer({
    required PracticeMode mode,
    required String question,
    required String referenceAnswer,
    required String userAnswer,
  }) {
    final rubric = mode.dimensions.map((d) => '- $d').join('\n');

    final focus = switch (mode) {
      PracticeMode.interview =>
        'Grade this as an interviewer would: did they lead with the key '
            'insight, structure the answer, and go deep enough to show real '
            'understanding rather than recall?',
      PracticeMode.debugging =>
        'Grade the REASONING, not just the conclusion. Someone who '
            'investigates in a sensible order and uses the metrics to rule '
            'things out scores well even if they do not name the exact root '
            'cause. Someone who guesses the right answer with no reasoning '
            'scores poorly.',
    };

    return '''
$focus

QUESTION
$question

REFERENCE ANSWER (what a strong response covers)
$referenceAnswer

THE CANDIDATE'S ANSWER
$userAnswer

RUBRIC — score each 0-10:
$rubric

CALIBRATION — use the full range. Most real answers are not 8s.
- 9-10  Complete and precise. Would impress a senior engineer.
- 7-8   Correct and well structured, missing some depth or nuance.
- 5-6   The core idea is right but thin, vague, or partly wrong.
- 3-4   Touches the topic, misses the actual mechanism.
- 0-2   Wrong, empty, or unrelated.

An answer of one or two words cannot score above 2, however correct it is —
there is nothing there to assess.

RULES
- "overall" is your honest weighted judgement, not the mean of the dimensions.
- "strengths": at least one, even for a weak answer. Be specific — quote or
  paraphrase what they actually said. Never invent a strength they did not show.
- "missing": what a strong answer covers that theirs did not. Concrete, not
  "more detail".
- "idealAnswer": how you would answer it well, in 3-5 sentences. This is the
  part they learn from, so it must stand on its own.
- Address the candidate as "you". Be direct and unsentimental, never harsh.

Return only the JSON object.
''';
  }

  /// Generates a new production incident to reason about.
  static String debugScenario({
    required List<Category> categories,
    required List<String> avoidTitles,
  }) {
    final categoryList = (categories.isEmpty ? Category.values : categories)
        .map((c) => '${c.id} (${c.label})')
        .join(', ');

    final avoid = avoidTitles.isEmpty
        ? 'None yet.'
        : avoidTitles.take(40).map((t) => '- $t').join('\n');

    return '''
Write one realistic production incident for an engineer to debug.

CATEGORIES — pick one, use its id:
$categoryList

ALREADY USED — do not repeat these or their underlying cause:
$avoid

WHAT MAKES THIS WORK
The metrics must let the reader rule things out. Include numbers that
contradict the obvious diagnosis — an incident where CPU is low is far more
interesting than one where CPU is pegged, because it forces real reasoning
instead of pattern matching.

- situation: 2-4 sentences. What is happening, since when, what changed.
- metrics: 4-6 observed signals with concrete values. Include at least one
  that rules out the lazy answer, and mark normal values as normal.
- prompt: what to investigate. Never hint at the cause.
- title: 3-6 words naming the symptom, not the cause.

Do not reveal or explain the root cause anywhere. The reader must work it out.

Return only the JSON object.
''';
  }
}
