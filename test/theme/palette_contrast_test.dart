import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techbyte/app/theme/app_palette.dart';
import 'package:techbyte/features/questions/domain/question_enums.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Locks in the light-mode palette rebuild.
///
/// The original palette was designed for a near-black ground and reused
/// verbatim in light mode, where all eighteen category colours plus the accent
/// and every semantic colour failed contrast — the worst at 1.44:1, rendered at
/// 11.5px above every question. These tests exist so that regression cannot
/// happen silently a second time.
void main() {
  const textMinimum = 4.5;
  const uiMinimum = 3.0;

  group('category colours', () {
    for (final category in Category.values) {
      test('${category.id} is legible in both themes', () {
        final onLight = _contrast(
          AppPalette.forCategory(category.id, isDark: false),
          AppPalette.lightBackground,
        );
        final onDark = _contrast(
          AppPalette.forCategory(category.id, isDark: true),
          AppPalette.darkBackground,
        );

        expect(
          onLight,
          greaterThanOrEqualTo(textMinimum),
          reason:
              '${category.id} light variant is ${onLight.toStringAsFixed(2)}:1 '
              'on the light background',
        );
        expect(
          onDark,
          greaterThanOrEqualTo(textMinimum),
          reason:
              '${category.id} dark variant is ${onDark.toStringAsFixed(2)}:1 '
              'on the dark background',
        );
      });
    }

    test('every category is visually distinct from every other', () {
      // Two categories sharing a hue means two categories with one identity;
      // DevOps and Cybersecurity previously did.
      for (final isDark in [true, false]) {
        final seen = <int, String>{};
        for (final category in Category.values) {
          final value = AppPalette.forCategory(
            category.id,
            isDark: isDark,
          ).toARGB32();
          expect(
            seen.containsKey(value),
            isFalse,
            reason:
                '${category.id} shares a colour with ${seen[value]} '
                'in ${isDark ? 'dark' : 'light'} mode',
          );
          seen[value] = category.id;
        }
      }
    });
  });

  group('accent and semantic colours', () {
    final pairs = <String, (Color, Color)>{
      'accent on light': (AppPalette.accent, AppPalette.lightBackground),
      'accent on dark': (AppPalette.accentDark, AppPalette.darkBackground),
      'success on light': (AppPalette.success, AppPalette.lightBackground),
      'success on dark': (AppPalette.successDark, AppPalette.darkBackground),
      'warning on light': (AppPalette.warning, AppPalette.lightBackground),
      'warning on dark': (AppPalette.warningDark, AppPalette.darkBackground),
      'danger on light': (AppPalette.danger, AppPalette.lightBackground),
      'danger on dark': (AppPalette.dangerDark, AppPalette.darkBackground),
    };

    pairs.forEach((name, pair) {
      test('$name clears $textMinimum:1', () {
        final ratio = _contrast(pair.$1, pair.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(textMinimum),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });
  });

  group('navigation dock', () {
    // The dock is painted from fixed dark-palette values in *both* themes,
    // because its whole character is being a dark object floating over the
    // interface. That means the scheme-driven contrast guarantees elsewhere in
    // this file do not cover it, and nothing else would catch a regression
    // here — in light mode the dock does not use the light palette at all.
    const surface = AppPalette.darkSurfaceRaised;

    final pairs = <String, (Color, Color, double)>{
      'selected icon': (AppPalette.accentDark, surface, uiMinimum),
      'idle icon': (AppPalette.darkTextSecondary, surface, textMinimum),
      'separator against the dock': (
        AppPalette.darkOutline,
        surface,
        // A hairline divider is decoration, not a control: it is deliberately
        // subtle, and only has to be perceptible.
        1.1,
      ),
    };

    pairs.forEach((name, pair) {
      test('$name clears ${pair.$3}:1 on the dock', () {
        final ratio = _contrast(pair.$1, pair.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(pair.$3),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });

    test('the dock separates from a light-mode page', () {
      // If this ever fails the silhouette has stopped reading, which is the
      // one thing the design cannot lose.
      expect(
        _contrast(surface, AppPalette.lightBackground),
        greaterThanOrEqualTo(uiMinimum),
      );
    });
  });

  group('filled control foregrounds', () {
    final pairs = <String, (Color, Color)>{
      'onAccent over accent': (AppPalette.onAccent, AppPalette.accent),
      'onAccentDark over accentDark': (
        AppPalette.onAccentDark,
        AppPalette.accentDark,
      ),
      'onSuccess over success': (AppPalette.onSuccess, AppPalette.success),
      'onSuccessDark over successDark': (
        AppPalette.onSuccessDark,
        AppPalette.successDark,
      ),
    };

    pairs.forEach((name, pair) {
      test('$name clears $textMinimum:1', () {
        final ratio = _contrast(pair.$1, pair.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(textMinimum),
          reason: '$name is ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });
  });

  group('body text', () {
    test('secondary text is legible on its own ground', () {
      expect(
        _contrast(AppPalette.lightTextSecondary, AppPalette.lightBackground),
        greaterThanOrEqualTo(textMinimum),
      );
      expect(
        _contrast(AppPalette.darkTextSecondary, AppPalette.darkBackground),
        greaterThanOrEqualTo(textMinimum),
      );
    });

    test('primary text clears the UI minimum comfortably', () {
      expect(
        _contrast(AppPalette.lightTextPrimary, AppPalette.lightBackground),
        greaterThan(uiMinimum),
      );
      expect(
        _contrast(AppPalette.darkTextPrimary, AppPalette.darkBackground),
        greaterThan(uiMinimum),
      );
    });
  });
}
