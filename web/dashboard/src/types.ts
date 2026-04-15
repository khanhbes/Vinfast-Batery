export interface User {
  id: string;
  email: string;
  displayName: string;
  role: 'admin' | 'user';
  createdAt: string;
  lastLogin?: string;
}

export interface TelemetryData {
  trip_id: string;
  timestamp: string;
  latitude: number;
  longitude: number;
  speed_kmh: number;
  altitude_m: number;
  current_soc: number;
}

export interface KpiCard {
  label: string;
  value: string;
  change: string;
  trend: 'up' | 'down';
  icon: any;
  color: string;
  bg: string;
}

export interface AlertItem {
  id: string;
  type: 'warning' | 'error' | 'info';
  title: string;
  description: string;
  timestamp: string;
  vehicle?: string;
}
