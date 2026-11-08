import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/data/models/entitlement.dart';
import 'package:vinfast_battery/features/auth/getting_started_screen.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/features/ai/dashboard_scan_screen.dart';
import 'package:vinfast_battery/features/premium/plan_transition_overlay.dart';

/// QA 149: frames of the story screens (Getting started, the plan change) at
/// moments of their timelines, for a person to look at. Not part of the
/// normal suite: it runs only with QA149_OUT (folder for the PNG files) and
/// QA139_FONTS (Flutter's material_fonts folder).
final _out = Platform.environment['QA149_OUT'];
final _fonts = Platform.environment['QA139_FONTS'];
final _boundary = GlobalKey();
const _dpr = 2.0;

Future<void> _loadFonts() async {
  final dir = _fonts!;
  for (final family in ['Roboto', 'FlutterTest']) {
    final roboto = FontLoader(family);
    for (final f in [
      'roboto-thin',
      'roboto-light',
      'roboto-regular',
      'roboto-medium',
      'roboto-bold',
      'roboto-black',
    ]) {
      roboto.addFont(
        Future.value(
          ByteData.sublistView(File('$dir/$f.ttf').readAsBytesSync()),
        ),
      );
    }
    await roboto.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$dir/materialicons-regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _host(Widget child) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: LuxeTheme.data().copyWith(
      textTheme: LuxeTheme.data().textTheme.apply(fontFamily: 'Roboto'),
    ),
    home: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Roboto'),
      child: child,
    ),
  ),
);

void main() {
  final skip = _out == null || _fonts == null;

  testWidgets('Getting started frames', (tester) async {
    await _loadFonts();
    Directory(_out!).createSync(recursive: true);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(GettingStartedScreen(onCreateAccount: () {}, onSignIn: () {})),
    );
    for (var page = 0; page < 4; page++) {
      var at = 0;
      for (final ms in [300, 900, 2700]) {
        await tester.pump(Duration(milliseconds: ms - at));
        at = ms;
        await _shot(tester, 'intro_p${page + 1}_${ms}ms');
      }
      if (page < 3) {
        // Halfway through the swipe to the next page.
        final gesture = await tester.startGesture(const Offset(300, 400));
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump(const Duration(milliseconds: 60));
        await _shot(tester, 'intro_swipe_${page + 1}to${page + 2}');
        await gesture.moveBy(const Offset(-100, 0));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 600));
      }
    }
    // Back to page 3: its scene plays again from the start.
    await tester.drag(find.byType(PageView), const Offset(260, 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _shot(tester, 'intro_back_p3_600ms');
    await tester.pump(const Duration(milliseconds: 2000));
    await _shot(tester, 'intro_back_p3_2600ms');
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);

  testWidgets('Scanner viewfinder over the real cluster', (tester) async {
    await _loadFonts();
    Directory(_out!).createSync(recursive: true);
    await tester.binding.setSurfaceSize(const Size(412, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bytes = gzip.decode(
      File('test/fixtures/dashboard/feliz_photo.gray.gz').readAsBytesSync(),
    );
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final w = data.getUint32(0, Endian.little);
    final h = data.getUint32(4, Endian.little);
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final v = bytes[8 + i];
      rgba[i * 4] = v;
      rgba[i * 4 + 1] = v;
      rgba[i * 4 + 2] = v;
      rgba[i * 4 + 3] = 255;
    }
    final photo = (await tester.runAsync(() async {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      return done.future;
    }))!;
    const template = DashboardTemplate.feliz2025;
    final window = DashboardScanGuide.windowFor(const Size(412, 600), template);
    for (final (name, soc, odo) in [
      ('scan_guide_reading', false, false),
      ('scan_guide_soc_locked', true, false),
    ]) {
      await tester.pumpWidget(
        _host(
          Stack(
            children: [
              const ColoredBox(color: Colors.black, child: SizedBox.expand()),
              // The photo stretched over the window, roughly where the
              // owner would line the glass up.
              Positioned.fromRect(
                rect: window.inflate(window.width * 0.06),
                child: RawImage(image: photo, fit: BoxFit.fill),
              ),
              DashboardScanGuide(
                ready: true,
                template: template,
                scanning: true,
                socLocked: soc,
                odoLocked: odo,
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await _shot(tester, name);
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);

  testWidgets('Plan change frames', (tester) async {
    await _loadFonts();
    Directory(_out!).createSync(recursive: true);
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        Stack(
          children: [
            const ColoredBox(color: LuxeColors.background),
            PlanTransitionOverlay(
              from: PlanTier.pro,
              to: PlanTier.ultra,
              onDone: () {},
            ),
          ],
        ),
      ),
    );
    var at = 0;
    for (final ms in [250, 600, 1000, 1500, 2200, 3200, 4600]) {
      await tester.pump(Duration(milliseconds: ms - at));
      at = ms;
      await _shot(tester, 'plan_ultra_${ms}ms');
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: skip);
}
