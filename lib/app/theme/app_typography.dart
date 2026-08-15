import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for TechByte.
///
/// The question is the hero element, so the display sizes are much larger than
/// stock Material and the body sizes stay comfortable for 30–90s of reading.
/// `google_fonts` resolves from its bundled cache and falls back to the
/// platform font when offline, so first launch without a network still renders.
///
/// [bodySmall], [labelLarge] and [monoSmall] exist because eleven screens were
/// patching `bodyMedium` to 12.5 or 12 and `labelSmall` to 10 or 13 inline. The
/// scale declared seven roles while the app actually shipped eleven; these are
/// the four it was missing, so every inline override could be deleted.
abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    return GoogleFonts.interTextTheme(base).copyWith(
      // Reserved for the question itself.
      displayLarge: GoogleFonts.inter(
        fontSize: 34,
        height: 1.14,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 28,
        height: 1.20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 24,
        height: 1.24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16.5,
        height: 1.55,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      // Captions, help text and tile metadata.
      bodySmall: GoogleFonts.inter(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      // Section eyebrows.
      labelLarge: GoogleFonts.inter(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      // The small caps category label above each question.
      labelSmall: GoogleFonts.inter(
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  /// Monospace, for the technical-detail sections and any inline identifiers.
  static TextStyle mono({double fontSize = 13.5, Color? color}) =>
      GoogleFonts.jetBrainsMono(fontSize: fontSize, height: 1.5, color: color);

  /// Inline data: metric rows, small tabular values.
  static TextStyle monoSmall({Color? color}) =>
      GoogleFonts.jetBrainsMono(fontSize: 12, height: 1.45, color: color);
}
