import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/data/models/vehicle_showroom.dart';
import 'package:vinfast_battery/features/home/widgets/vehicle_showroom.dart';
import 'package:vinfast_battery/features/settings/widgets/training_result_sheet.dart';

// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, dynamic> _tripReport({
  String decision = 'promoted',
  bool saw = true,
}) => {
  'decision': decision,
  'mode': 'finetune',
  'used': 77,
  'beforeMae': 0.66,
  'afterMae': 0.73,
  'evaluation': {
    'method': 'kiểm tra chéo 5 phần theo thời gian',
    'testSet': saw ? 'all' : 'new',
    'currentSawTest': saw,
    'current': {
      'n': 77,
      'mae': 0.66,
      'bias': -0.09,
      'within1': 0.805,
      'within2': 0.961,
    },
    'new': {
      'n': 77,
      'mae': 0.73,
      'bias': -0.08,
      'within1': 0.779,
      'within2': 0.961,
    },
    'flat': {
      'n': 77,
      'mae': 0.86,
      'bias': 0.01,
      'within1': 0.701,
      'within2': 0.909,
    },
    'examples': [
      for (var i = 0; i < 8; i++)
        {
          'at': '2026-04-2${i % 9}',
          'km': 5.0 + i,
          'speedKmh': 20,
          'actual': 4.0 + i,
          'current': 4.2 + i,
          'new': 3.9 + i,
          'flat': 4.5 + i,
        },
    ],
  },
};

void main() {
  setUp(() => showroomImageProvider = (_) => MemoryImage(_png));

  group('training verdict', () {
    test('a worse new model is kept out and says so', () {
      final report = TrainingReport.fromJson(
        _tripReport(decision: 'rejected_worse'),
      )!;
      expect(TrainingResultSheet.verdict(report), contains('chưa tốt hơn'));
      expect(
        TrainingResultSheet.verdict(report),
        contains('giữ bản đang dùng'),
      );
    });

    test('a better new model reports the reduction', () {
      final raw = _tripReport();
      final evaluation = raw['evaluation'] as Map<String, dynamic>;
      evaluation['new'] = {
        'n': 10,
        'mae': 0.5,
        'bias': 0,
        'within1': 0.9,
        'within2': 1,
      };
      final report = TrainingReport.fromJson(raw)!;
      expect(TrainingResultSheet.verdict(report), contains('Bản mới tốt hơn'));
      expect(TrainingResultSheet.verdict(report), contains('−24%'));
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('result sheet fits 320dp at text x$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = TrainingReport.fromJson(_tripReport())!;
      await tester.pumpWidget(
        MaterialApp(
          theme: LuxeTheme.data(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: TrainingResultSheet(
                title: 'Hao pin theo lộ trình',
                report: report,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('training-verdict')), findsOneWidget);
      expect(find.text('km/1% cố định'), findsOneWidget);
      expect(find.textContaining('lạc quan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('THỰC TẾ SO VỚI DỰ ĐOÁN (% HAO)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('the owner Feliz render ships with the app', () {
    final only = BundledShowroom.withBundled(null, modelId: 'feliz')!;
    expect(only.defaultColor.id, BundledShowroom.felizMint.id);
    expect(only.primary.mediumUrl, startsWith('asset:'));
    expect(BundledShowroom.withBundled(null, modelId: 'evo200'), isNull);
    final spin = VehicleShowroomData(
      colors: [
        ShowroomColor(
          id: 'do',
          name: 'Đỏ',
          swatch: const Color(0xFFC8102E),
          angles: [
            for (var i = 0; i < 12; i++)
              ShowroomImage(
                thumbnailUrl: 'https://x/$i.webp',
                mediumUrl: 'https://x/$i.webp',
                heroUrl: 'https://x/$i.webp',
              ),
          ],
        ),
      ],
      defaultColorId: 'do',
    );
    final merged = BundledShowroom.withBundled(spin, name: 'VinFast Feliz')!;
    expect(merged.colors.length, 2);
    expect(merged.defaultColorId, 'do', reason: 'a real 360° set wins');
  });

  testWidgets('one photo turns round and settles front or back', (
    tester,
  ) async {
    final key = GlobalKey<VehicleShowroomViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 300,
              child: VehicleShowroomView(
                key: key,
                color: BundledShowroom.felizMint,
                orbit: true,
                fallback: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kéo ngang để xoay quanh xe'), findsOneWidget);
    final stage = find.byType(VehicleShowroomView);
    await tester.timedDrag(
      stage,
      const Offset(-200, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    final settled = key.currentState!.orbitDegrees;
    expect(settled.abs(), closeTo(180, 0.01), reason: 'a long drag turns it');
    await tester.timedDrag(
      stage,
      const Offset(30, 0),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.orbitDegrees.abs() % 180, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });
}
