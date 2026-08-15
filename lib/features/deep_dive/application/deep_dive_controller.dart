import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../services/ai/ai_result.dart';
import '../../../services/ai/prompts/prompt_library.dart';
import '../data/generated_content_repository.dart';

final generatedContentRepositoryProvider = Provider<GeneratedContentRepository>(
  (ref) => GeneratedContentRepository(ref.watch(appDatabaseProvider)),
);

/// Identifies one piece of derived content: a question plus which variant.
@immutable
class ExplanationRequest {
  const ExplanationRequest({required this.questionId, required this.kind});

  /// Deep dive is modelled as just another variant kind, so it shares the same
  /// cache, the same quota accounting, and the same fallback behaviour.
  const ExplanationRequest.deepDive(this.questionId) : kind = 'deep_dive';

  ExplanationRequest.style(this.questionId, ExplanationStyle style)
    : kind = style.id;

  final String questionId;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is ExplanationRequest &&
      other.questionId == questionId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(questionId, kind);
}

/// Resolves derived content, cache first.
///
/// The ordering here is the fallback chain from the product spec, in one
/// place: local cache, then Gemini, then an explicit unavailable state that
/// the UI explains rather than hides.
final explanationProvider =
    FutureProvider.family<AiResult<String>, ExplanationRequest>((
      ref,
      request,
    ) async {
      final cache = ref.watch(generatedContentRepositoryProvider);

      final cached = await cache.read(request.questionId, request.kind);
      if (cached != null) {
        await ref.read(aiUsageTrackerProvider).recordCacheHit();
        return AiSuccess(cached);
      }

      final question = await ref
          .read(questionRepositoryProvider)
          .byId(request.questionId);
      if (question == null) {
        return const AiUnavailable(AiUnavailableReason.unknown);
      }

      final prefs = ref.read(userPreferencesProvider);
      if (!prefs.aiGenerationEnabled) {
        return const AiUnavailable(AiUnavailableReason.notConfigured);
      }

      final gemini = ref.read(geminiServiceProvider);
      final result = request.kind == 'deep_dive'
          ? await gemini.generateDeepDive(question)
          : await gemini.generateExplanation(
              question,
              ExplanationStyle.values.firstWhere(
                (s) => s.id == request.kind,
                orElse: () => ExplanationStyle.simple,
              ),
            );

      if (result case AiSuccess(:final value)) {
        await cache.write(request.questionId, request.kind, value);
      }
      return result;
    });
