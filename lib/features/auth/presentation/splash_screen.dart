import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';

/// Shown while Firebase reports the initial auth state.
///
/// Uses the same [CategoryMark] lockup as the sign-in screen, so the
/// transition between them really is a continuation rather than a flash of a
/// different layout — which the two screens previously only claimed, having
/// hand-rolled the mark separately at different sizes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppPalette.accentFor(isDark: isDark);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryRule(color: accent),
            const SizedBox(height: Space.lg),
            Text(
              'TECHBYTE',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
