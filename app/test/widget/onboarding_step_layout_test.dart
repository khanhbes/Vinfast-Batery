import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/widgets/battery_bot_mascot.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/features/auth/onboarding_chat_screen.dart';

void main() {
  final spec = VinFastModelSpec.fromMap({
    'modelId': 'layout-test-model',
    'modelName': 'VinFast mẫu xe có tên đầy đủ và phiên bản dài',
    'nominalCapacityWh': 3500,
  });

  Widget fixture({
    required int step,
    required Brightness brightness,
    bool keyboard = false,
    bool reducedMotion = false,
    VoidCallback? onContinue,
    VoidCallback? onBack,
    Widget? content,
    bool forward = true,
  }) => MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.5),
        disableAnimations: reducedMotion,
        viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
      ),
      child: child!,
    ),
    home: OnboardingStepFrame(
      step: step,
      forward: forward,
      onBack: onBack,
      onContinue: onContinue,
      child: content ?? const Text('Nội dung thiết lập'),
    ),
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 412.0]) {
      for (final keyboard in [false, true]) {
        testWidgets(
          'nine onboarding frames $brightness ${width}dp keyboard=$keyboard',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 568));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            for (var step = 0; step < 9; step++) {
              await tester.pumpWidget(
                fixture(
                  step: step,
                  brightness: brightness,
                  keyboard: keyboard,
                  onContinue: () {},
                  onBack: () {},
                  content: step == 1
                      ? OnboardingVehicleChoice(
                          spec: spec,
                          selected: true,
                          onSelected: () {},
                        )
                      : const TextField(
                          decoration: InputDecoration(
                            labelText: 'Thông tin tùy chọn',
                            errorText:
                                'Thông tin chưa hợp lệ. Vui lòng kiểm tra và nhập lại.',
                            errorMaxLines: 3,
                          ),
                        ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.takeException(), isNull, reason: 'step $step');
              expect(
                find.byType(BatteryBotMascot),
                keyboard ? findsNothing : findsOneWidget,
              );
              if (!keyboard) {
                expect(
                  tester.getSize(find.byType(BatteryBotMascot)),
                  const Size(40, 40),
                );
              }
              final next = find.byType(FilledButton);
              expect(
                next.hitTestable(),
                findsOneWidget,
                reason: 'CTA step $step',
              );
              expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
              if (step > 0) {
                expect(
                  find.byTooltip('Quay lại bước trước').hitTestable(),
                  findsOneWidget,
                );
              }
              for (final text in tester.widgetList<Text>(find.byType(Text))) {
                expect(text.overflow, isNot(TextOverflow.ellipsis));
              }
              await tester.pumpWidget(const SizedBox());
            }
          },
        );
      }
    }
  }

  testWidgets('step metadata identifies only optional survey sections', (
    tester,
  ) async {
    expect(OnboardingStepCopy.steps.length, 9);
    expect(OnboardingStepCopy.steps[1].optional, isFalse);
    for (var step = 2; step <= 7; step++) {
      expect(OnboardingStepCopy.steps[step].optional, isTrue);
    }
    final welcome = OnboardingStepCopy.steps[0];
    expect(welcome.title, 'Thiết lập xe của bạn');
    expect(welcome.description, isNot(contains('bảo vệ')));
    await tester.pumpWidget(fixture(step: 1, brightness: Brightness.light));
    expect(find.text('Bước 2/9 · Bắt buộc'), findsOneWidget);
  });

  testWidgets('disabled Continue and horizontal gesture cannot advance', (
    tester,
  ) async {
    var advances = 0;
    await tester.pumpWidget(fixture(step: 1, brightness: Brightness.light));
    await tester.tap(find.byType(FilledButton));
    await tester.drag(find.text('Nội dung thiết lập'), const Offset(-280, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Bước 2/9 · Bắt buộc'), findsOneWidget);

    await tester.pumpWidget(
      fixture(
        step: 1,
        brightness: Brightness.light,
        onContinue: () => advances++,
      ),
    );
    await tester.drag(find.text('Nội dung thiết lập'), const Offset(-280, 0));
    await tester.pump();
    expect(advances, 0);
    await tester.tap(find.byType(FilledButton));
    expect(advances, 1);
  });

  testWidgets('step motion is 220ms and disabled by reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(step: 0, brightness: Brightness.dark));
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      const Duration(milliseconds: 220),
    );
    await tester.pumpWidget(
      fixture(step: 1, brightness: Brightness.dark, reducedMotion: true),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
      Duration.zero,
    );
    expect(find.text('Bước 2/9 · Bắt buộc'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vehicle choice wraps full name and exposes selection', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    var selections = 0;
    await tester.pumpWidget(
      fixture(
        step: 1,
        brightness: Brightness.light,
        content: OnboardingVehicleChoice(
          spec: spec,
          selected: true,
          onSelected: () => selections++,
        ),
      ),
    );
    expect(find.text(spec.modelName), findsOneWidget);
    final choiceSemantics = find.descendant(
      of: find.byType(OnboardingVehicleChoice),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true,
      ),
    );
    expect(choiceSemantics, findsOneWidget);
    await tester.ensureVisible(find.text(spec.modelName));
    await tester.tap(find.text(spec.modelName));
    expect(selections, 1);
    expect(tester.takeException(), isNull);
  });
}
