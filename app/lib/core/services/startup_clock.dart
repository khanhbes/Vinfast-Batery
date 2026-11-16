import 'package:flutter/foundation.dart';

/// QA 162: how long the start takes, in the log of debug and profile builds
/// (`adb logcat | grep Startup`): when the splash finished drawing and when
/// the first screen was ready.
abstract final class StartupClock {
  static final Stopwatch _watch = Stopwatch();
  static final Set<String> _marked = {};

  static void start() {
    if (!_watch.isRunning) _watch.start();
  }

  /// Logs [event] once with the time since [start].
  static void mark(String event) {
    if (kReleaseMode || !_watch.isRunning || !_marked.add(event)) return;
    debugPrint('[Startup] $event ${_watch.elapsedMilliseconds}ms');
  }
}
