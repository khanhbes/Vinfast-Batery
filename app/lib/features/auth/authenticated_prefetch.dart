import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/models/onboarding_draft.dart';

/// QA 162: the signed-in app needs the account's profile and its local
/// survey draft before it can pick a screen. They used to be read only once
/// the splash had finished, so the brand held still for another second or
/// more. [AuthGate] starts both reads as soon as the session is restored,
/// while the mark is still being drawn; the signed-in root takes them once.
class AuthenticatedPrefetch {
  AuthenticatedPrefetch._();

  static const profileTimeout = Duration(seconds: 12);

  static String? _uid;
  static Future<DocumentSnapshot<Map<String, dynamic>>>? _profile;
  static Future<OnboardingDraft?>? _draft;

  /// Test hooks: what the reads are.
  static Future<DocumentSnapshot<Map<String, dynamic>>> Function(String uid)
  readProfile = (uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get()
      .timeout(profileTimeout);
  static Future<OnboardingDraft?> Function(String uid) readDraft = (uid) =>
      OnboardingDraftRepository().load(uid);

  /// Starts both reads for [uid] (once per account until taken).
  static void start(String? uid) {
    if (uid == null || uid.isEmpty || _uid == uid) return;
    _uid = uid;
    try {
      _profile = readProfile(uid);
      _draft = readDraft(uid);
      // Errors are the root's to handle when it takes them; never unhandled.
      _profile!.ignore();
      _draft!.ignore();
    } on Object {
      clear();
    }
  }

  /// The reads started for [uid], once; null when none (another account,
  /// already taken, or never started).
  static ({
    Future<DocumentSnapshot<Map<String, dynamic>>> profile,
    Future<OnboardingDraft?> draft,
  })?
  take(String uid) {
    final profile = _profile, draft = _draft;
    final match = _uid == uid && profile != null && draft != null;
    clear();
    return match ? (profile: profile, draft: draft) : null;
  }

  static void clear() {
    _uid = null;
    _profile = null;
    _draft = null;
  }
}
