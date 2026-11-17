import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QA 165 (owner's choice): "Chế độ develop". Owners see as little text as
/// possible; with this mode on, screens add the technical detail (how a
/// figure was computed, its inputs, its error). Unlocked by tapping the
/// version seven times (Giới thiệu or the foot of Cài đặt), then switched in
/// Cài đặt. Kept on this phone only; it never changes what the app does.
class DevView extends ChangeNotifier {
  DevView();

  static DevView instance = DevView();

  static const _unlockedKey = 'devView.unlocked.v1';
  static const _onKey = 'devView.on.v1';
  static const tapsToUnlock = 7;
  static const tapWindow = Duration(seconds: 3);

  bool _unlocked = false;
  bool _on = false;
  bool _loaded = false;
  int _taps = 0;
  DateTime? _lastTap;

  bool get unlocked => _unlocked;

  /// Detailed text is shown.
  bool get on => _unlocked && _on;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _unlocked = prefs.getBool(_unlockedKey) ?? false;
      _on = prefs.getBool(_onKey) ?? false;
    } on Object {
      // No storage: the owner's view.
    }
    _loaded = true;
    notifyListeners();
  }

  /// One tap on the version. Returns how many taps are left (0 when this
  /// tap unlocked it, null when it was already unlocked).
  int? tapVersion({DateTime? now}) {
    if (_unlocked) return null;
    final at = now ?? DateTime.now();
    final last = _lastTap;
    _taps = last != null && at.difference(last) <= tapWindow ? _taps + 1 : 1;
    _lastTap = at;
    final left = tapsToUnlock - _taps;
    if (left <= 0) {
      _taps = 0;
      _unlocked = true;
      _on = true;
      notifyListeners();
      _save();
      return 0;
    }
    return left;
  }

  Future<void> setOn(bool value) async {
    if (!_unlocked) return;
    _on = value;
    notifyListeners();
    await _save();
  }

  /// Hides the switch again (and turns the detail off).
  Future<void> lock() async {
    _unlocked = false;
    _on = false;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_unlockedKey, _unlocked);
      await prefs.setBool(_onKey, _on);
    } on Object {
      // Remembered for this run only.
    }
  }

  /// One instance for the app's life: a provider scope going away (tests,
  /// account switch) must not dispose it.
  @override
  // ignore: must_call_super
  void dispose() {}

  /// Tests.
  @visibleForTesting
  void debugSet({required bool unlocked, required bool on}) {
    _unlocked = unlocked;
    _on = on;
    _loaded = true;
    notifyListeners();
  }
}

final devViewProvider = ChangeNotifierProvider<DevView>((ref) {
  final view = DevView.instance;
  view.load();
  return view;
});

/// Shows [child] only in "Chế độ develop" ([fallback] otherwise).
class DevOnly extends ConsumerWidget {
  const DevOnly({super.key, required this.child, this.fallback});

  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(devViewProvider).on
      ? child
      : (fallback ?? const SizedBox.shrink());
}

/// QA 165: "Chế độ develop" for any widget with a context (no Riverpod
/// needed): `DevViewScope.on(context)` rebuilds the caller when it changes.
/// Without a scope (tests) it reads [DevView.instance].
class DevViewScope extends InheritedNotifier<DevView> {
  DevViewScope({super.key, required super.child, DevView? view})
    : super(notifier: (view ?? DevView.instance)..load());

  static bool on(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DevViewScope>()
          ?.notifier
          ?.on ??
      DevView.instance.on;

  /// The full text in "Chế độ develop", the short one otherwise.
  static String pick(BuildContext context, String short, String full) =>
      on(context) ? full : short;
}
