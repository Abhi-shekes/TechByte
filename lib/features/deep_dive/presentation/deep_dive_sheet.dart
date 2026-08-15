import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../services/ai/ai_result.dart';
import '../../../services/ai/prompts/prompt_library.dart';
import '../../questions/domain/question.dart';
import '../application/deep_dive_controller.dart';

/// Bottom sheet for "Go deeper" and "Explain differently".
///
/// Both live in one sheet because they are the same interaction from the
/// user's side — "give me this again, differently" — and because sharing the
/// sheet keeps every AI-backed surface using the identical cache-first path.
class DeepDiveSheet extends ConsumerStatefulWidget {
  const DeepDiveSheet({super.key, required this.question});

  final Question question;

  static Future<void> show(BuildContext context, Question question) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeepDiveSheet(question: question),
    );
  }

  @override
  ConsumerState<DeepDiveSheet> createState() => _DeepDiveSheetState();
}

class _DeepDiveSheetState extends ConsumerState<DeepDiveSheet> {
  late ExplanationRequest _request = ExplanationRequest.deepDive(
    widget.question.id,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(explanationProvider(_request));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            Space.xxxl,
          ),
          children: [
            Text(
              widget.question.question,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Space.lg),
            _StyleSelector(
              selectedKind: _request.kind,
              onSelected: (request) => setState(() => _request = request),
              questionId: widget.question.id,
            ),
            const SizedBox(height: Space.xl),
            switch (async) {
              AsyncLoading() => const _Thinking(),
              AsyncError(:final error) => _Unavailable(
                message: 'Something went wrong.',
                detail: error.toString(),
                onRetry: () => ref.invalidate(explanationProvider(_request)),
              ),
              AsyncData(:final value) => switch (value) {
                AiSuccess(:final value) => SelectableText(
                  value,
                  style: theme.textTheme.bodyLarge,
                ),
                AiUnavailable(:final reason) => _Unavailable(
                  message: reason.message,
                  detail: reason == AiUnavailableReason.quotaExhausted
                      ? 'TechByte runs entirely on free AI quota, so '
                            'generation pauses once the daily limit is '
                            'reached. Everything already saved stays '
                            'available.'
                      : null,
                  onRetry: reason.isRetryable
                      ? () => ref.invalidate(explanationProvider(_request))
                      : null,
                ),
              },
            },
            if (widget.question.followUpQuestion case final followUp?) ...[
              const SizedBox(height: Space.xxl),
              const SectionHeader('Next'),
              Text(followUp, style: theme.textTheme.titleMedium),
            ],
          ],
        );
      },
    );
  }
}

class _StyleSelector extends StatelessWidget {
  const _StyleSelector({
    required this.selectedKind,
    required this.onSelected,
    required this.questionId,
  });

  final String selectedKind;
  final ValueChanged<ExplanationRequest> onSelected;
  final String questionId;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Go deeper'),
            selected: selectedKind == 'deep_dive',
            onSelected: (_) =>
                onSelected(ExplanationRequest.deepDive(questionId)),
          ),
          for (final style in ExplanationStyle.values) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              label: Text(style.label),
              selected: selectedKind == style.id,
              onSelected: (_) =>
                  onSelected(ExplanationRequest.style(questionId, style)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shaped like the paragraph that is coming, so the sheet does not
          // jump when it arrives.
          const AppSkeleton(width: double.infinity, height: 14),
          const SizedBox(height: Space.md),
          const AppSkeleton(width: double.infinity, height: 14),
          const SizedBox(height: Space.md),
          const AppSkeleton(width: double.infinity, height: 14),
          const SizedBox(height: Space.md),
          const AppSkeleton(width: 180, height: 14),
          const SizedBox(height: Space.xl),
          Text(
            'Thinking…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, this.detail, this.onRetry});

  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.titleMedium),
          if (detail case final text?) ...[
            const SizedBox(height: Space.sm),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (onRetry case final retry?) ...[
            const SizedBox(height: Space.lg),
            OutlinedButton(
              onPressed: retry,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Sizes.buttonMd),
              ),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
