import { Vehicle, ChargerProfile, ChargingPrediction } from '../types';

export function calculateChargingPrediction(
  vehicle: Vehicle,
  charger: ChargerProfile,
  currentPercent: number,
  targetPercent: number,
  tariffVNDPerKWh: number = 2800
): ChargingPrediction {
  const clampedCurrent = Math.max(0, Math.min(100, Math.round(currentPercent)));
  const clampedTarget = Math.max(clampedCurrent, Math.min(100, Math.round(targetPercent)));
  const deltaPercent = clampedTarget - clampedCurrent;

  const totalBatteryCapacityWh = vehicle.batteryCapacityKWh * 1000;
  const energyNeededWh = Math.round((deltaPercent / 100) * totalBatteryCapacityWh);

  // Charger specs with ~90% conversion efficiency
  const effectivePowerW = Math.min(charger.powerW, vehicle.maxChargingPowerW) * 0.90;

  let totalMinutes = 0;
  const phases: ChargingPrediction['phases'] = [];

  if (deltaPercent <= 0) {
    const now = new Date();
    return {
      targetPercent: clampedTarget,
      currentPercent: clampedCurrent,
      deltaPercent: 0,
      energyNeededWh: 0,
      estimatedMinutes: 0,
      estimatedCompletionTime: formatClock(now),
      rangeAddedKm: 0,
      estimatedCostVND: 0,
      chargerName: charger.name,
      isBalancingPhaseNeeded: false,
      phases: []
    };
  }

  // Phase 1: Constant Current (CC) - up to 85%
  const ccThreshold = 85;
  const ccStart = Math.min(clampedCurrent, ccThreshold);
  const ccEnd = Math.min(clampedTarget, ccThreshold);

  if (ccEnd > ccStart) {
    const ccDelta = ccEnd - ccStart;
    const ccEnergyWh = (ccDelta / 100) * totalBatteryCapacityWh;
    const ccMinutes = Math.round((ccEnergyWh / effectivePowerW) * 60);
    totalMinutes += ccMinutes;

    phases.push({
      name: 'Pha sạc nhanh (CC)',
      description: 'Sạc dòng ổn định công suất tối đa',
      fromPercent: ccStart,
      toPercent: ccEnd,
      minutes: ccMinutes,
      powerW: Math.round(effectivePowerW / 0.90)
    });
  }

  // Phase 2: Constant Voltage & Cell Balancing (CV) - 85% to 100%
  const cvStart = Math.max(clampedCurrent, ccThreshold);
  const cvEnd = Math.max(clampedTarget, ccThreshold);

  if (cvEnd > cvStart) {
    const cvDelta = cvEnd - cvStart;
    const cvEnergyWh = (cvDelta / 100) * totalBatteryCapacityWh;
    // In CV phase, average power is ~55% of peak power due to tapering and cell balancing
    const cvAvgPowerW = effectivePowerW * 0.55;
    const cvMinutes = Math.round((cvEnergyWh / cvAvgPowerW) * 60);
    totalMinutes += cvMinutes;

    phases.push({
      name: 'Pha cân bằng cell (CV)',
      description: 'Giảm dần công suất để bảo vệ và cân bằng cell pin',
      fromPercent: cvStart,
      toPercent: cvEnd,
      minutes: cvMinutes,
      powerW: Math.round(cvAvgPowerW / 0.90)
    });
  }

  // Calculate completion time
  const completionDate = new Date(Date.now() + totalMinutes * 60 * 1000);
  const estimatedCompletionTime = formatClock(completionDate);

  // Range added
  const rangeAddedKm = Math.round((deltaPercent / 100) * vehicle.maxRangeKm);

  // Estimated Cost (Energy input including grid efficiency / 0.9)
  const gridEnergyKWh = (energyNeededWh / 0.90) / 1000;
  const estimatedCostVND = Math.round(gridEnergyKWh * tariffVNDPerKWh);

  return {
    targetPercent: clampedTarget,
    currentPercent: clampedCurrent,
    deltaPercent,
    energyNeededWh,
    estimatedMinutes: Math.max(1, totalMinutes),
    estimatedCompletionTime,
    rangeAddedKm,
    estimatedCostVND,
    chargerName: charger.name,
    isBalancingPhaseNeeded: clampedTarget > 85,
    phases
  };
}

export function formatDuration(minutes: number): string {
  if (minutes <= 0) return 'Đã đầy';
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m} phút`;
  if (m === 0) return `${h} giờ`;
  return `${h} giờ ${m} phút`;
}

export function formatCurrencyVND(amount: number): string {
  return new Intl.NumberFormat('vi-VN', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0
  }).format(amount);
}

function formatClock(date: Date): string {
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}
