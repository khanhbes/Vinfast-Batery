enum FeatureAvailabilityState {
  ready,
  needsSetup,
  needsData,
  disabled,
  offline,
}

class FeatureAvailability {
  const FeatureAvailability({required this.state, required this.reason});
  final FeatureAvailabilityState state;
  final String reason;
  bool get enabled => state == FeatureAvailabilityState.ready;
}
