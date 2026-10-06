import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/energy_level.dart';

class EnergyJourneyState {
  const EnergyJourneyState({
    required this.totalKWh,
    required this.currentLevel,
    this.nextLevel,
    required this.progressToNext,
    required this.remainingKWhToNext,
    required this.co2KgSaved,
    required this.equivalentKmDriven,
    required this.treesEquivalent,
    this.newLevelCelebration,
  });

  final double totalKWh;
  final EnergyLevel currentLevel;
  final EnergyLevel? nextLevel;
  final double progressToNext; // 0.0 to 1.0
  final double remainingKWhToNext;
  final double co2KgSaved;
  final double equivalentKmDriven;
  final double treesEquivalent;
  final EnergyLevel? newLevelCelebration;

  EnergyJourneyState copyWith({
    double? totalKWh,
    EnergyLevel? currentLevel,
    EnergyLevel? nextLevel,
    double? progressToNext,
    double? remainingKWhToNext,
    double? co2KgSaved,
    double? equivalentKmDriven,
    double? treesEquivalent,
    EnergyLevel? newLevelCelebration,
    bool clearCelebration = false,
  }) =>
      EnergyJourneyState(
        totalKWh: totalKWh ?? this.totalKWh,
        currentLevel: currentLevel ?? this.currentLevel,
        nextLevel: nextLevel ?? this.nextLevel,
        progressToNext: progressToNext ?? this.progressToNext,
        remainingKWhToNext: remainingKWhToNext ?? this.remainingKWhToNext,
        co2KgSaved: co2KgSaved ?? this.co2KgSaved,
        equivalentKmDriven: equivalentKmDriven ?? this.equivalentKmDriven,
        treesEquivalent: treesEquivalent ?? this.treesEquivalent,
        newLevelCelebration: clearCelebration
            ? null
            : (newLevelCelebration ?? this.newLevelCelebration),
      );
}

class EnergyJourneyController extends StateNotifier<EnergyJourneyState> {
  EnergyJourneyController()
      : super(
          _computeState(0.0),
        ) {
    _init();
  }

  static const _lastSeenLevelKey = 'energy_journey_last_seen_level';

  static EnergyJourneyState _computeState(double kwh, {EnergyLevel? celebration}) {
    final current = EnergyLevel.fromKWh(kwh);
    final next = current.nextLevel;

    double progress = 1.0;
    double remaining = 0.0;

    if (next != null) {
      final range = next.thresholdKWh - current.thresholdKWh;
      if (range > 0) {
        progress = ((kwh - current.thresholdKWh) / range).clamp(0.0, 1.0);
        remaining = (next.thresholdKWh - kwh).clamp(0.0, 99999.0);
      }
    }

    // Environmental calculations:
    // ~0.4 kg CO2 avoided per kWh compared to gasoline scooter
    final co2 = kwh * 0.40;
    // ~35 km per kWh for VinFast electric motorbikes (Feliz, Evo 200, Klara)
    final km = kwh * 35.0;
    // ~1 tree absorbs ~20 kg CO2 per year
    final trees = co2 / 20.0;

    return EnergyJourneyState(
      totalKWh: kwh,
      currentLevel: current,
      nextLevel: next,
      progressToNext: progress,
      remainingKWhToNext: remaining,
      co2KgSaved: co2,
      equivalentKmDriven: km,
      treesEquivalent: trees,
      newLevelCelebration: celebration,
    );
  }

  Future<void> _init() async {
    // Initial check
  }

  /// Updates cumulative energy from historical charging sessions
  Future<void> updateEnergyFromSessions(double totalEnergyKWh) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getInt(_lastSeenLevelKey) ?? 1;

    final currentLevel = EnergyLevel.fromKWh(totalEnergyKWh);
    EnergyLevel? celebration;

    if (currentLevel.level > lastSeen) {
      celebration = currentLevel;
      await prefs.setInt(_lastSeenLevelKey, currentLevel.level);
    }

    state = _computeState(totalEnergyKWh, celebration: celebration);
  }

  /// Manually dismisses the celebration dialog
  void dismissCelebration() {
    state = state.copyWith(clearCelebration: true);
  }
}

final energyJourneyControllerProvider =
    StateNotifierProvider<EnergyJourneyController, EnergyJourneyState>(
  (ref) => EnergyJourneyController(),
);
