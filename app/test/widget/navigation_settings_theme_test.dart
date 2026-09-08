import 'package:flutter/material.dart';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/app_navigation_bar.dart';
import 'package:vinfast_battery/core/theme/cockpit_design_system.dart';

void main() {
  testWidgets('Navigation exposes actionable selected semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selectedIndex: 0,
            onSelected: (index) => selected = index,
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Lịch sử'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    expect(selected, 2);
    handle.dispose();
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Navigation equal targets / $brightness / $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                bottomNavigationBar: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: AppNavigationBar(
                    selectedIndex: selected,
                    onSelected: (index) => setState(() => selected = index),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sizes = [
          for (var i = 0; i < 4; i++)
            tester.getSize(find.byKey(ValueKey('navigation-destination-$i'))),
        ];
        for (final size in sizes) {
          expect(size.width, sizes.first.width);
          expect(size.height, sizes.first.height);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.text('Lịch sử'));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('Settings rows follow theme with long text / $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Column(
                  children: [
                    const CockpitSectionLabel('Thông báo và kết nối'),
                    CockpitSettingsRow(
                      icon: Icons.settings,
                      title: 'Smart Charger',
                      subtitle:
                          'Thiết lập kết nối bộ sạc và kiểm tra trạng thái xác minh trước khi điều khiển.',
                      onTap: () => taps++,
                    ),
                    const CockpitSettingsRow(
                      icon: Icons.lock,
                      title: 'Chức năng chưa khả dụng',
                      availability: SettingsItemAvailability.comingSoon,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Smart Charger')).style!.color,
        theme.colorScheme.onSurface,
      );
      await tester.tap(find.text('Smart Charger'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
