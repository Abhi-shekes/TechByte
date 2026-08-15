import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/storage/app_database.dart';
import '../../features/questions/data/question_repository.dart';
import '../../features/settings/domain/user_preferences.dart';

/// Outcome of a sync attempt. Never an exception — being unable to sync is a
/// normal state, not an error the user should see.
enum SyncOutcome { succeeded, nothingToDo, notSignedIn, failed }

/// Mirrors local user state to Firestore and back.
///
/// Firestore is a **backup and multi-device channel, never a read path for the
/// feed**. Everything the app displays comes from SQLite; this class only ever
/// runs in the background. That is what keeps document reads far inside the
/// free tier and the app fast offline.
///
/// Cost shape, and why it is built this way:
///   - Writes are batched, so N changed questions cost one round trip.
///   - Only rows with `synced = false` are uploaded, so a quiet day costs
///     nothing at all.
///   - Pull happens on sign-in, not on launch — a returning user on one device
///     has nothing to reconcile.
class SyncService {
  SyncService({
    required QuestionRepository questions,
    FirebaseFirestore? firestore,
  }) : _questions = questions,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final QuestionRepository _questions;
  final FirebaseFirestore _firestore;

  /// Firestore caps a batch at 500 operations.
  static const _batchLimit = 400;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _progress(String uid) =>
      _userDoc(uid).collection('progress');

  /// Uploads everything not yet mirrored.
  Future<SyncOutcome> push({required String? uid}) async {
    if (uid == null) return SyncOutcome.notSignedIn;

    try {
      final pending = await _questions.unsyncedInteractions(limit: _batchLimit);
      if (pending.isEmpty) return SyncOutcome.nothingToDo;

      final batch = _firestore.batch();
      for (final row in pending) {
        batch.set(
          _progress(uid).doc(row.questionId),
          _toRemote(row),
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      // Only after the commit succeeds — a failed upload must be retried, not
      // silently marked done.
      await _questions.markSynced(pending.map((r) => r.questionId));
      return SyncOutcome.succeeded;
    } on FirebaseException catch (e) {
      debugPrint('Sync push failed: ${e.code} ${e.message}');
      return SyncOutcome.failed;
    } on Exception catch (e) {
      debugPrint('Sync push failed: $e');
      return SyncOutcome.failed;
    }
  }

  /// Pulls remote progress and merges it into the local database.
  Future<SyncOutcome> pull({required String? uid}) async {
    if (uid == null) return SyncOutcome.notSignedIn;

    try {
      final snapshot = await _progress(uid).get();
      if (snapshot.docs.isEmpty) return SyncOutcome.nothingToDo;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        await _questions.mergeRemoteInteraction(
          questionId: doc.id,
          timesSeen: (data['timesSeen'] as num?)?.toInt() ?? 0,
          revealed: data['revealed'] as bool? ?? false,
          completed: data['completed'] as bool? ?? false,
          saved: data['saved'] as bool? ?? false,
          savedAt: _toDate(data['savedAt']),
          lastSeenAt: _toDate(data['lastSeenAt']),
          lastAnswerCorrect: data['lastAnswerCorrect'] as bool?,
          reviewStage: (data['reviewStage'] as num?)?.toInt() ?? 0,
          reviewDueAt: _toDate(data['reviewDueAt']),
        );
      }
      return SyncOutcome.succeeded;
    } on FirebaseException catch (e) {
      debugPrint('Sync pull failed: ${e.code} ${e.message}');
      return SyncOutcome.failed;
    } on Exception catch (e) {
      debugPrint('Sync pull failed: $e');
      return SyncOutcome.failed;
    }
  }

  /// Stores the profile document and preferences.
  ///
  /// Only the Google fields needed to render the profile are written — never
  /// anything else from the account.
  Future<SyncOutcome> pushProfile({
    required String? uid,
    required String? displayName,
    required String? email,
    required String? photoUrl,
    required UserPreferences preferences,
  }) async {
    if (uid == null) return SyncOutcome.notSignedIn;

    try {
      await _userDoc(uid).set({
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'preferences': {
          'topics': preferences.topics.map((t) => t.id).toList(),
          'level': preferences.level.id,
          'goal': preferences.goal.id,
          'themeMode': preferences.themeMode.name,
          'aiGenerationEnabled': preferences.aiGenerationEnabled,
          'dailyReminderEnabled': preferences.dailyReminderEnabled,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SyncOutcome.succeeded;
    } on Exception catch (e) {
      debugPrint('Profile push failed: $e');
      return SyncOutcome.failed;
    }
  }

  /// Deletes the user's remote data.
  ///
  /// Firestore has no recursive delete from a client, so subcollections are
  /// removed explicitly. Missing this is the classic way "delete my account"
  /// leaves orphaned documents behind forever.
  Future<SyncOutcome> deleteRemoteData({required String? uid}) async {
    if (uid == null) return SyncOutcome.notSignedIn;

    try {
      // Loop rather than a single batch: a heavy user can exceed the 500-op
      // limit, and a partial delete is worse than a slow one.
      while (true) {
        final snapshot = await _progress(uid).limit(_batchLimit).get();
        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if (snapshot.docs.length < _batchLimit) break;
      }

      await _userDoc(uid).delete();
      return SyncOutcome.succeeded;
    } on Exception catch (e) {
      debugPrint('Remote delete failed: $e');
      return SyncOutcome.failed;
    }
  }

  static Map<String, dynamic> _toRemote(QuestionInteraction row) => {
    'questionId': row.questionId,
    'timesSeen': row.timesSeen,
    'revealed': row.revealed,
    'completed': row.completed,
    'skipped': row.skipped,
    'saved': row.saved,
    'savedAt': row.savedAt == null ? null : Timestamp.fromDate(row.savedAt!),
    'lastSeenAt': row.lastSeenAt == null
        ? null
        : Timestamp.fromDate(row.lastSeenAt!),
    'lastAnswerCorrect': row.lastAnswerCorrect,
    'reviewStage': row.reviewStage,
    'reviewDueAt': row.reviewDueAt == null
        ? null
        : Timestamp.fromDate(row.reviewDueAt!),
  };

  static DateTime? _toDate(Object? value) => switch (value) {
    final Timestamp t => t.toDate(),
    final String s => DateTime.tryParse(s),
    _ => null,
  };
}
