// Generated-compatible Firebase configuration for the shared vinfast-873db project.
// Re-run `flutterfire configure` on a workstation with Firebase CLI credentials when
// adding a new iOS app; the values below are safe client identifiers, not secrets.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('VinFast Battery does not support Firebase Web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is not configured for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAKoNr2iPZi2XB0l_JaGhTkM2hsitwqyKE',
    appId: '1:450938791386:android:fde2bf0210038fa32dcce3',
    messagingSenderId: '450938791386',
    projectId: 'vinfast-873db',
    storageBucket: 'vinfast-873db.firebasestorage.app',
  );

  // The iOS app must be registered in Firebase Console before TestFlight.
  // Replace the placeholder appId/apiKey with the values emitted by
  // `flutterfire configure --platforms=ios`.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAKoNr2iPZi2XB0l_JaGhTkM2hsitwqyKE',
    appId: '1:450938791386:ios:vinfastbattery',
    messagingSenderId: '450938791386',
    projectId: 'vinfast-873db',
    storageBucket: 'vinfast-873db.firebasestorage.app',
    iosBundleId: 'com.khanhbes.vinfastbattery',
  );
}
