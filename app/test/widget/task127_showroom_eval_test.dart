import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/vehicle_learning_status.dart';
import 'package:vinfast_battery/features/settings/widgets/training_result_sheet.dart';

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
}
