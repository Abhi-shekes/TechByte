/// The shared component layer.
///
/// Every widget here exists because the same thing was previously written
/// between two and seven times across `features/**/presentation/`. Importing
/// this barrel plus `app/theme/app_tokens.dart` should cover everything a
/// screen needs to build itself without a single literal spacing, radius,
/// duration or colour value.
library;

export 'app_nav_bar.dart';
export 'app_panel.dart';
export 'app_search_bar.dart';
export 'app_skeleton.dart';
export 'app_states.dart';
export 'category_mark.dart';
export 'google_mark.dart';
export 'meter_row.dart';
export 'question_tile.dart';
export 'section_header.dart';
export 'stat_tile.dart';
