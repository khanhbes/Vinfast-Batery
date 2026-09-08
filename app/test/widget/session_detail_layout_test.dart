import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/confirm_session_soc_dialog.dart';
import 'package:vinfast_battery/core/widgets/adaptive_detail_rows.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/widgets/session_soc_summary.dart';

SmartChargingSession session({double? actual, double? estimated}) {
  final time = DateTime.utc(2026, 9, 8);
  return SmartChargingSession(
    sessionId: 'session-test',
    vehicleId: 'vehicle-test',
    state: ChargingSessionState.completed,
    strategy: ChargingStrategy.manualTimed,
    startSoc: 20,
    targetSoc: 80,
    actualEndSoc: actual,
    estimatedSoc: estimated,
    predictedMinutes: 60,
    predictionSource: 'manual',
    createdAt: time,
    updatedAt: time,
    hardDeadlineAt: time,
    aiStopAt: time,
    effectiveStopAt: time,
    absoluteSafetyStopAt: time,
    shadowMode: false,
    version: 1,
  );
}

void main() {
  testWidgets('SOC dialog rejects invalid values and accepts decimal comma', (
    tester,
  ) async {
    double? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<double>(
                  context: context,
                  builder: (_) => const ConfirmSessionSocDialog(),
                );
              },
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    for (final input in ['', 'NaN', '101', '-1']) {
      await tester.enterText(find.byType(TextField), input);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập mức pin từ 0 đến 100%.'), findsOneWidget);
      expect(result, isNull);
    }
    await tester.enterText(find.byType(TextField), '80,5');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    expect(result, 80.5);
    expect(find.byType(ConfirmSessionSocDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Session SOC and metadata $brightness / $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Column(
                    children: [
                      SessionSocSummary(session: session()),
                      const AdaptiveDetailRows(
                        rows: [
                          (
                            'Mã phiên',
                            'charging-session-with-a-very-long-identifier-2026-09-08',
                          ),
                          (
                            'Model AI',
                            'charging-time-production-model-v3-long-version',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Chưa có dữ liệu'), findsOneWidget);
        expect(find.text('80%'), findsNothing);
        expect(find.text('Mục tiêu đặt trước: 80%'), findsOneWidget);
        expect(find.byType(SelectableText), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Confirmed SOC takes precedence over estimate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSocSummary(session: session(actual: 65, estimated: 70)),
        ),
      ),
    );
    expect(find.text('65%'), findsOneWidget);
    expect(find.text('70%'), findsNothing);
    expect(find.text('Cuối phiên · đã xác nhận'), findsOneWidget);
  });
  testWidgets('Invalid confirmed SOC does not appear as measured data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSocSummary(
            session: session(actual: double.nan, estimated: 62),
          ),
        ),
      ),
    );
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('SOC ước tính'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });
}
