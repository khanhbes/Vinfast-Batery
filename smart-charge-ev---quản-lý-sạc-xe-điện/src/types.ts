export interface Vehicle {
  id: string;
  name: string;
  model: string;
  year: number;
  batteryCapacityKWh: number; // e.g. 3.5 kWh for Feliz 2025 LFP
  maxRangeKm: number; // e.g. 198 km
  nominalVoltage: number; // e.g. 72V
  maxChargingPowerW: number; // e.g. 1000W / 2000W
  batteryType: 'LFP' | 'Lithium-ion';
  plateNumber: string;
  odometerKm: number;
  isArchived?: boolean;
  chargerBinding?: {
    chargerName: string;
    isConnected: boolean;
    deviceModel?: string;
  };
  personalAiStage?: 'learning_intro' | 'learning_habits' | 'personalized';
  personalAiEnabled?: boolean;
  sessionsUsedForAi?: number;
  lastAiUpdate?: string;
}

export interface ChargerProfile {
  id: string;
  name: string;
  powerW: number;
  voltageV: number;
  currentA: number;
  label: string;
  tag: string;
}

export interface ChargingSession {
  id: string;
  vehicleId: string;
  vehicleNameSnapshot: string;
  startTime: string;
  endTime?: string;
  startPercent: number;
  endPercent: number;
  targetPercent: number;
  isSocEstimated?: boolean;
  confirmedEndSoc?: number;
  energyWh: number;
  durationMinutes: number;
  costVND?: number;
  status: 'completed' | 'stopped' | 'charging' | 'scheduled';
  terminalState?: 'completed' | 'cancelled' | 'interrupted' | 'safety_stop' | 'failed';
  triggerType: 'manual' | 'smart_schedule' | 'auto_target';
  strategy: 'ai_target' | 'manual_timed' | 'manual';
  chargerName: string;
  dateStr: string;
  timeStr: string;
  isHidden?: boolean;
  hiddenByUserAt?: string;
  averagePowerW?: number;
  peakPowerW?: number;
  averageVoltageV?: number;
  averageCurrentA?: number;
  maxPlugTemperatureC?: number;
  maxBatteryTemperatureC?: number;
  predictedMinutes?: number;
  trainingEligible?: boolean;
  trainingReason?: string;
  energyQuality?: 'good' | 'partial' | 'invalid';
  stopReason?: string;
  chartSummary?: {
    soc: Array<{ minute: number; value: number }>;
    power: Array<{ minute: number; value: number }>;
    energy: Array<{ minute: number; value: number }>;
    temperature: Array<{ minute: number; value: number }>;
  };
}

export interface LiveChargingMetrics {
  isCharging: boolean;
  currentPercent: number;
  targetPercent: number;
  currentPowerW: number;
  currentVoltageV: number;
  currentAmpsA: number;
  batteryTempC: number;
  sessionEnergyWh: number;
  sessionDurationSeconds: number;
  isAutoCutoffEnabled: boolean;
  isBmsConnected: boolean;
  isNightEcoMode: boolean;
  activeChargerId: string;
  lastSyncTime: string;
}

export interface ChargingPrediction {
  targetPercent: number;
  currentPercent: number;
  deltaPercent: number;
  energyNeededWh: number;
  estimatedMinutes: number;
  estimatedCompletionTime: string;
  rangeAddedKm: number;
  estimatedCostVND: number;
  chargerName: string;
  isBalancingPhaseNeeded: boolean;
  phases: {
    name: string;
    description: string;
    fromPercent: number;
    toPercent: number;
    minutes: number;
    powerW: number;
  }[];
}

export interface UserProfile {
  name: string;
  email: string;
  avatarText: string;
  phone?: string;
  joinedDate?: string;
  role?: string;
}

export interface AppSettings {
  electricityTariffVNDPerKWh: number;
  defaultTargetPercent: number;
  confirmOnStopCharging: boolean; // Always true for safety
  notifyOnTargetReached: boolean;
  notifyOnInterrupted: boolean;
  notifySafetyAlert: boolean;
  notifyReminder: boolean;
  notifyAiUpdate: boolean;
  notifyMaintenance: boolean;
  allowDataForAi: boolean;
  hapticFeedback: boolean;
  motionReduction: boolean;
  energyUnit: 'auto' | 'wh' | 'kwh';
  language: 'vi' | 'en';
  theme: 'system' | 'dark' | 'amoled' | 'light';
  smartChargerMode: 'cloud' | 'lan' | 'direct';
  autoSyncCloud: boolean;
  pushNotifications: boolean;
  developerModeUnlocked: boolean;
}

