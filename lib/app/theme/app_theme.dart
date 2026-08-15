import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Material 3 themes for TechByte, in both brightnesses.
abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  /// System UI overlay matching a given brightness, applied by the shell so the
  /// status bar disappears into the full-bleed feed.
  static SystemUiOverlayStyle overlayFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? AppPalette.darkBackground
          : AppPalette.lightBackground,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final background = isDark
        ? AppPalette.darkBackground
        : AppPalette.lightBackground;
    final surface = isDark ? AppPalette.darkSurface : AppPalette.lightSurface;
    final surfaceRaised = isDark
        ? AppPalette.darkSurfaceRaised
        : AppPalette.lightSurfaceRaised;
    final outline = isDark ? AppPalette.darkOutline : AppPalette.lightOutline;
    final outlineStrong = isDark
        ? AppPalette.darkOutlineStrong
        : AppPalette.lightOutlineStrong;
    final textPrimary = isDark
        ? AppPalette.darkTextPrimary
        : AppPalette.lightTextPrimary;
    final textSecondary = isDark
        ? AppPalette.darkTextSecondary
        : AppPalette.lightTextSecondary;
    final accent = AppPalette.accentFor(isDark: isDark);
    final onAccent = AppPalette.onAccentFor(isDark: isDark);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      error: AppPalette.dangerFor(isDark: isDark),
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceRaised,
      surfaceContainerHigh: surfaceRaised,
      onSurfaceVariant: textSecondary,
      outline: outline,
      // outlineVariant is the stronger of the two here, reserved for the
      // overlay depth tier — Material's naming implies the reverse, but the
      // tiers need two distinct border weights and these are the two slots.
      outlineVariant: outlineStrong,
    );

    final textTheme = AppTypography.textTheme(
      brightness,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: overlayFor(brightness),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: Radii.xlAll,
        ).copyWith(side: BorderSide(color: outline)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRaised,
        side: BorderSide(color: outline),
        labelStyle: textTheme.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: Radii.fullAll),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, Sizes.buttonLg),
          textStyle: textTheme.titleMedium,
          shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, Sizes.buttonLg),
          side: BorderSide(color: outline),
          textStyle: textTheme.titleMedium,
          shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, Sizes.buttonMd),
          textStyle: textTheme.titleMedium,
          shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          // Every icon button clears the WCAG 2.2 target minimum. The feed
          // card previously shrank these with `visualDensity: compact`, at the
          // top corner of the screen where they are hardest to hit.
          minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: Radii.mdAll),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.mdAll,
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Depth.overlay.background(scheme),
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.16),
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: Radii.fullAll,
        ),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Depth.overlay.background(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Depth.overlay.background(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: Radii.xlAll),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Depth.overlay.background(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(color: outlineStrong),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearMinHeight: Sizes.meterTrack,
        linearTrackColor: surfaceRaised,
        circularTrackColor: surfaceRaised,
        color: accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
