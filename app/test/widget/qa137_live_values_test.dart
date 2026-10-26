import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/providers/app_providers.dart';
import 'package:vinfast_battery/core/providers/entitlement_provider.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/theme/plan_style.dart';
import 'package:vinfast_battery/core/utils/number_text.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/repositories/charge_log_repository.dart';
import 'package:vinfast_battery/features/premium/premium_screen.dart';

/// QA 137: a % / ODO saved anywhere reaches every screen at once (the
/// vehicle was a one-shot read), money reads "249.000đ", no "~", and the
/// Ultra plan on the Premium page always moves (slowly).
class _Repo implements ChargeLogRepository {
  final changes = StreamController<VehicleModel?>.broadcast();
  int listReads = 0;

  @override
  Stream<VehicleModel?> watchVehicle(String vehicleId) => changes.stream;

  @override
  Future<List<VehicleModel>> getAllVehicles() async {
    listReads++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VehicleModel _car({required int soc, required int odo}) => VehicleModel(
  vehicleId: 'car',
  vehicleName: 'VinFast Feliz',
  ownerUid: 'u1',
  currentOdo: odo,
  currentBattery: soc,
);

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

/// Reads the vehicle like the Overview, Settings and Charge tab do.
class _Readout extends ConsumerWidget {
  const _Readout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleContextProvider).vehicle;
    return Text(
      vehicle == null
          ? 'chưa có xe'
          : '${vehicle.currentBattery}% · ${groupThousands(vehicle.currentOdo)} km',
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('money reads 249.000đ; other numbers keep their grouping', () {
    expect(formatVnd(249000), '249.000đ');
    expect(formatVnd(20750), '20.750đ');
    expect(formatVnd(1200500), '1.200.500đ');
    expect(formatVnd(800), '800đ');
    expect(formatVnd(0), '0đ');
    expect(groupThousands(4818), isNot(contains('.')), reason: 'ODO not money');
  });

  testWidgets('a reading saved anywhere updates every screen at once', (
    tester,
  ) async {
    final repo = _Repo();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chargeLogRepositoryProvider.overrideWithValue(repo),
          selectedVehicleIdProvider.overrideWith((ref) => 'car'),
        ],
        child: const MaterialApp(home: Scaffold(body: _Readout())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_Readout)),
    );
    // The garage/switcher list is open too.
    container.listen(allVehiclesProvider, (_, _) {});
    await tester.pump();
    repo.changes.add(_car(soc: 31, odo: 4818));
    await tester.pump();
    await tester.pump();
    expect(find.text('31% · ${groupThousands(4818)} km'), findsOneWidget);
    final listReads = repo.listReads;
    // The owner saves 80 % / 4 830 km (reading, confirmed charge, bot or
    // the server after a charge): no restart, no pull-to-refresh.
    repo.changes.add(_car(soc: 80, odo: 4830));
    await tester.pump();
    await tester.pump();
    expect(find.text('80% · ${groupThousands(4830)} km'), findsOneWidget);
    expect(repo.listReads, greaterThan(listReads), reason: 'list refreshed');
  });

  testWidgets('Ultra on the Premium page moves for every plan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<bool> running({required bool reduceMotion}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            entitlementProvider.overrideWith(() => _Plan(PlanTier.free)),
          ],
          child: MaterialApp(
            theme: LuxeTheme.data(),
            builder: (context, page) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: page!,
            ),
            home: const PremiumScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final pill = tester.element(
        find.byKey(const ValueKey('premium-tier-ultra')),
      );
      return PlanMotion.of(pill).running;
    }

    expect(await running(reduceMotion: false), isTrue);
    // The chosen Ultra pill shows its aurora at full strength while it flows
    // (an implicit animation used to restart on every colour tick and stay
    // dark on a real phone).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final fade = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('premium-tier-ultra')),
        matching: find.byType(Opacity),
      ),
    );
    expect(fade.opacity, 1.0);
    expect(await running(reduceMotion: true), isFalse);
    // The price line says "khoảng", never "~".
    expect(find.textContaining('khoảng 37.417đ mỗi tháng'), findsOneWidget);
    expect(find.textContaining('~'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
