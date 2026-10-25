import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/adaptive_detail_rows.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/widgets/session_soc_summary.dart';

SmartChargingSession session({
  double? actual,
  double? estimated,
  double start = 20,
  double target = 80,
}) {
  final time = DateTime.utc(2026, 9, 8);
  return SmartChargingSession(
    sessionId: 'session-test',
    vehicleId: 'vehicle-test',
    state: ChargingSessionState.completed,
    strategy: ChargingStrategy.manualTimed,
    startSoc: start,
    targetSoc: target,
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
  testWidgets('A timed charge without a target shows no fake target', (
    tester,
  ) async {
    // QA 135: stored target = start % ("Mục tiêu đặt trước: 11%").
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionSocSummary(
            session: session(actual: 81, start: 11, target: 11),
          ),
        ),
      ),
    );
    expect(find.text('Không đặt mục tiêu'), findsOneWidget);
    expect(find.textContaining('Mục tiêu đặt trước'), findsNothing);
  });
}
