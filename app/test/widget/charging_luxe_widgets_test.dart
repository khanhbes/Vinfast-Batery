import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/ai/widgets/recent_sessions_section_v2.dart';
import 'package:vinfast_battery/features/ai/widgets/timed_charging_section_v2.dart';

SmartChargingSession session(String state) => SmartChargingSession.fromJson({
  'session_id': 'session-$state',
  'vehicle_id': 'VF-001',
  'state': state,
  'strategy': 'smart_combined',
  'start_soc': 20,
  'target_soc': 80,
  'predicted_minutes': 60,
  'prediction_source': 'ai_model',
  'created_at': '2030-01-01T03:00:00Z',
  'updated_at': '2030-01-01T03:30:00Z',
  'started_at': '2030-01-01T03:00:00Z',
  'ai_stop_at': '2030-01-01T04:00:00Z',
  'hard_deadline_at': '2030-01-01T05:00:00Z',
  'effective_stop_at': '2030-01-01T04:00:00Z',
  'absolute_safety_stop_at': '2030-01-01T07:00:00Z',
  'estimated_soc': 25,
  'relay_verified': true,
  'energy_used_wh': 120,
  'version': 2,
});

void main() {
  testWidgets('history labels each session state honestly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecentSessionsSectionV2(
              sessions: [
                session('active'),
                session('completed'),
                session('cancelled'),
                session('interrupted'),
              ],
              onViewAll: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    // An active session was previously shown as "Đã dừng".
    expect(find.text('Đang sạc'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(find.text('Đã dừng'), findsOneWidget);
    expect(find.text('Gián đoạn'), findsOneWidget);
  });

  // QA 140: the end is a clock time; the length below follows it.
  testWidgets('timed end reads as a clock time and a length', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimedChargingSectionV2(
              onStart: (_) async {},
              onOff: () {},
              readyForControl: true,
              clock: () => DateTime(2026, 10, 29, 7),
            ),
          ),
        ),
      ),
    );
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('Sạc 2 giờ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timed-end-plus')));
    await tester.pump();
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('Sạc 2 giờ 15 phút'), findsOneWidget);
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const ValueKey('timed-end-minus')));
      await tester.pump();
    }
    // Never sooner than 5 minutes from now.
    expect(find.text('07:05'), findsOneWidget);
    expect(find.text('Sạc 5 phút'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('an end time already passed today means tomorrow', () {
    final now = DateTime(2026, 10, 29, 23, 40);
    expect(
      TimedChargingSectionV2.stopAtFor(const TimeOfDay(hour: 1, minute: 0), now),
      DateTime(2026, 10, 30, 1),
    );
    expect(
      TimedChargingSectionV2.endAfter(const Duration(minutes: 30), now),
      const TimeOfDay(hour: 0, minute: 10),
    );
    expect(
      TimedChargingSectionV2.endAfter(
        const Duration(minutes: 30),
        DateTime(2026, 10, 29, 7, 2, 10),
      ),
      const TimeOfDay(hour: 7, minute: 35),
    );
  });
}
