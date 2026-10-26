import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/services/app_update_service.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/luxe_submit_button.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/personal_charging_profile.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/features/more/more_screen.dart';
import 'package:vinfast_battery/features/premium/premium_gate.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';
import 'package:vinfast_battery/features/settings/delete_account_sheet.dart';
import 'package:vinfast_battery/features/settings/personal_ai_settings_screen.dart';

/// QA 138 (review 26/10/2026): the High findings, fixed.
/// QA-02 the owner's AI data (switch, delete) is open on every plan, only
/// training is Ultra; QA-03 the Premium page and its sheets promise only
/// what exists; QA-04 the owner deletes the account in the app; QA-05 the
/// store build updates through the stores and asks for no unused
/// permission.
class _Plan extends EntitlementNotifier {
  _Plan(this.tier);
  final PlanTier tier;

  @override
  Entitlement build() => Entitlement.fromMap({
    'tier': tier.id,
    'status': tier == PlanTier.free ? 'none' : 'active',
    'trialAvailable': tier == PlanTier.free,
    'features': {
      for (final f in PremiumFeature.values) f.id: tier.covers(f.tier),
    },
    'enforced': true,
  });

  @override
  Future<void> refresh() async {}
}

class _Learning implements ServerSmartChargerService {
  final trained = <String>[];

  @override
  Future<PersonalChargingProfile> getPersonalProfile(String vehicleId) async =>
      PersonalChargingProfile.fromJson({
        'vehicleId': vehicleId,
        'consentEnabled': true,
      });

  @override
  Future<VehicleLearningStatus?> learningStatus(String vehicleId) async =>
      VehicleLearningStatus.fromJson({
        'vehicleId': 'car',
        'consentEnabled': true,
        'charge': {
          'pending': 3,
          'required': 3,
          'ready': true,
          'trained': 2,
          'whPerPct': 26.15,
          'powerW': 437,
        },
        'trip': {
          'pending': 0,
          'required': 10,
          'ready': false,
          'trained': 0,
          'kmPerPct': 1.2,
          'sources': {'csv': 0, 'trip': 0, 'odo_segment': 0},
          'model': {'refPctPerKm': 0.735, 'source': 'catalog'},
        },
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, {PlanTier tier = PlanTier.free, double scale = 1}) =>
    ProviderScope(
      overrides: [entitlementProvider.overrideWith(() => _Plan(tier))],
      child: MaterialApp(
        theme: LuxeTheme.data(),
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: page!,
        ),
        home: child,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder target) => tester
    .scrollUntilVisible(target, 150, scrollable: find.byType(Scrollable).first);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('QA-02 AI cá nhân', () {
    for (final scale in const [1.0, 2.0]) {
      testWidgets(
        'Free sees and controls the data, training is Ultra x$scale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _app(
              PersonalAiSettingsScreen(vehicleId: 'car', service: _Learning()),
              scale: scale,
            ),
          );
          await _settle(tester);
          expect(find.byType(PremiumScreen), findsNothing);
          await _scrollTo(
            tester,
            find.byKey(const ValueKey('learning-train-ultra')),
          );
          final train = find.byKey(const ValueKey('train-lần sạc'));
          await _scrollTo(tester, train);
          expect(tester.widget<ButtonStyleButton>(train).onPressed, isNull);
          await _scrollTo(tester, find.text('Cho phép AI học từ dữ liệu xe'));
          await _scrollTo(tester, find.text('Xóa model & dữ liệu cá nhân'));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Ultra trains, without the plan notice', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          PersonalAiSettingsScreen(vehicleId: 'car', service: _Learning()),
          tier: PlanTier.ultra,
        ),
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('learning-train-ultra')), findsNothing);
      final train = find.byKey(const ValueKey('train-lần sạc'));
      await _scrollTo(tester, train);
      expect(tester.widget<ButtonStyleButton>(train).onPressed, isNotNull);
    });

    testWidgets('the Settings row is open on Free', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(const Scaffold(body: MoreScreen())));
      await _settle(tester);
      expect(find.byKey(const ValueKey('more-personal-ai')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('premium-locked-learning_train')),
        findsNothing,
      );
      // Night charging stays an Ultra entry.
      expect(
        find.byKey(const ValueKey('premium-locked-night_charging')),
        findsOneWidget,
      );
    });
  });

  group('QA-03 Premium promises only what exists', () {
    testWidgets('no monthly cost or sharing as Ultra; 10 vehicles', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(const PremiumScreen()));
      await _settle(tester);
      expect(
        find.text('Tối đa 10 xe, Pinova Bot 100 tin mỗi ngày.'),
        findsOneWidget,
      );
      final compare = find.byKey(const ValueKey('premium-compare-toggle'));
      await _scrollTo(tester, compare);
      await tester.tap(compare);
      await _settle(tester);
      expect(find.textContaining('chia sẻ xe'), findsNothing);
      expect(find.textContaining('Chi phí theo tháng'), findsNothing);
      expect(find.textContaining('chi phí theo tháng'), findsNothing);
      expect(find.text('AI cá nhân (huấn luyện)'), findsOneWidget);
      expect(find.text('Nhiều'), findsNothing);
    });

    testWidgets('the vehicle-limit sheet says Ultra has 10', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PremiumGate.showVehicleLimit(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.textContaining('Ultra tối đa 10 xe'), findsOneWidget);
      expect(find.textContaining('không giới hạn'), findsNothing);
    });
  });

  group('QA-04 delete the account in the app', () {
    Future<void> fill(WidgetTester tester, {String confirm = 'XÓA'}) async {
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-password')),
        'secret-1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-confirm')),
        confirm,
      );
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.byKey(const ValueKey('delete-account-submit'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    LuxeSubmitButton button(WidgetTester tester) =>
        tester.widget(find.byKey(const ValueKey('delete-account-submit')));

    for (final scale in const [1.0, 2.0]) {
      testWidgets('needs the password and XÓA; fits 320 dp x$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _app(const Scaffold(body: DeleteAccountSheet()), scale: scale),
        );
        await tester.pump();
        expect(button(tester).onPressed, isNull);
        await fill(tester, confirm: 'xoa');
        expect(button(tester).onPressed, isNotNull, reason: 'XOA works too');
        await fill(tester, confirm: 'XO');
        expect(button(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a wrong password never reaches the server', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: DeleteAccountSheet(
              reauthenticate: (_) async => 'Mật khẩu chưa đúng.',
              deleteAccount: () async {
                deleted++;
                return {'success': true};
              },
              afterDelete: () async {},
            ),
          ),
        ),
      );
      await fill(tester);
      await submit(tester);
      expect(find.text('Mật khẩu chưa đúng.'), findsOneWidget);
      expect(deleted, 0);
    });

    testWidgets('the server refusal is shown (charging now)', (tester) async {
      var left = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: DeleteAccountSheet(
              reauthenticate: (_) async => null,
              deleteAccount: () async => {
                'success': false,
                'code': 'activeSmartCharge',
                'userMessage':
                    'Đang có phiên sạc. Hãy dừng sạc rồi xóa tài khoản.',
              },
              afterDelete: () async => left++,
            ),
          ),
        ),
      );
      await fill(tester);
      await submit(tester);
      expect(
        find.text('Đang có phiên sạc. Hãy dừng sạc rồi xóa tài khoản.'),
        findsOneWidget,
      );
      expect(left, 0);
    });

    testWidgets('success signs out once', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: DeleteAccountSheet(
              reauthenticate: (password) async {
                calls.add('reauth:$password');
                return null;
              },
              deleteAccount: () async {
                calls.add('delete');
                return {'success': true};
              },
              afterDelete: () async => calls.add('leave'),
            ),
          ),
        ),
      );
      await fill(tester);
      await submit(tester);
      expect(calls, ['reauth:secret-1', 'delete', 'leave']);
    });
  });

  group('QA-05 store build', () {
    test('updates open Google Play / the App Store, never an APK', () {
      expect(
        AppUpdateService.storeUrlFor(const {}, ios: false),
        'https://play.google.com/store/apps/details?id=com.bes.vinbatery',
      );
      expect(
        AppUpdateService.storeUrlFor(const {
          'androidStoreUrl': 'market://details?id=com.bes.vinbatery',
        }, ios: false),
        'market://details?id=com.bes.vinbatery',
      );
      expect(
        AppUpdateService.storeUrlFor(const {
          'androidStoreUrl': 'http://example.com/pinova.apk',
        }, ios: false),
        startsWith('https://play.google.com/'),
        reason: 'plain http and APK links are ignored',
      );
      expect(AppUpdateService.storeUrlFor(const {}, ios: true), '');
      final source = File(
        'lib/core/services/app_update_service.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(contains('application/vnd.android.package-archive')),
      );
    });

    test('no unused permission or old name reaches the stores', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      for (final gone in [
        'REQUEST_INSTALL_PACKAGES',
        'FOREGROUND_SERVICE_LOCATION',
        'FOREGROUND_SERVICE_DATA_SYNC',
        'flutter_background_service',
      ]) {
        expect(manifest, isNot(contains(gone)), reason: gone);
      }
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.RECORD_AUDIO" '
          'tools:node="remove"/>',
        ),
      );
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, isNot(contains('VinFast Battery')));
      expect(
        plist,
        isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
      );
      expect(plist, isNot(contains('<string>location</string>')));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('open_filex')));
      expect(pubspec, isNot(contains('flutter_background_service')));
    });
  });
}
