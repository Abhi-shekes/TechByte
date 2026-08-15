/// The complete set of analytics events TechByte emits.
///
/// An enum rather than loose strings so the event vocabulary is reviewable in
/// one place and a typo becomes a compile error instead of a silently
/// mis-named event that nobody notices for a month.
///
/// Firebase requires event names of 1–40 characters, letters/digits/underscore,
/// not starting with a digit. All of these comply.
enum AnalyticsEvent {
  appOpened('app_opened'),
  feedStarted('feed_started'),
  questionViewed('question_viewed'),
  answerRevealed('answer_revealed'),
  questionCompleted('question_completed'),
  questionSkipped('question_skipped'),
  questionSaved('question_saved'),
  questionShared('question_shared'),
  questionReported('question_reported'),
  deepDiveOpened('deep_dive_opened'),
  explanationRequested('explanation_requested'),
  interviewStarted('interview_started'),
  interviewCompleted('interview_completed'),
  debugStarted('debug_started'),
  debugCompleted('debug_completed'),
  reviewAnswered('review_answered'),
  dailySessionCompleted('daily_session_completed'),
  aiGenerationSucceeded('ai_generation_succeeded'),
  aiGenerationUnavailable('ai_generation_unavailable'),
  onboardingCompleted('onboarding_completed'),
  signedIn('signed_in'),
  signedOut('signed_out');

  const AnalyticsEvent(this.name);

  final String name;
}

/// Parameter keys, kept together for the same reason as the event names.
///
/// Nothing here is personal data. Only categories, question types, difficulty,
/// scores and counts are recorded — never question text, never answer text,
/// never anything typed by the user, and never an email or display name.
abstract final class AnalyticsParam {
  static const category = 'category';
  static const questionType = 'question_type';
  static const difficulty = 'difficulty';
  static const source = 'source';
  static const mode = 'mode';
  static const score = 'score';
  static const passed = 'passed';
  static const count = 'count';
  static const style = 'style';
  static const reason = 'reason';
  static const correct = 'correct';
  static const stage = 'stage';
}
