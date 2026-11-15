import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/dashboard_layout_parser.dart';
import 'package:vinfast_battery/data/services/dashboard_templates.dart';
import 'package:vinfast_battery/data/services/seven_segment_reader.dart';
import 'package:vinfast_battery/features/ai/dashboard_scan_screen.dart';

import 'qa156_scan_bench_test.dart' as bench;

/// QA 159: the owner's scan of 15/11/2026 locked 37 % as 7 %. The "3" ran
/// into the battery icon under it, the phone was held far (the glass at
/// 60 % of the window), and the lone "7" passed as a number.
void main() {
  final photo = bench.photos[1];
  final src = photo.load();

  test('the 37 % photo never reads 7, near or far', () {
    for (final scale in [0.95, 1.0, 1.1, 1.3, 1.5, 1.7, 1.9]) {
      for (final tilt in [-4.0, 0.0, 4.0]) {
        final frame = bench.frameFor(
          photo,
          src,
          bench.Shot(scale: scale, tilt: tilt, blur: 1, noise: 3),
        );
        final r = bench.readFrame(frame, lastOdoKm: 5480);
        expect(r.soc, anyOf(isNull, 37), reason: 'scale $scale tilt $tilt');
      }
    }
  });

  test('a real one-digit % still reads (the tens cell is dark)', () {
    // The "3" blanked out: the cluster as it shows 7 %.
    final pixels = Uint8List.fromList(src.pixels);
    for (var y = 232; y < 290; y++) {
      for (var x = 300; x < 348; x++) {
        pixels[y * src.width + x] = 22;
      }
    }
    final seven = GrayImage(src.width, src.height, pixels);
    final frame = bench.frameFor(photo, seven, const bench.Shot());
    expect(bench.readFrame(frame, lastOdoKm: 5480).soc, 7);
  });

  test('the glass is found from the speed digits however far', () {
    for (final scale in [0.9, 1.0, 1.3, 1.6, 1.9]) {
      final frame = bench.frameFor(photo, src, bench.Shot(scale: scale));
      final scan = SevenSegmentReader.scanFrame(
        frame.image,
        template: DashboardTemplate.feliz2025,
        window: frame.window,
        recut: frame.recut,
      );
      final share = scan.glass!.width / frame.window.width;
      expect(share, closeTo(1 / scale, 0.08 / scale), reason: 'scale $scale');
    }
  });

  test('a one-digit % waits while a two-digit one containing it is in view', () {
    DashboardLayoutReading soc(int value) =>
        DashboardLayoutReading(soc: value, socConfident: true);
    final vote = DashboardScanVote();
    for (final value in [7, 7, 37, 7, 7, 7]) {
      vote.add(soc(value));
    }
    expect(vote.socLocked, isNull);
    final clean = DashboardScanVote();
    for (var i = 0; i < 5; i++) {
      clean.add(soc(7));
    }
    expect(clean.socLocked, 7);
  });

  test('the hint asks to come closer once the zoom is used up', () {
    expect(
      scanHint(socLocked: false, odoLocked: true, blindFrames: 0, tooFar: true),
      'Đưa điện thoại gần màn hình xe hơn.',
    );
    expect(
      scanHint(socLocked: true, odoLocked: true, blindFrames: 0, tooFar: true),
      'Đã đọc xong',
    );
  });
}
