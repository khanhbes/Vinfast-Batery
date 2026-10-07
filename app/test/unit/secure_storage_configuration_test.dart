import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/account_secure_storage.dart';

void main() {
  test('account store matches existing Android encryption without reset', () {
    final options = accountSecureStorage.aOptions.toMap();
    expect(options['encryptedSharedPreferences'], 'true');
    expect(options['resetOnError'], 'false');
    // Keep the existing namespace so already-migrated history remains readable.
    expect(options['sharedPreferencesName'], isEmpty);
    expect(options['preferencesKeyPrefix'], isEmpty);
  });

  test('production does not mix bare legacy stores with encrypted stores', () {
    final bareStore = RegExp(r'FlutterSecureStorage\(\s*\)');
    final inconsistent = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => bareStore.hasMatch(file.readAsStringSync()))
        .map((file) => file.path)
        .toList();
    expect(inconsistent, isEmpty);
  });
}
