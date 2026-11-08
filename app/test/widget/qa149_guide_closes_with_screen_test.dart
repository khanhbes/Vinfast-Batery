import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/guide_registry.dart';
import 'package:vinfast_battery/core/theme/luxe_theme.dart';
import 'package:vinfast_battery/core/widgets/coach_mark_overlay.dart';

/// QA 149, found on the owner's phone: Pinova Bot's first-run guide stayed on
/// the app after its sheet was closed ("Đang đợi mục này hiển thị") and
/// swallowed every tap until "Bỏ qua". A guide now closes with its screen.
void main() {
  final anchor = GlobalKey();
  final steps = [
    CoachMarkStep(
      id: 'qa149',
      titleVi: 'Hỏi Pinova Bot',
      titleEn: 'Ask Pinova Bot',
      descriptionVi: 'Mô tả',
      descriptionEn: 'Description',
      anchorKey: anchor,
    ),
  ];

  tearDown(CoachMarkOverlay.dismissActive);

  testWidgets('closing the screen closes its guide and frees the app', (
    tester,
  ) async {
    var tappedBelow = 0;
    var skipped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: LuxeTheme.data(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  tappedBelow++;
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (sheet) => SizedBox(
                      height: 300,
                      child: Center(
                        child: TextButton(
                          key: anchor,
                          onPressed: () {},
                          child: const Text('Ô hỏi'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Mở bot'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở bot'));
    await tester.pumpAndSettle();
    final sheetContext = tester.element(find.text('Ô hỏi'));
    CoachMarkOverlay.show(
      context: sheetContext,
      steps: steps,
      showDontShowAgain: false,
      onFinish: () {},
      onSkip: () => skipped++,
      route: ModalRoute.of(sheetContext),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(CoachMarkOverlay.hasActive, isTrue);

    // The owner closes the sheet with Back while the guide is on screen.
    Navigator.of(sheetContext).pop();
    await tester.pumpAndSettle();
    expect(CoachMarkOverlay.hasActive, isFalse);
    expect(find.text('Hỏi Pinova Bot'), findsNothing);
    expect(skipped, 0, reason: 'not seen: it shows again next time');

    // Nothing is left on top: the screen below takes taps again.
    await tester.tap(find.text('Mở bot'));
    await tester.pumpAndSettle();
    expect(tappedBelow, 2);
  });
}
