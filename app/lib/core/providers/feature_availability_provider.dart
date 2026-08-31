import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/feature_availability_registry.dart';

final featureAvailabilityProvider = Provider<FeatureAvailabilityRegistry>(
  (ref) => const FeatureAvailabilityRegistry(),
);
