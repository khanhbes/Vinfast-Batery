import 'package:flutter/foundation.dart';

/// Single log entry for error reporting and debugging.
class AppErrorEntry {
  AppErrorEntry({
    required this.time,
    required this.source,
    required this.message,
    required this.stackTrace,
    this.endpoint,
    this.statusCode,
    this.debugCode,
    this.debugDetail,
  });

  final DateTime time;
  final String source;
  final String message;
  final String stackTrace;
  final String? endpoint;
  final int? statusCode;
  final String? debugCode;
  final String? debugDetail;

  String toCopyableString() {
    final sb = StringBuffer();
    sb.writeln('Source: $source');
    sb.writeln('Time: ${time.toIso8601String()}');
    if (endpoint != null && endpoint!.isNotEmpty) {
      sb.writeln('Endpoint: $endpoint');
    }
    if (statusCode != null) {
      sb.writeln('HTTP Status: $statusCode');
    }
    if (debugCode != null && debugCode!.isNotEmpty) {
      sb.writeln('Debug Code: $debugCode');
    }
    if (debugDetail != null && debugDetail!.isNotEmpty) {
      sb.writeln('Detail: $debugDetail');
    }
    sb.writeln('Error: $message');
    if (stackTrace.isNotEmpty) {
      sb.writeln('--- Stack Trace ---');
      sb.writeln(stackTrace);
    }
    return sb.toString();
  }
}

/// Centralized error reporter and debug log collector.
class AppErrorReporter {
  static const int maxEntries = 50;
  static final List<AppErrorEntry> _entries = [];
  static final ValueNotifier<List<AppErrorEntry>> notifier =
      ValueNotifier<List<AppErrorEntry>>([]);

  static List<AppErrorEntry> get entries => List.unmodifiable(_entries);

  /// Sanitizes sensitive information (passwords, tokens, API keys) from text.
  static String redactSecrets(String input) {
    if (input.isEmpty) return input;
    var sanitized = input;

    // Redact Bearer tokens
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
      (m) => '${m[1]}***',
    );

    // Redact Authorization headers
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(Authorization:\s*)(?:Bearer\s+)?[^\r\n,]+', caseSensitive: false),
      (m) => '${m[1]}Bearer ***',
    );

    // Redact password fields
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(password["\x27]?\s*[:=]\s*["\x27]?)([^"\x27,\s&]+)(["\x27]?)', caseSensitive: false),
      (m) => '${m[1]}***${m[3]}',
    );

    // Redact API keys and auth keys
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'((?:api[_\-]?key|apiKey|auth[_\-]?key|shelly[_\-]?key)["\x27]?\s*[:=]\s*["\x27]?)([^"\x27,\s&]+)(["\x27]?)', caseSensitive: false),
      (m) => '${m[1]}***${m[3]}',
    );

    // Redact tokens
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'((?:refresh[_\-]?token|id[_\-]?token|firebase[_\-]?token|token)["\x27]?\s*[:=]\s*["\x27]?)([^"\x27,\s&]+)(["\x27]?)', caseSensitive: false),
      (m) => '${m[1]}***${m[3]}',
    );

    // Redact cookies
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'(cookie["\x27]?\s*[:=]\s*["\x27]?)([^"\x27,\s;\r\n]+)(["\x27]?)', caseSensitive: false),
      (m) => '${m[1]}***${m[3]}',
    );

    return sanitized;
  }

  /// Report an error with source and optional API metadata.
  static void report(
    dynamic error,
    StackTrace? stackTrace, {
    String source = 'App',
    String? endpoint,
    int? statusCode,
    String? debugCode,
    String? debugDetail,
  }) {
    final rawMessage = error?.toString() ?? 'Unknown error';
    final rawStack = stackTrace?.toString() ?? '';

    final cleanMessage = redactSecrets(rawMessage);
    final cleanStack = redactSecrets(rawStack);
    final cleanEndpoint = endpoint != null ? redactSecrets(endpoint) : null;
    final cleanDetail = debugDetail != null ? redactSecrets(debugDetail) : null;

    final entry = AppErrorEntry(
      time: DateTime.now(),
      source: source,
      message: cleanMessage,
      stackTrace: cleanStack,
      endpoint: cleanEndpoint,
      statusCode: statusCode,
      debugCode: debugCode,
      debugDetail: cleanDetail,
    );

    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifier.value = List.unmodifiable(_entries);

    debugPrint('🚨 [$source] $cleanMessage');
  }

  /// Clears all recorded error entries.
  static void clear() {
    _entries.clear();
    notifier.value = const [];
  }

  /// Exports all error entries to a single string suitable for clipboard copy.
  static String exportAllLogs() {
    if (_entries.isEmpty) return 'No errors recorded.';
    final sb = StringBuffer();
    sb.writeln('=== APP ERROR LOGS (${_entries.length} entries) ===\n');
    for (var i = 0; i < _entries.length; i++) {
      sb.writeln('--- [#${i + 1}] ---');
      sb.writeln(_entries[i].toCopyableString());
      sb.writeln();
    }
    return sb.toString();
  }
}
