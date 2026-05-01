import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/app_error_formatter.dart';

/// Widget hiển thị trạng thái lỗi — Dark Premium V3.
///
/// Trong `kDebugMode`, nếu có `rawError` thì luôn hiển thị thêm chuỗi raw
/// (monospace, cuộn được nếu dài) để dev debug nhanh.
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
  /// `rawError` được giữ lại để hiển thị chi tiết trong debug build.
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
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 36, color: AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
            if (kDebugMode && rawError != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rawError.toString(),
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: AppColors.textTertiary.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 160,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
