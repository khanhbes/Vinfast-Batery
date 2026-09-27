import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/utils/app_error_formatter.dart';
import 'package:vinfast_battery/core/widgets/error_state.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Error state hides raw details and allows retry: $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ErrorState.fromError(
              error: Exception(
                'uid=qa-account token=qa-secret https://qa.invalid',
              ),
              onRetry: () => retries++,
            ),
          ),
        ),
      );
      expect(find.text(AppErrorFormatter.fallback), findsOneWidget);
      expect(find.textContaining('qa-account'), findsNothing);
      expect(find.textContaining('qa-secret'), findsNothing);
      expect(find.textContaining('qa.invalid'), findsNothing);
      await tester.ensureVisible(find.text('Thử lại'));
      await tester.tap(find.text('Thử lại'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  }
}
