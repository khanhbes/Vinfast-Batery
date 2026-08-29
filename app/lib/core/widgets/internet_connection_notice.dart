import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'app_popup.dart';

class InternetConnectionNotice extends StatefulWidget {
  const InternetConnectionNotice({super.key, required this.child});
  final Widget child;

  @override
  State<InternetConnectionNotice> createState() => _InternetNoticeState();
}

class _InternetNoticeState extends State<InternetConnectionNotice> {
  StreamSubscription<ConnectivityResult>? _subscription;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen(_handle);
    unawaited(_retry());
  }

  Future<void> _retry() async =>
      _handle(await Connectivity().checkConnectivity());

  void _handle(ConnectivityResult result) {
    final offline = result == ConnectivityResult.none;
    if (offline == _offline) return;
    _offline = offline;
    if (offline) {
      AppPopup.showWarning(
        'Mất kết nối Internet',
        detail:
            'Dữ liệu gần nhất vẫn được giữ. Timer Shelly tiếp tục chạy; LAN vẫn có thể điều khiển.',
        action: _retry,
        actionLabel: 'THỬ LẠI',
        persistent: true,
      );
    } else {
      AppPopup.dismiss();
      AppPopup.showSuccess('Đã kết nối lại Internet');
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
