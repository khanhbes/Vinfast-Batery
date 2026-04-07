import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/app_error_formatter.dart';

/// Widget hiển thị trạng thái lỗi với icon, thông báo, và nút thử lại.
/// Tự động rút gọn lỗi kỹ thuật dài thành thông báo thân thiện.
///
/// Sử dụng:
/// ```dart
/// ErrorState(
///   message: 'Không tải được dữ liệu',
///   onRetry: () => ref.invalidate(someProvider),
/// )
/// ```
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final String retryLabel;

  const ErrorState({
    super.key,
    this.message = 'Đã xảy ra lỗi. Vui lòng thử lại.',
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
    this.retryLabel = 'Thử lại',
  });

  /// Factory constructor nhận raw error object và format tự động
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
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
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
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
