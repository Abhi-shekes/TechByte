import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:uuid/uuid.dart';

import '../../app/config/ai_config.dart';
import '../../features/practice/domain/answer_evaluation.dart';
import '../../features/practice/domain/debug_scenario.dart';
import '../../features/practice/domain/practice_mode.dart';
import '../../features/questions/domain/question.dart';
import '../../features/questions/domain/question_enums.dart';
import '../../features/questions/domain/question_validator.dart';
import 'ai_result.dart';
import 'ai_usage_tracker.dart';
import 'prompts/prompt_library.dart';

/// The single boundary between TechByte and Gemini.
///
/// Nothing else in the app imports `firebase_ai`. Widgets never call this
/// directly either — the feed controller does, off the swipe path.
///
/// Billing safety: this class only ever constructs [FirebaseAI.googleAI], the
/// Gemini Developer API backend, which has a no-cost tier. The Vertex AI
/// backend requires a billing account and is deliberately never referenced.
class GeminiService {
  GeminiService({
    required AiUsageTracker usageTracker,
    QuestionValidator validator = const QuestionValidator(),
    FirebaseAI? firebaseAI,
  }) : _usage = usageTracker,
       _validator = validator,
       _ai = firebaseAI ?? FirebaseAI.googleAI();

  final AiUsageTracker _usage;
  final QuestionValidator _validator;
  final FirebaseAI _ai;
  final _uuid = const Uuid();

  GenerativeModel? _questionModel;
  GenerativeModel? _proseModel;
  GenerativeModel? _evaluationModel;
  GenerativeModel? _scenarioModel;

  /// Structured-output schema for generated questions.
  ///
  /// Constraining the model at the API level is what makes parsing reliable;
  /// [QuestionValidator] then handles the things a schema cannot express, such
  /// as banned phrasings and near-duplicates.
  static final _questionSchema = Schema.array(
    items: Schema.object(
      properties: {
        'question': Schema.string(),
        'shortAnswer': Schema.string(),
        'whyItMatters': Schema.string(),
        'realWorldExample': Schema.string(),
        'technicalDetails': Schema.string(),
        'interviewAngle': Schema.string(),
        'followUpQuestion': Schema.string(),
        'type': Schema.enumString(
          enumValues: QuestionType.values.map((t) => t.id).toList(),
        ),
        'category': Schema.enumString(
          enumValues: Category.values.map((c) => c.id).toList(),
        ),
        'difficulty': Schema.enumString(
          enumValues: Difficulty.values.map((d) => d.id).toList(),
        ),
        'subcategory': Schema.string(),
        'tags': Schema.array(items: Schema.string()),
      },
      optionalProperties: const ['interviewAngle', 'subcategory', 'tags'],
    ),
  );

  GenerativeModel get _questions => _questionModel ??= _ai.generativeModel(
    model: AiConfig.model,
    systemInstruction: Content.text(PromptLibrary.systemInstruction),
    generationConfig: GenerationConfig(
      temperature: AiConfig.temperature,
      responseMimeType: 'application/json',
      responseSchema: _questionSchema,
    ),
  );

  GenerativeModel get _prose => _proseModel ??= _ai.generativeModel(
    model: AiConfig.model,
    systemInstruction: Content.text(PromptLibrary.systemInstruction),
    generationConfig: GenerationConfig(temperature: AiConfig.temperature),
  );

  /// Whether a request is permitted right now, without making one.
  Future<bool> get isAvailable => _usage.canRequest();

  /// Generates and validates a batch of new questions.
  ///
  /// Returns only questions that passed validation, which may be fewer than
  /// requested — or none. Callers must treat an empty success as normal and
  /// fall back to the existing local pool.
  Future<AiResult<List<Question>>> generateQuestions({
    required List<Category> categories,
    required ExperienceLevel level,
    required LearningGoal goal,
    required List<String> avoidQuestions,
    int count = AiConfig.questionsPerGeneration,
  }) async {
    final prompt = PromptLibrary.questionGeneration(
      count: count,
      categories: categories,
      level: level,
      goal: goal,
      avoidQuestions: avoidQuestions,
    );

    final raw = await _request(_questions, prompt);
    if (raw is AiUnavailable<String>) {
      return AiUnavailable(raw.reason, detail: raw.detail);
    }

    final text = (raw as AiSuccess<String>).value;
    final decoded = _decodeJsonArray(text);
    if (decoded == null) {
      await _usage.recordFailure(isQuota: false);
      return const AiUnavailable(AiUnavailableReason.invalidResponse);
    }

    // Seed the duplicate check with what the user already has, then extend it
    // as the batch is accepted so the model can't repeat itself within one run.
    final fingerprints = avoidQuestions
        .map(QuestionValidator.fingerprint)
        .toList(growable: true);

    final accepted = <Question>[];
    var rejected = 0;

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        rejected++;
        continue;
      }

      final candidate = Question.fromJson({
        ...item,
        'id': 'ai_${_uuid.v4()}',
        'source': QuestionSource.ai.id,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final result = _validator.validate(
        candidate,
        existingFingerprints: fingerprints,
      );

      switch (result) {
        case ValidationAccepted(:final question):
          accepted.add(question);
          fingerprints.add(QuestionValidator.fingerprint(question.question));
        case ValidationRejected():
          rejected++;
      }
    }

    await _usage.recordGenerationOutcome(
      accepted: accepted.length,
      rejected: rejected,
    );

    return AiSuccess(accepted);
  }

  /// Structured-output schema for a graded answer.
  static final _evaluationSchema = Schema.object(
    properties: {
      'overall': Schema.number(),
      'dimensions': Schema.array(
        items: Schema.object(
          properties: {'label': Schema.string(), 'score': Schema.number()},
        ),
      ),
      'strengths': Schema.array(items: Schema.string()),
      'missing': Schema.array(items: Schema.string()),
      'idealAnswer': Schema.string(),
      'followUpQuestion': Schema.string(),
    },
    optionalProperties: const ['followUpQuestion'],
  );

  static final _scenarioSchema = Schema.object(
    properties: {
      'title': Schema.string(),
      'situation': Schema.string(),
      'metrics': Schema.array(
        items: Schema.object(
          properties: {'label': Schema.string(), 'value': Schema.string()},
        ),
      ),
      'prompt': Schema.string(),
      'category': Schema.enumString(
        enumValues: Category.values.map((c) => c.id).toList(),
      ),
      'difficulty': Schema.enumString(
        enumValues: Difficulty.values.map((d) => d.id).toList(),
      ),
    },
    optionalProperties: const ['difficulty'],
  );

  GenerativeModel _jsonModel(Schema schema, {double? temperature}) =>
      _ai.generativeModel(
        model: AiConfig.model,
        systemInstruction: Content.text(PromptLibrary.systemInstruction),
        generationConfig: GenerationConfig(
          temperature: temperature ?? AiConfig.temperature,
          responseMimeType: 'application/json',
          responseSchema: schema,
        ),
      );

  /// Grades a free-text practice answer.
  ///
  /// Runs at a low temperature: grading should be as reproducible as the API
  /// allows, since an identical answer scoring 5 one minute and 8 the next
  /// would make both the feedback and the review schedule untrustworthy.
  Future<AiResult<AnswerEvaluation>> evaluateAnswer({
    required PracticeMode mode,
    required String question,
    required String referenceAnswer,
    required String userAnswer,
  }) async {
    final raw = await _request(
      _evaluationModel ??= _jsonModel(_evaluationSchema, temperature: 0.2),
      PromptLibrary.evaluateAnswer(
        mode: mode,
        question: question,
        referenceAnswer: referenceAnswer,
        userAnswer: userAnswer,
      ),
    );

    if (raw is AiUnavailable<String>) {
      return AiUnavailable(raw.reason, detail: raw.detail);
    }

    final json = _decodeJsonObject((raw as AiSuccess<String>).value);
    if (json == null) {
      await _usage.recordFailure(isQuota: false);
      return const AiUnavailable(AiUnavailableReason.invalidResponse);
    }

    final evaluation = AnswerEvaluation.fromJson(json);
    if (!evaluation.isUsable) {
      // A score with no ideal answer is a number without the part that
      // teaches anything, so it is treated as invalid rather than shown.
      await _usage.recordFailure(isQuota: false);
      return const AiUnavailable(AiUnavailableReason.invalidResponse);
    }

    return AiSuccess(evaluation);
  }

  /// Generates a new production incident to reason about.
  Future<AiResult<DebugScenario>> generateDebugScenario({
    List<Category> categories = const [],
    List<String> avoidTitles = const [],
  }) async {
    final raw = await _request(
      _scenarioModel ??= _jsonModel(_scenarioSchema),
      PromptLibrary.debugScenario(
        categories: categories,
        avoidTitles: avoidTitles,
      ),
    );

    if (raw is AiUnavailable<String>) {
      return AiUnavailable(raw.reason, detail: raw.detail);
    }

    final json = _decodeJsonObject((raw as AiSuccess<String>).value);
    if (json == null) {
      await _usage.recordFailure(isQuota: false);
      return const AiUnavailable(AiUnavailableReason.invalidResponse);
    }

    final scenario = DebugScenario.fromJson(json, id: 'ai_${_uuid.v4()}');
    if (!scenario.isUsable) {
      await _usage.recordFailure(isQuota: false);
      return const AiUnavailable(AiUnavailableReason.invalidResponse);
    }

    return AiSuccess(scenario);
  }

  /// One level deeper on an existing question. Cached by the caller.
  Future<AiResult<String>> generateDeepDive(Question question) {
    return _request(
      _prose,
      PromptLibrary.deepDive(
        question: question.question,
        shortAnswer: question.shortAnswer,
        technicalDetails: question.technicalDetails,
      ),
    );
  }

  /// An alternate framing of an answer the user has already seen.
  Future<AiResult<String>> generateExplanation(
    Question question,
    ExplanationStyle style,
  ) {
    return _request(
      _prose,
      PromptLibrary.explanation(
        question: question.question,
        shortAnswer: question.shortAnswer,
        style: style,
      ),
    );
  }

  /// Issues one request, enforcing the local budget, timeout and retry policy.
  ///
  /// Retries at most [AiConfig.maxRetries] times and never retries a quota
  /// error — repeated attempts against a spent quota only waste the budget the
  /// app is trying to protect.
  Future<AiResult<String>> _request(
    GenerativeModel model,
    String prompt,
  ) async {
    if (!await _usage.canRequest()) {
      return const AiUnavailable(AiUnavailableReason.quotaExhausted);
    }

    for (var attempt = 0; attempt <= AiConfig.maxRetries; attempt++) {
      try {
        await _usage.recordRequest();

        final response = await model
            .generateContent([Content.text(prompt)])
            .timeout(AiConfig.requestTimeout);

        final text = response.text?.trim();
        if (text == null || text.isEmpty) {
          // An empty body with no exception usually means a safety block.
          await _usage.recordFailure(isQuota: false);
          return const AiUnavailable(AiUnavailableReason.safetyBlocked);
        }
        return AiSuccess(text);
      } on QuotaExceeded catch (e) {
        await _usage.recordFailure(isQuota: true);
        return AiUnavailable(
          AiUnavailableReason.quotaExhausted,
          detail: e.message,
        );
      } on ServiceApiNotEnabled catch (e) {
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(
          AiUnavailableReason.notConfigured,
          detail: e.message,
        );
      } on InvalidApiKey catch (e) {
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(
          AiUnavailableReason.notConfigured,
          detail: e.message,
        );
      } on UnsupportedUserLocation catch (e) {
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(
          AiUnavailableReason.notConfigured,
          detail: e.message,
        );
      } on SocketException {
        await _usage.recordFailure(isQuota: false);
        return const AiUnavailable(AiUnavailableReason.offline);
      } on TimeoutException {
        await _usage.recordFailure(isQuota: false);
        if (attempt == AiConfig.maxRetries) {
          return const AiUnavailable(AiUnavailableReason.rateLimited);
        }
      } on ServerException catch (e) {
        await _usage.recordFailure(isQuota: false);
        // A retired model id arrives here as a 404 ("no longer available to
        // new users"). Retrying cannot fix it and "AI is busy right now" sends
        // whoever reads it hunting for a rate limit, so call it what it is:
        // a configuration problem, reported on the first attempt.
        if (_isModelUnavailable(e.message)) {
          return AiUnavailable(
            AiUnavailableReason.notConfigured,
            detail: e.message,
          );
        }
        if (attempt == AiConfig.maxRetries) {
          return AiUnavailable(
            AiUnavailableReason.rateLimited,
            detail: e.message,
          );
        }
      } on FirebaseAIException catch (e) {
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(AiUnavailableReason.unknown, detail: e.message);
      } on FirebaseException catch (e) {
        // Not a Firebase AI error at all: `FirebaseAIException` is its own
        // hierarchy and implements `Exception` directly, so nothing above
        // catches what the *other* Firebase plugins throw while the request is
        // being assembled. The common one is App Check failing to mint a token
        // — "code: 403 body: App attestation failed" — which happens before a
        // single byte reaches Gemini. It used to escape this method, escape
        // the controller that awaited it, and land in the global error handler
        // with the calling screen left in its loading state forever.
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(
          AiUnavailableReason.notConfigured,
          detail: '${e.plugin}/${e.code}: ${e.message}',
        );
      } catch (error) {
        // The same guarantee for anything else: this method's contract is that
        // it returns a result, never throws.
        await _usage.recordFailure(isQuota: false);
        return AiUnavailable(AiUnavailableReason.unknown, detail: '$error');
      }
    }

    return const AiUnavailable(AiUnavailableReason.unknown);
  }

  /// Whether a server error means the configured model id itself is gone,
  /// rather than the request being throttled or the backend having a bad
  /// moment. Matched on the message because `firebase_ai` surfaces every
  /// non-quota HTTP failure as the same [ServerException] type.
  static bool _isModelUnavailable(String message) {
    final text = message.toLowerCase();
    return text.contains('no longer available') ||
        text.contains('is not found') ||
        text.contains('not found for api version');
  }

  /// Parses a JSON object, tolerating the same fencing as [_decodeJsonArray].
  static Map<String, dynamic>? _decodeJsonObject(String text) {
    final decoded = _decodeJson(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Parses a JSON array.
  static List<dynamic>? _decodeJsonArray(String text) {
    final decoded = _decodeJson(text);
    return decoded is List ? decoded : null;
  }

  /// Decodes JSON, tolerating the fenced code blocks models sometimes emit
  /// despite a JSON response mime type.
  static Object? _decodeJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    try {
      return jsonDecode(cleaned);
    } on FormatException {
      return null;
    }
  }
}
