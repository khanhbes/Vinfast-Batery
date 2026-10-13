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

  testWidgets('timed label reads in hours, not minutes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimedChargingSectionV2(
              onStart: (_) async {},
              onOff: () {},
              readyForControl: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sạc 2 giờ'), findsOneWidget);
    expect(find.text('Sạc 120 phút'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('timed-preset-30')));
    await tester.pump();
    expect(find.text('Sạc 30 phút'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
