import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Outcome of a sign-in attempt.
///
/// Cancellation is modelled as a distinct, non-error case: the user backing out
/// of the account picker is normal and must not surface as a failure message.
sealed class SignInOutcome {
  const SignInOutcome();
}

final class SignInSucceeded extends SignInOutcome {
  const SignInSucceeded(this.user);
  final User user;
}

final class SignInCancelled extends SignInOutcome {
  const SignInCancelled();
}

final class SignInFailed extends SignInOutcome {
  const SignInFailed(this.message);
  final String message;
}

/// Google Sign-In on top of Firebase Authentication.
///
/// Google is the only provider by product requirement — no email/password, no
/// phone, no anonymous. That keeps the surface small: there are no credentials
/// to store, nothing to reset, and no password to leak.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _auth = auth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  /// `initialize` must be called exactly once per process, so the future is
  /// cached and awaited by every entry point rather than guarded by a bool.
  Future<void>? _initialization;

  /// On Android the serverClientId is resolved automatically from the
  /// `default_web_client_id` resource that the google-services Gradle plugin
  /// generates from google-services.json, so nothing needs hardcoding here.
  Future<void> _ensureInitialized() =>
      _initialization ??= _googleSignIn.initialize();

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Attempts a silent sign-in using a previously granted session.
  ///
  /// Used on launch so a returning user goes straight to the feed without an
  /// account picker. Failure is silent by design — it just means we show the
  /// sign-in screen.
  Future<void> restoreSession() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.attemptLightweightAuthentication();
    } on GoogleSignInException {
      // Nothing to restore.
    } on Exception {
      // Never block launch on session restoration.
    }
  }

  /// Interactive Google sign-in, exchanged for a Firebase credential.
  Future<SignInOutcome> signInWithGoogle() async {
    try {
      await _ensureInitialized();

      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;

      if (idToken == null) {
        return const SignInFailed(
          'Google did not return an ID token. Check that Google Sign-In is '
          'enabled for this Firebase project and that the SHA-1 fingerprint '
          'is registered.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);

      final user = result.user;
      if (user == null) return const SignInFailed('Sign-in failed.');
      return SignInSucceeded(user);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const SignInCancelled();
      }
      return SignInFailed(e.description ?? 'Google sign-in failed.');
    } on FirebaseAuthException catch (e) {
      return SignInFailed(e.message ?? 'Authentication failed.');
    } on Exception {
      return const SignInFailed('Could not sign in. Check your connection.');
    }
  }

  /// Signs out of both Firebase and Google.
  ///
  /// Google is signed out too so the next sign-in shows the account picker
  /// rather than silently reusing the same account.
  Future<void> signOut() async {
    await _ensureInitialized();
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  /// Deletes the Firebase user and revokes the Google grant.
  ///
  /// Local data is cleared by the caller; Firestore documents are removed by
  /// the account-deletion path in the sync layer. Firebase requires a recent
  /// sign-in for this, so [AccountDeletionOutcome.requiresRecentLogin] tells
  /// the caller to re-authenticate and try again.
  Future<AccountDeletionOutcome> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return AccountDeletionOutcome.notSignedIn;

    try {
      await _ensureInitialized();
      await _googleSignIn.disconnect();
      await user.delete();
      return AccountDeletionOutcome.deleted;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return AccountDeletionOutcome.requiresRecentLogin;
      }
      return AccountDeletionOutcome.failed;
    } on Exception {
      return AccountDeletionOutcome.failed;
    }
  }
}

enum AccountDeletionOutcome {
  deleted,
  requiresRecentLogin,
  notSignedIn,
  failed,
}
