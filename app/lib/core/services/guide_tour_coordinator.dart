import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Waits for real layout/route frames without a frame-count deadline or an
/// endless scheduleFrame loop. The navigation shell, not a help route that
/// has just been popped, owns this coordinator.
class GuideTourCoordinator {
  String? _uid;
  int _generation = 0;
  bool _scheduled = false;
  bool _disposed = false;
  bool Function()? _ready;
  OverlayEntry? Function()? _show;
  OverlayEntry? _entry;
  bool _manual = false;
  VoidCallback? onReplay;
  VoidCallback? dismissOverlay;
  bool Function(OverlayEntry)? entryIsActive;

  void activateAccount(String? uid) {
    if (_uid == uid) return;
    cancel();
    _uid = uid;
  }

  void replay() => onReplay?.call();

  void request({
    required String uid,
    required bool Function() ready,
    required OverlayEntry? Function() show,
    bool manual = false,
  }) {
    if (_disposed || _uid != uid) return;
    if (_manual && !manual && _show != null) return;
    // Repeated preference notifications must not replace an open tour.
    if (_entry?.mounted == true) return;
    _ready = ready;
    _show = show;
    _manual = manual;
    _observeNextFrame();
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _observeNextFrame() {
    if (_disposed || _scheduled || _show == null) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || _show == null) return;
      final generation = _generation;
      if (_entry case final entry?) {
        if (!(entryIsActive?.call(entry) ?? entry.mounted)) {
          _entry = null;
          _show = null;
          _ready = null;
          _manual = false;
          return;
        }
        if (_ready?.call() != true) {
          // A safety notice or another route takes priority. Keep the same
          // request pending so it can resume without changing guide progress.
          dismissOverlay?.call();
          _entry = null;
        }
        _observeNextFrame();
        return;
      }
      if (_ready?.call() == true) {
        final entry = _show?.call();
        if (generation != _generation || _disposed) return;
        if (entry != null) {
          _entry = entry;
          _observeNextFrame();
          return;
        }
      }
      // Register for the next *real* frame: async data, navigation, keyboard,
      // or anchor attachment supplies it. Do not manufacture 120 frames.
      _observeNextFrame();
    });
  }

  void cancel() {
    _generation++;
    _ready = null;
    _show = null;
    _entry = null;
    _manual = false;
    dismissOverlay?.call();
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    onReplay = null;
    dismissOverlay = null;
    entryIsActive = null;
    _disposed = true;
  }
}
