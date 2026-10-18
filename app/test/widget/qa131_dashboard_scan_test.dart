import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/services/dashboard_reader.dart';
import 'package:vinfast_battery/features/ai/dashboard_scan_screen.dart';
import 'package:vinfast_battery/features/ai/widgets/battery_reading_sheet.dart';

/// QA 131: the live dashboard scanner (panel, no-camera fallback) and the
/// sheet it fills, at 320 dp with text ×1 and ×2.
Widget _app(Widget home, double scale) => MaterialApp(
  theme: LuxeTheme.data(),
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: page!,
  ),
  home: home,
);

class _Opener extends StatefulWidget {
  const _Opener(this.open);

  final Future<Object?> Function(BuildContext context) open;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  String _result = 'none';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          key: const ValueKey('open'),
          onPressed: () async {
            final value = await widget.open(context);
            setState(() => _result = '$value');
          },
          child: const Text('open'),
        ),
        Text('result: $_result'),
      ],
    ),
  );
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('scan panel shows reading, locked and hint states x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var used = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            backgroundColor: Colors.black,
            body: Column(
              children: [
                const Spacer(),
                DashboardScanPanel(
                  socSeen: 68,
                  socLocked: 68,
                  odoSeen: 4818,
                  scanning: true,
                  note:
                      'Chưa đọc rõ. Nghiêng nhẹ điện thoại để tránh lóa, đưa '
                      'gần hơn hoặc bấm Chụp ảnh.',
                  onCapture: () {},
                  onUse: () => used++,
                  onGallery: () {},
                  onManual: () {},
                ),
              ],
            ),
          ),
          scale,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Đã khớp'), findsOneWidget);
      expect(find.text('Đang xác nhận…'), findsOneWidget);
      // Thousands use the narrow space of the whole app.
      expect(find.textContaining('4 818'), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-note')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scan-use')));
      expect(used, 1);
      for (final key in ['scan-capture', 'scan-gallery', 'scan-manual']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('no camera: explains and offers photo or typing x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _Opener(
            (context) => Navigator.of(context)
                .push(
                  MaterialPageRoute<DashboardScanResult>(
                    builder: (_) => DashboardScanScreen(
                      lastOdoKm: 4804,
                      loadCameras: () async => const [],
                    ),
                  ),
                )
                .then(
                  (r) => r == null ? 'manual' : 'gallery=${r.wantsGallery}',
                ),
          ),
          scale,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-camera-problem')), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-capture')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('scan-gallery')));
      await tester.pumpAndSettle();
      expect(find.text('result: gallery=true'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scan-manual')));
      await tester.pumpAndSettle();
      expect(find.text('result: manual'), findsOneWidget);
    });

    testWidgets('a locked scan fills the sheet and says so x$scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<DashboardReading?> reader({required bool camera}) async =>
          const DashboardReading(soc: 68, odoKm: 4818, frames: 3);
      await tester.pumpWidget(
        _app(
          _Opener(
            (context) => BatteryReadingSheet.show(
              context,
              currentOdoKm: 4804,
              reader: reader,
            ),
          ),
          scale,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('Quét đồng hồ'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('reading-camera')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reading-camera')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã khớp qua 3 khung hình'), findsOneWidget);
      expect(find.text('68'), findsOneWidget);
      expect(find.text('4818'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
