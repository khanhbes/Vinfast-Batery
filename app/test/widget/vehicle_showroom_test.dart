import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/vehicle_showroom.dart';
import 'package:vinfast_battery/data/models/vinfast_model_spec.dart';
import 'package:vinfast_battery/core/widgets/vehicle_photo.dart';

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
  setUp(() => vehicleImageProvider = (_) => MemoryImage(_png));
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

  group('one vehicle photo everywhere (QA 131)', () {
    test('a Feliz always shows the bundled photo', () {
      expect(
        VehicleImages.resolve(name: 'VinFast Feliz S'),
        VehicleImages.felizUrl,
      );
      expect(
        VehicleImages.forVehicleMap({
          'vinfastModelId': 'feliz-2024',
          'catalogSnapshot': {
            'media': {'heroUrl': 'https://media.example.net/other.webp'},
          },
        }),
        VehicleImages.felizUrl,
      );
    });

    test('other models use their catalog photo, or none', () {
      expect(
        VehicleImages.forVehicleMap({
          'model': 'VinFast Evo200',
          'catalogSnapshot': {
            'media': {'heroUrl': 'https://media.example.net/evo.webp'},
          },
        }),
        'https://media.example.net/evo.webp',
      );
      expect(VehicleImages.forVehicleMap({'model': 'VinFast Klara'}), isNull);
    });

    testWidgets('no photo shows the fallback art', (tester) async {
      await tester.pumpWidget(
        host(const VehiclePhoto(url: null, fallback: Text('fallback-art'))),
      );
      expect(find.text('fallback-art'), findsOneWidget);
    });

    testWidgets('a broken photo falls back to the art', (tester) async {
      vehicleImageProvider = (_) => MemoryImage(Uint8List.fromList([1, 2, 3]));
      await tester.pumpWidget(
        host(
          const VehiclePhoto(
            url: 'https://media.example.net/x.webp',
            reflection: true,
            fallback: Text('art'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('art'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the photo renders with its reflection', (tester) async {
      await tester.pumpWidget(
        host(
          const VehiclePhoto(
            url: 'https://media.example.net/x.webp',
            reflection: true,
            fallback: Text('art'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('art'), findsNothing);
    });
  });
}
