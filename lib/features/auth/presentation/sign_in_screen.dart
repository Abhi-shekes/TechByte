import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../feed/application/daily_session_controller.dart';
import '../data/auth_repository.dart';

/// Google is the only way in, so this screen has exactly one action.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final outcome = await ref.read(authRepositoryProvider).signInWithGoogle();
    if (outcome is SignInSucceeded) {
      final analytics = ref.read(analyticsServiceProvider);
      unawaited(analytics.setUser(outcome.user.uid));
      unawaited(analytics.signedIn());

      unawaited(_reconcile(outcome.user));
    }
    if (!mounted) return;

    setState(() {
      _busy = false;
      // Cancellation is not an error — the user simply changed their mind, so
      // showing a red message would be wrong.
      _error = switch (outcome) {
        SignInFailed(:final message) => message,
        _ => null,
      };
    });
  }

  /// Reconciles with whatever this account did on another device, then records
  /// the profile.
  ///
  /// Best-effort and never awaited by the sign-in flow: a Firestore outage, or
  /// a project where the database has not been created yet, must not stop
  /// someone getting into the app.
  Future<void> _reconcile(User user) async {
    final sync = ref.read(syncServiceProvider);
    await sync.pull(uid: user.uid);
    await sync.pushProfile(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
      preferences: ref.read(userPreferencesProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppPalette.accentFor(isDark: isDark);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutterReading,
            Space.xxl,
            Space.gutterReading,
            Space.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              CategoryMark(
                label: 'TechByte',
                color: accent,
                size: MarkSize.large,
              ),
              const SizedBox(height: Space.xxl),
              Text(
                'Questions worth\nthinking about.',
                style: theme.textTheme.displayLarge,
              ),
              const SizedBox(height: Space.lg),
              Text(
                'Short technical questions across networking, hardware, '
                'databases, AI and the rest — one swipe at a time.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(flex: 3),

              if (_error case final message?) ...[
                AppPanel(
                  accent: theme.colorScheme.error,
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
              ],

              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const GoogleMark(size: 20),
                label: Text(_busy ? 'Signing in…' : 'Continue with Google'),
                // The column aligns to the start so the headline sets a left
                // edge, which also left every child free to shrink-wrap — so
                // the one action on the screen sat as a short pill against the
                // margin instead of spanning it.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, Sizes.buttonLg),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                'We only use your Google account to sign you in and show your '
                'name. Your password is never shared with TechByte.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
