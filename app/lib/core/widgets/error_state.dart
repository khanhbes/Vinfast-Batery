import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';
import '../utils/app_error_formatter.dart';
import 'debug_error_sheet.dart';

/// Recoverable error presentation. Diagnostics are opt-in in debug builds;
/// raw service content is never rendered automatically into the screen.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final String retryLabel;
  final Object? rawError;

  const ErrorState({
    super.key,
    this.message = 'Đã xảy ra lỗi. Vui lòng thử lại.',
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
    this.retryLabel = 'Thử lại',
    this.rawError,
  });

  /// Factory constructor nhận raw error object và format tự động.
  /// Diagnostics remain behind the opt-in, redacted debug details sheet.
  factory ErrorState.fromError({
    Key? key,
    required Object error,
    VoidCallback? onRetry,
    IconData icon = Icons.error_outline_rounded,
    String retryLabel = 'Thử lại',
    String? prefix,
  }) {
    final formatted = AppErrorFormatter.format(error);
    final message = prefix != null ? '$prefix: $formatted' : formatted;
    return ErrorState(
      key: key,
      message: message,
      onRetry: onRetry,
      icon: icon,
      retryLabel: retryLabel,
      rawError: error,
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuxeReveal(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF26282C), Color(0xFF0F1012)],
                ),
                border: Border.all(
                  color: LuxeColors.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(icon, size: 26, color: LuxeColors.danger),
            ),
          ),
          const SizedBox(height: 16),
          LuxeReveal(
            index: 1,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: LuxeText.body.copyWith(fontSize: 15),
            ),
          ),
          if (kDebugMode && rawError != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => DebugErrorSheet.show(
                context,
                error: rawError,
                source: 'ErrorState',
              ),
              icon: const Icon(Icons.bug_report_rounded, size: 16),
              label: const Text('Xem chi tiết lỗi (Debug)'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            LuxeReveal(
              index: 2,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(retryLabel),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
