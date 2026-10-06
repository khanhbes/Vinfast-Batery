import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android native splash uses ONE LINE background and transparent icon',
    () {
      for (final qualifier in ['values', 'values-night']) {
        final colors = File(
          'android/app/src/main/res/$qualifier/colors.xml',
        ).readAsStringSync();
        expect(
          colors,
          contains('<color name="splash_background">#0B0F0E</color>'),
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
