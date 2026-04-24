export interface BatteryState {
  percentage: number;
  soh: number; // State of Health
  estimatedRange: number; // km
  temp: number; // Celsius
}

export interface Trip {
  id: string;
  from: string;
  to: string;
  distance: number; // km
  duration: number; // minutes
  consumption: number; // %
  timestamp: number;
}

export interface MaintenanceItem {
  id: string;
  name: string;
  currentKm: number;
  limitKm: number;
  status: 'good' | 'warning' | 'critical';
  icon: string;
}

export interface UserProfile {
  name: string;
  weight: number;
  vehicleModel: string;
  totalOdo: number;
}
