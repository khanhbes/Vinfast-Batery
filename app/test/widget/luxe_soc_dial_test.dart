import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/features/ai/widgets/luxe_soc_dial.dart';

void main() {
  double? current;
  double? target;

  Widget host({double cur = 20, double tgt = 50, bool inList = false}) {
    final dial = SizedBox(
      width: 340,
      child: LuxeSocDial(
        current: cur,
        target: tgt,
        onCurrentChanged: (v) => current = v,
        onTargetChanged: (v) => target = v,
      ),
    );
    return MaterialApp(
      home: Scaffold(
        body: inList
            ? ListView(
                children: [
                  const SizedBox(height: 40),
                  Center(child: dial),
                  const SizedBox(height: 1200),
                ],
              )
            : Center(child: dial),
      ),
    );
  }

  setUp(() {
    current = null;
    target = null;
  });

  // Knob centre at [pct] on the 270° dial (radius = 0.39 × 340).
  Offset knob(WidgetTester tester, double pct) {
    final c = tester.getCenter(find.byType(LuxeSocDial));
    const r = 0.39 * 340;
    final a = math.pi * 0.75 + math.pi * 1.5 * pct / 100;
    return c + Offset(r * math.cos(a), r * math.sin(a));
  }

  testWidgets('dragging along the ring moves the emerald knob', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 2));
    final g = await tester.startGesture(knob(tester, 50));
    await g.moveBy(const Offset(10, 0));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();
    expect(target, isNotNull);
    expect(target!, greaterThan(50));
    expect(current, isNull);
  });

  testWidgets('current knob cannot pass the target', (tester) async {
    await tester.pumpWidget(host(cur: 45, tgt: 50));
    await tester.pump(const Duration(seconds: 2));
    // Current (45%) sits just left of the top; drag it far clockwise.
    final g = await tester.startGesture(knob(tester, 45));
    await g.moveBy(const Offset(10, -2));
    await g.moveBy(const Offset(120, 40));
    await g.up();
    await tester.pump();
    if (current != null) expect(current!, lessThanOrEqualTo(49));
  });

  testWidgets('a vertical swipe on the top knob scrolls the page', (
    tester,
  ) async {
    await tester.pumpWidget(host(inList: true));
    await tester.pump(const Duration(seconds: 2));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    await tester.dragFrom(knob(tester, 50), const Offset(0, -200));
    await tester.pump();
    expect(position.pixels, greaterThan(100));
    expect(target, isNull);
  });

  testWidgets('screen readers can step both levels', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 2));
    SemanticsNode slider(String label) => tester.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      ),
    );
    final t = slider('Mục tiêu sạc');
    t.owner!.performAction(t.id, SemanticsAction.increase);
    await tester.pump();
    expect(target, 51);
    final c = slider('Mức pin hiện tại');
    c.owner!.performAction(c.id, SemanticsAction.decrease);
    await tester.pump();
    expect(current, 19);
    handle.dispose();
  });
}
