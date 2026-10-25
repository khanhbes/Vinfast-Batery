import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_bootstrap_coordinator.dart';

/// True once `Firebase.initializeApp()` finished (set by `AuthGate`).
///
/// QA 136: the app root picks its theme from the account's plan. Reading
/// the plan before Firebase is up built the auth stream too early; it
/// stayed in an error state for the whole session (no plan, no locks, the
/// achievements showed 0). Anything above `AuthGate` that needs the account
/// must wait for this.
final firebaseReadyProvider = StateProvider<bool>(
  (ref) => FirebaseBootstrapCoordinator.isReady,
);
