import 'question.dart';

/// Outcome of validating one candidate question.
sealed class ValidationResult {
  const ValidationResult();
}

final class ValidationAccepted extends ValidationResult {
  const ValidationAccepted(this.question);
  final Question question;
}

final class ValidationRejected extends ValidationResult {
  const ValidationRejected(this.reason);
  final String reason;

  @override
  String toString() => 'ValidationRejected($reason)';
}

/// Content-level validation for questions, applied to *everything* that reaches
/// the feed — generated or curated.
///
/// Schema validity is already guaranteed upstream by the structured-output
/// schema; this layer catches the things a schema cannot: stub text, the
/// textbook phrasings the editorial rule forbids, and near-duplicates of
/// questions the user has already seen.
class QuestionValidator {
  const QuestionValidator({
    this.minQuestionLength = 20,
    this.maxQuestionLength = 220,
    this.minShortAnswerLength = 40,
    this.maxShortAnswerLength = 900,
    this.duplicateThreshold = 0.8,
  });

  final int minQuestionLength;
  final int maxQuestionLength;
  final int minShortAnswerLength;
  final int maxShortAnswerLength;

  /// Token-overlap similarity above which two questions are treated as the
  /// same question. See [_similarity].
  final double duplicateThreshold;

  /// Openers that signal a definition-style question. The product rule is
  /// "make the user curious before giving them the answer" — "What is RAM?"
  /// fails that on its face, so it never reaches the feed.
  static const _textbookOpeners = <String>[
    'what is a ',
    'what is an ',
    'what is the ',
    'what is ',
    'what are ',
    'define ',
    'explain the concept of ',
  ];

  /// Validates one question against the content rules.
  ///
  /// [existingFingerprints] should be the fingerprints of questions already in
  /// the local pool; pass [fingerprint] output from previously accepted items.
  ValidationResult validate(
    Question question, {
    Iterable<Set<String>> existingFingerprints = const [],
  }) {
    final q = question.question.trim();
    final a = question.shortAnswer.trim();

    if (question.id.trim().isEmpty) {
      return const ValidationRejected('empty id');
    }
    if (q.length < minQuestionLength) {
      return ValidationRejected('question too short (${q.length})');
    }
    if (q.length > maxQuestionLength) {
      return ValidationRejected('question too long (${q.length})');
    }
    if (!q.endsWith('?')) {
      return const ValidationRejected('question is not phrased as a question');
    }
    if (a.length < minShortAnswerLength) {
      return ValidationRejected('short answer too short (${a.length})');
    }
    if (a.length > maxShortAnswerLength) {
      return ValidationRejected('short answer too long (${a.length})');
    }

    final lower = q.toLowerCase();
    for (final opener in _textbookOpeners) {
      if (lower.startsWith(opener)) {
        return ValidationRejected('textbook phrasing: "$opener…"');
      }
    }

    // Models occasionally echo the prompt scaffolding or leave placeholders.
    if (lower.contains('as an ai') ||
        lower.contains('lorem ipsum') ||
        a.toLowerCase().contains('as an ai') ||
        a.contains('...') && a.length < 80) {
      return const ValidationRejected('placeholder or meta text');
    }

    final fp = fingerprint(q);
    for (final existing in existingFingerprints) {
      if (_similarity(fp, existing) >= duplicateThreshold) {
        return const ValidationRejected(
          'near-duplicate of an existing question',
        );
      }
    }

    return ValidationAccepted(question);
  }

  /// Normalised content-word set used for duplicate detection.
  static Set<String> fingerprint(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .toSet();
  }

  /// Shared tokens as a fraction of the *larger* question.
  ///
  /// Jaccard is the obvious choice here and is wrong for this job: swapping
  /// two words in a short question ("nearly full" → "almost full") drops it to
  /// around 0.7, so real rephrasings slip through. Dividing by the larger set
  /// instead scores that pair at 0.83 while still refusing to call a short
  /// question a duplicate merely because a longer one contains its words.
  static double _similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length;
    final largest = a.length > b.length ? a.length : b.length;
    return intersection / largest;
  }

  static const _stopWords = <String>{
    'the',
    'and',
    'for',
    'are',
    'but',
    'not',
    'you',
    'your',
    'can',
    'does',
    'did',
    'why',
    'how',
    'what',
    'when',
    'who',
    'which',
    'that',
    'this',
    'with',
    'from',
    'they',
    'them',
    'its',
    'it',
    'is',
    'was',
    'were',
    'be',
    'been',
    'have',
    'has',
    'had',
    'would',
    'could',
    'should',
    'will',
    'may',
    'might',
    'more',
    'most',
    'some',
    'than',
    'then',
    'there',
    'their',
    'even',
    'also',
    'into',
    'over',
    'under',
    'about',
    'actually',
    'happens',
    'happen',
  };
}
