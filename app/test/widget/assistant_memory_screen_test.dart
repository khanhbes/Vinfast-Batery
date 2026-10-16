import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/luxe_settings.dart';
import 'package:vinfast_battery/features/ai/services/assistant_api.dart';
import 'package:vinfast_battery/features/settings/assistant_memory_screen.dart';

class _Api extends AssistantApi {
  bool learning = true;
  final facts = <AssistantFact>[
    const AssistantFact(
      id: 'f1',
      text: 'Đi làm khoảng 12 km mỗi ngày',
      category: 'habit',
    ),
    const AssistantFact(
      id: 'f2',
      text: 'Thích sạc buổi tối sau 21 giờ để tránh giờ cao điểm',
      category: 'preference',
    ),
  ];

  @override
  Future<AssistantMemorySnapshot> memory() async => AssistantMemorySnapshot(
    learningEnabled: learning,
    facts: List.of(facts),
    usedToday: 3,
    dailyLimit: 50,
  );

  @override
  Future<void> forget(String id) async => facts.removeWhere((f) => f.id == id);

  @override
  Future<bool> setLearning(bool enabled) async => learning = enabled;
}

Future<_Api> _pump(WidgetTester tester, double scale) async {
  await tester.binding.setSurfaceSize(const Size(320, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = _Api();
  await tester.pumpWidget(
    MaterialApp(
      theme: LuxeTheme.data(),
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: page!,
      ),
      home: AssistantMemoryScreen(api: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  return api;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('memory screen fits 320dp at text x$scale', (tester) async {
      await _pump(tester, scale);
      expect(find.text('BatteryBot đang nhớ gì'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('3/50'), 200);
      expect(find.textContaining('3/50'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Đi làm khoảng 12 km mỗi ngày'),
        200,
      );
      expect(find.text('Đi làm khoảng 12 km mỗi ngày'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('forget one fact and turn learning off', (tester) async {
    final api = await _pump(tester, 1);
    await tester.scrollUntilVisible(
      find.text('Đi làm khoảng 12 km mỗi ngày'),
      200,
    );
    await tester.ensureVisible(find.byTooltip('Quên điều này').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Quên điều này').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(api.facts, hasLength(1));
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(LuxeSwitch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(api.learning, isFalse);
    expect(find.textContaining('Đang tắt'), findsOneWidget);
  });
}
