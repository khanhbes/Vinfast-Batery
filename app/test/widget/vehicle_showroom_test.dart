import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vehicle_showroom.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/features/home/vehicle_showroom_screen.dart';
import 'package:vinfast_battery/features/home/widgets/vehicle_showroom.dart';

Map<String, dynamic> angle(int i, {String scheme = 'https'}) => {
  'thumbnailUrl': '$scheme://media.example.net/a$i/t.webp',
  'mediumUrl': '$scheme://media.example.net/a$i/m.webp',
  'heroUrl': '$scheme://media.example.net/a$i/h.webp',
  'credit': '© VinFast',
  'backgroundRemoved': true,
};

Map<String, dynamic> media({int redAngles = 12, int whiteAngles = 1}) => {
  'showroom': {
    'defaultColorId': 'do',
    'colors': [
      {
        'id': 'do',
        'name': 'Đỏ tươi',
        'swatchHex': '#C8102E',
        'angles': [for (var i = 0; i < redAngles; i++) angle(i)],
      },
      {
        'id': 'trang',
        'name': 'Trắng ngọc trai',
        'swatchHex': '#F2F2EE',
        'angles': [for (var i = 0; i < whiteAngles; i++) angle(100 + i)],
      },
    ],
  },
};

// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  setUp(() => showroomImageProvider = (_) => MemoryImage(_png));
  group('VehicleShowroomData', () {
    test('parses colours, default, spin threshold and round-trips', () {
      final data = VehicleShowroomData.fromMedia(media())!;
      expect(data.colors.map((c) => c.id), ['do', 'trang']);
      expect(data.defaultColor.name, 'Đỏ tươi');
      expect(data.defaultColor.swatch, const Color(0xFFC8102E));
      expect(data.colors[0].canSpin, isTrue);
      expect(data.colors[1].canSpin, isFalse);
      expect(data.primary.heroUrl, 'https://media.example.net/a0/h.webp');
      final again = VehicleShowroomData.fromMedia({'showroom': data.toMap()})!;
      expect(again.colors.length, 2);
      expect(again.colors[0].angles.length, 12);
      expect(again.colors[0].swatch, data.colors[0].swatch);
    });

    test('drops non-https images, empty colours and bad ids', () {
      final data = VehicleShowroomData.fromMedia({
        'showroom': {
          'defaultColorId': 'missing',
          'colors': [
            {
              'id': '',
              'angles': [angle(1)],
            },
            {
              'id': 'x',
              'angles': [angle(1, scheme: 'http')],
            },
            {
              'id': 'y',
              'swatchHex': 'nope',
              'angles': [angle(2)],
            },
          ],
        },
      })!;
      expect(data.colors.map((c) => c.id), ['y']);
      expect(data.defaultColorId, 'y');
      expect(data.colors.first.swatch, const Color(0xFFC9CDD2));
    });

    test('falls back to the legacy single 2D image, or nothing', () {
      final legacy = VehicleShowroomData.fromMedia({
        'views': {'twoD': angle(7)},
      })!;
      expect(legacy.colors.single.name, 'Ảnh chính');
      expect(legacy.primary.heroUrl, contains('a7'));
      expect(VehicleShowroomData.fromMedia(null), isNull);
      expect(
        VehicleShowroomData.fromMedia({'heroUrl': 'http://x/y.webp'}),
        isNull,
      );
    });

    test('catalog spec parses and caches the showroom', () {
      final spec = VinFastModelSpec.fromMap({
        'modelName': 'VinFast Evo200',
        'battery': {'calculationCapacityWh': 1872},
        'media': media(),
      }, id: 'evo200');
      expect(spec.showroom?.colors.length, 2);
      final cached = VinFastModelSpec.fromMap(spec.toMap(), id: 'evo200');
      expect(cached.showroom?.colors[0].angles.length, 12);
    });
  });

  Widget host(Widget child, {double width = 360, double scale = 1}) =>
      MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: 300, child: child),
          ),
        ),
      );

  testWidgets('without images the stage shows the fallback art', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const VehicleShowroomView(color: null, fallback: Text('fallback-art')),
      ),
    );
    expect(find.text('fallback-art'), findsOneWidget);
    expect(find.text('Kéo để ngắm xe'), findsNothing);
  });

  testWidgets('360 waits for frames, then a drag turns the vehicle', (
    tester,
  ) async {
    final color = VehicleShowroomData.fromMedia(media())!.defaultColor;
    await tester.pumpWidget(
      host(VehicleShowroomView(color: color, fallback: const Text('art'))),
    );
    final state = tester.state<VehicleShowroomViewState>(
      find.byType(VehicleShowroomView),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(state.spinReady, isTrue);
    final before = state.frameIndex;
    await tester.drag(find.byType(VehicleShowroomView), const Offset(-160, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(state.frameIndex, isNot(before));
    expect(state.frameIndex, inInclusiveRange(0, 11));
  });

  testWidgets('broken frames fall back to the art instead of failing', (
    tester,
  ) async {
    showroomImageProvider = (_) => MemoryImage(Uint8List.fromList([1, 2, 3]));
    final color = VehicleShowroomData.fromMedia(media())!.defaultColor;
    await tester.pumpWidget(
      host(VehicleShowroomView(color: color, fallback: const Text('art'))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('art'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2.5D tilt springs back after the drag', (tester) async {
    final color = VehicleShowroomData.fromMedia(media())!.colors[1];
    await tester.pumpWidget(
      host(VehicleShowroomView(color: color, fallback: const Text('art'))),
    );
    await tester.pump();
    expect(find.text('Kéo để ngắm xe'), findsOneWidget);
    await tester.drag(find.byType(VehicleShowroomView), const Offset(120, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(VehicleShowroomView),
            matching: find.byType(Transform),
          )
          .first,
    );
    // Back to an upright pose (no residual Y rotation).
    expect(transform.transform.entry(0, 2).abs(), lessThan(0.01));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('showroom screen swaps colours and fits 320dp at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: VehicleShowroomScreen(
            title: 'VinFast Evo200',
            showroom: VehicleShowroomData.fromMedia(media()),
            figures: const [
              ('Dung lượng pin', '1.9 kWh'),
              ('Pin hiện tại', '100%'),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Đỏ tươi'),
        200,
        scrollable: list,
      );
      expect(find.text('Đỏ tươi'), findsOneWidget);
      await tester.ensureVisible(find.bySemanticsLabel('Màu Trắng ngọc trai'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Màu Trắng ngọc trai'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Trắng ngọc trai'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('screen explains when a model has no official photos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VehicleShowroomScreen(title: 'VinFast Klara', showroom: null),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.textContaining('chưa có ảnh chính thức'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('chưa có ảnh chính thức'), findsOneWidget);
  });
}
