import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/app_error_reporter.dart';

/// Modal bottom sheet displaying detailed error and debug information.
class DebugErrorSheet extends StatelessWidget {
  const DebugErrorSheet({
    super.key,
    required this.entry,
  });

  final AppErrorEntry entry;

  /// Convenience method to display the error sheet for a specific entry or error.
  static Future<void> show(
    BuildContext context, {
    AppErrorEntry? entry,
    dynamic error,
    StackTrace? stackTrace,
    String source = 'App',
    String? endpoint,
    int? statusCode,
    String? debugCode,
    String? debugDetail,
  }) {
    AppErrorEntry targetEntry;
    if (entry != null) {
      targetEntry = entry;
    } else if (error != null) {
      targetEntry = AppErrorEntry(
        time: DateTime.now(),
        source: source,
        message: AppErrorReporter.redactSecrets(error.toString()),
        stackTrace: AppErrorReporter.redactSecrets(stackTrace?.toString() ?? ''),
        endpoint: endpoint != null ? AppErrorReporter.redactSecrets(endpoint) : null,
        statusCode: statusCode,
        debugCode: debugCode,
        debugDetail: debugDetail != null ? AppErrorReporter.redactSecrets(debugDetail) : null,
      );
    } else if (AppErrorReporter.entries.isNotEmpty) {
      targetEntry = AppErrorReporter.entries.first;
    } else {
      targetEntry = AppErrorEntry(
        time: DateTime.now(),
        source: 'System',
        message: 'Không có thông tin lỗi chi tiết.',
        stackTrace: '',
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DebugErrorSheet(entry: targetEntry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(entry.time);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.bug_report_rounded, color: Colors.orangeAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chi tiết lỗi',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                shrinkWrap: true,
                children: [
                  // Source & Time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.blueGrey.shade800 : Colors.blueGrey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.source,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.lightBlueAccent : Colors.blueGrey.shade800,
                          ),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // HTTP & Debug code tags
                  if (entry.statusCode != null || (entry.debugCode != null && entry.debugCode!.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (entry.statusCode != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: entry.statusCode! >= 500
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: entry.statusCode! >= 500
                                      ? Colors.redAccent.withOpacity(0.5)
                                      : Colors.orangeAccent.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                'HTTP ${entry.statusCode}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: entry.statusCode! >= 500
                                      ? Colors.redAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          if (entry.debugCode != null && entry.debugCode!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.purpleAccent.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                entry.debugCode!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purpleAccent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Endpoint
                  if (entry.endpoint != null && entry.endpoint!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Endpoint',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF14171E) : const Color(0xFFF1F3F5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              entry.endpoint!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Error message
                  Text(
                    'Thông báo lỗi',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      entry.message,
                      style: TextStyle(
                        color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  // Detail if present
                  if (entry.debugDetail != null && entry.debugDetail!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Chi tiết bổ sung',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF14171E) : const Color(0xFFF1F3F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.debugDetail!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],

                  // Stack trace
                  if (entry.stackTrace.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Stack trace',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF101217) : const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          entry.stackTrace,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: entry.toCopyableString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã sao chép chi tiết lỗi vào bộ nhớ tạm'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Sao chép lỗi'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
