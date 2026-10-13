import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/bootstrap_splash.dart';

void main() {
  test(
    'Android native splash matches the Flutter splash background',
    () {
      for (final qualifier in ['values', 'values-night']) {
        final colors = File(
          'android/app/src/main/res/$qualifier/colors.xml',
        ).readAsStringSync();
        // The first native frame must match the Flutter splash exactly.
        final hex = BootstrapSplash.background
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2)
            .toUpperCase();
        expect(
          colors,
          contains('<color name="splash_background">#$hex</color>'),
        );
      }
      for (final qualifier in ['drawable', 'drawable-v21']) {
        final launch = File(
          'android/app/src/main/res/$qualifier/launch_background.xml',
        ).readAsStringSync();
        expect(launch, isNot(contains('bitmap')));
        expect(launch, contains('@color/splash_background'));
      }
      for (final qualifier in ['values-v31', 'values-night-v31']) {
        final styles = File(
          'android/app/src/main/res/$qualifier/styles.xml',
        ).readAsStringSync();
        expect(styles, contains('@drawable/splash_empty'));
        expect(styles, isNot(contains('@mipmap/ic_launcher')));
      }
      final config = File(
        'pubspec.yaml',
      ).readAsStringSync().split('flutter_native_splash:').last;
      expect(config, contains('android: false'));
      expect(config, isNot(contains('image: assets/icons/app_icon.png')));
    },
  );
}
