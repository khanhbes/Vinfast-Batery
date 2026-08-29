import React from 'react';
import {
  BatteryCharging,
  Gauge,
  Award,
  Navigation,
  Timer,
  BellRing,
  MapPin,
  HeartPulse,
  Stethoscope,
  Box,
  Sparkles,
  Route,
  Zap,
  UserRound,
  Activity,
  ShieldCheck,
  Thermometer,
} from 'lucide-react';

export const MODEL_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  BatteryCharging,
  BatteryMedium: BatteryCharging,
  Gauge,
  Award,
  Navigation,
  Timer,
  BellRing,
  MapPin,
  HeartPulse,
  Stethoscope,
  Box,
  Sparkles,
  Route,
  Zap,
  UserRound,
  Activity,
  ShieldCheck,
  Thermometer,
};

export function getModelIcon(iconName?: string): React.ComponentType<{ className?: string }> {
  if (!iconName) return Box;
  return MODEL_ICONS[iconName] || Box;
}
