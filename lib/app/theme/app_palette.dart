import 'package:flutter/material.dart';

/// Raw colour values for TechByte.
///
/// The feed is the product, and the feed is mostly a single large block of
/// text on a dark ground. Everything here is tuned for that: deep neutral
/// backgrounds, one saturated accent, and per-category hues used only as
/// small identifying marks (never as card fills, which would fight the text).
///
/// Every colour exists in two versions. The dark set was designed first and is
/// unchanged. The light set is derived from it — same hue, luminance lowered
/// until it clears 4.5:1 against [lightBackground] — because the original
/// palette was reused verbatim in light mode, where all eighteen category
/// colours plus the accent and all three semantic colours failed contrast. The
/// worst was 1.44:1, rendered at 11.5px above every question.
abstract final class AppPalette {
  // Dark (primary experience).
  static const darkBackground = Color(0xFF0A0C0F);
  static const darkSurface = Color(0xFF13171D);
  static const darkSurfaceRaised = Color(0xFF1B2027);
  static const darkOutline = Color(0xFF2A313B);
  static const darkOutlineStrong = Color(0xFF39414D);
  static const darkTextPrimary = Color(0xFFF2F5F8);
  static const darkTextSecondary = Color(0xFF9BA6B4);

  // Light.
  static const lightBackground = Color(0xFFFBFCFD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFF1F4F7);
  static const lightOutline = Color(0xFFD9E0E8);
  static const lightOutlineStrong = Color(0xFFC5CED8);
  static const lightTextPrimary = Color(0xFF0D1117);
  static const lightTextSecondary = Color(0xFF5A6673);

  /// The single brand accent, used for reveal affordances and progress.
  static const accent = Color(0xFF1167FF); // 4.64:1 on light
  static const accentDark = Color(0xFF6BA4FF); // 7.81:1 on dark

  /// Foreground for filled controls painted in [accent] / [accentDark].
  static const onAccent = Color(0xFFFFFFFF);
  static const onAccentDark = Color(0xFF06213F);

  static const success = Color(0xFF188350); // 4.65:1 on light
  static const successDark = Color(0xFF3DD68C);

  /// Foreground for controls filled with the success colour.
  static const onSuccess = Color(0xFFFFFFFF);
  static const onSuccessDark = Color(0xFF06231A);
  static const warning = Color(0xFFA36503); // 4.63:1 on light
  static const warningDark = Color(0xFFF5A524);
  static const danger = Color(0xFFE60C0C); // 4.62:1 on light
  static const dangerDark = Color(0xFFF25C5C);

  static Color accentFor({required bool isDark}) =>
      isDark ? accentDark : accent;
  static Color onAccentFor({required bool isDark}) =>
      isDark ? onAccentDark : onAccent;
  static Color successFor({required bool isDark}) =>
      isDark ? successDark : success;
  static Color onSuccessFor({required bool isDark}) =>
      isDark ? onSuccessDark : onSuccess;
  static Color warningFor({required bool isDark}) =>
      isDark ? warningDark : warning;
  static Color dangerFor({required bool isDark}) =>
      isDark ? dangerDark : danger;

  /// Per-category identity colours, keyed by [Category.id].
  ///
  /// Used for the small category label above each question and for chips in
  /// Explore. Kept deliberately desaturated so ten of them on one screen still
  /// read as one palette.
  static const _categoryDark = <String, Color>{
    'programming': Color(0xFF7AA2F7),
    'computer_science': Color(0xFF9D7CD8),
    'operating_systems': Color(0xFFE0AF68),
    'networking': Color(0xFF7DCFFF),
    'internet': Color(0xFF56C7E5),
    'databases': Color(0xFF73DACA),
    'backend': Color(0xFF89DDFF),
    'cloud': Color(0xFF82AAFF),
    // DevOps and Cybersecurity shared one hue, which meant two categories had
    // one identity. Split in both sets.
    'devops': Color(0xFFF7768E),
    'ai_ml': Color(0xFFBB9AF7),
    'hardware': Color(0xFFFF9E64),
    'mobile': Color(0xFF4FD6BE),
    'cybersecurity': Color(0xFFE06C9F),
    'electronics': Color(0xFFFFC777),
    'distributed_systems': Color(0xFFC099FF),
    'system_design': Color(0xFF86E1FC),
    'developer_tools': Color(0xFFA9B1D6),
    'real_world_tech': Color(0xFF7DE3A3),
  };

  /// Light-mode counterparts. Each verified at or above 4.5:1 on
  /// [lightBackground]; the ratio is noted where it is close to the floor.
  static const _categoryLight = <String, Color>{
    'programming': Color(0xFF2568F8), // 4.63
    'computer_science': Color(0xFF865BD2), // 4.60
    'operating_systems': Color(0xFF9D681C), // 4.61
    'networking': Color(0xFF0078BF), // 4.61
    'internet': Color(0xFF137D9A), // 4.62
    'databases': Color(0xFF1F8172), // 4.60
    'backend': Color(0xFF007BAD), // 4.61
    'cloud': Color(0xFF1F67FF), // 4.60
    'devops': Color(0xFFC4102C), // 5.91
    'ai_ml': Color(0xFF894CF6), // 4.62
    'hardware': Color(0xFFC74B00), // 4.61
    'mobile': Color(0xFF1B816F), // 4.63
    'cybersecurity': Color(0xFFB01236), // 6.85
    'electronics': Color(0xFFA76300), // 4.62
    'distributed_systems': Color(0xFF8C46FF), // 4.61
    'system_design': Color(0xFF007CA1), // 4.65
    'developer_tools': Color(0xFF5F6FB7), // 4.60
    'real_world_tech': Color(0xFF198441), // 4.63
  };

  /// Falls back to the brand accent for categories added later (including any
  /// the AI invents), so an unknown category never renders colourless.
  ///
  /// [isDark] selects the value, not merely the fallback — that distinction was
  /// the bug that made light mode illegible.
  static Color forCategory(String categoryId, {required bool isDark}) {
    final table = isDark ? _categoryDark : _categoryLight;
    return table[categoryId] ?? accentFor(isDark: isDark);
  }
}
