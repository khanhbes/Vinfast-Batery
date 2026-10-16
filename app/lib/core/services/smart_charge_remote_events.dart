import 'dart:async';

/// A Smart Charge state change made elsewhere (another phone on the same
/// account, BatteryBot, the worker), delivered by an FCM data push while the
/// app is open (Task 123). It only asks for a fresh read; it never carries a
/// relay state to trust.
class SmartChargeRemoteEvent {
  const SmartChargeRemoteEvent({
    required this.sessionId,
    required this.vehicleId,
    required this.state,
  });

  final String sessionId;
  final String vehicleId;
  final String state;
}

class SmartChargeRemoteEvents {
  SmartChargeRemoteEvents._();
  static final instance = SmartChargeRemoteEvents._();

  final _controller = StreamController<SmartChargeRemoteEvent>.broadcast();

  Stream<SmartChargeRemoteEvent> get stream => _controller.stream;

  /// Accepts the raw FCM data map; ignores anything that is not a Smart
  /// Charge event.
  void addFromPush(Map<String, dynamic> data) {
    if (data['event']?.toString() != 'smart_charge') return;
    _controller.add(
      SmartChargeRemoteEvent(
        sessionId: data['sessionId']?.toString() ?? '',
        vehicleId: data['vehicleId']?.toString() ?? '',
        state: data['state']?.toString() ?? '',
      ),
    );
  }
}
