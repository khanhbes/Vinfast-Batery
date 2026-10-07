import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Match the Android store already used by session, onboarding and Shelly.
/// Mixing the legacy and encrypted stores lets the plugin migrate keys away
/// from readers of the legacy store. Never reset the store on a read error.
const accountSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
