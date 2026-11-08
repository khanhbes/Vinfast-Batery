import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/assistant_context_coordinator.dart';
import 'package:vinfast_battery/core/widgets/floating_battery_bot.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/features/settings/widgets/training_result_sheet.dart';

/// QA 149, found on the owner's phone: the tucked-in Pinova Bot button sat
/// over tiles and history cards while scrolling, the "Đang sạc" pill covered
/// the Overview's middle card, and the trip card read "đã huấn luyện từ 77
/// chuyến" beside "Chưa đủ dữ liệu để đánh giá".
void main() {
  testWidgets('the bot steps off the screen while the page scrolls down', (
    tester,
  ) async {
    // The provider disposes it with the scope.
    final bot = AssistantContextCoordinator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantContextCoordinatorProvider.overrideWith((_) => bot),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Stack(children: [FloatingBatteryBot()])),
        ),
      ),
    );
    final width = tester.getSize(find.byType(Scaffold)).width;
    double left() => tester.getTopLeft(find.byTooltip('Mở Pinova Bot')).dx;

    bot.setDocked(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(left(), lessThan(width), reason: 'tucked in, still reachable');

    bot.setScrollingAway(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(left(), greaterThanOrEqualTo(width), reason: 'off the screen');
    Finder hiddenBy(bool Function(Widget w) test) => find.ancestor(
      of: find.byTooltip('Mở Pinova Bot'),
      matching: find.byWidgetPredicate(test),
    );
    expect(
      hiddenBy((w) => w is IgnorePointer && w.ignoring),
      findsOneWidget,
      reason: 'no taps land on a hidden button',
    );
    expect(
      hiddenBy((w) => w is ExcludeSemantics && w.excluding),
      findsOneWidget,
      reason: 'TalkBack does not read a hidden button',
    );

    bot.setScrollingAway(false); // the scroll stopped
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(left(), lessThan(width));
    expect(bot.isDocked, isTrue);
  });

  test('the charging pill has its own strip above the tabs', () {
    final shell = File('lib/navigation/app_navigation.dart').readAsStringSync();
    final body = shell.indexOf('body: Stack(');
    final bar = shell.indexOf('bottomNavigationBar: Column(');
    final pill = shell.indexOf('GlobalChargingPill()');
    expect(bar, greaterThan(body));
    expect(pill, greaterThan(bar), reason: 'not floating over the page');
  });

  group('training verdict beside a learned model', () {
    TrainingReport report(String decision) =>
        TrainingReport.fromJson({'decision': decision, 'mode': 'finetune'})!;

    test('a model in use is not called "no data"', () {
      expect(
        TrainingResultSheet.verdict(report('no_data'), trained: 77),
        'Chưa có dữ liệu mới để kiểm tra nên vẫn dùng bản đã học.',
      );
      expect(
        TrainingResultSheet.verdict(report('promoted'), trained: 77),
        startsWith('Đã dùng bản mới.'),
      );
    });

    test('nothing learned yet still says so', () {
      expect(
        TrainingResultSheet.verdict(report('no_data')),
        'Chưa đủ dữ liệu để đánh giá.',
      );
    });
  });
}
