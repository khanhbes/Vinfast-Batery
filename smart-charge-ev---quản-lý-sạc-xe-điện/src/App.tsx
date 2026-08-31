import React, { useState, useEffect } from 'react';
import { 
  VEHICLES, CHARGER_PROFILES, INITIAL_SESSIONS, DEFAULT_SETTINGS, DEFAULT_USER_PROFILE 
} from './data/mockData';
import { 
  Vehicle, ChargerProfile, ChargingSession, 
  LiveChargingMetrics, AppSettings, UserProfile 
} from './types';
import { AndroidFrame } from './components/AndroidFrame';
import { SmartChargeTab } from './components/SmartChargeTab';
import { HistoryTab } from './components/HistoryTab';
import { OverviewTab } from './components/OverviewTab';
import { SettingsTab } from './components/SettingsTab';
import { PredictionSheet } from './components/PredictionSheet';
import { CalibrateModal } from './components/CalibrateModal';
import { VehicleSelectorModal } from './components/VehicleSelectorModal';
import { SessionDetailModal } from './components/SessionDetailModal';
import { ConfirmEndSocModal } from './components/ConfirmEndSocModal';

export default function App() {
  // Navigation
  const [activeTab, setActiveTab] = useState<'overview' | 'charge' | 'history' | 'settings'>('charge');

  // User Profile State
  const [profile, setProfile] = useState<UserProfile>(DEFAULT_USER_PROFILE);

  // Active Vehicle & Chargers
  const [vehicles, setVehicles] = useState<Vehicle[]>(VEHICLES);
  const [activeVehicleId, setActiveVehicleId] = useState<string>('vinfast_feliz_2025');
  const activeVehicle = vehicles.find(v => v.id === activeVehicleId) || vehicles[0];

  // Which vehicle is actively charging (can be different from currently selected vehicle)
  const [chargingVehicleId, setChargingVehicleId] = useState<string | undefined>(undefined);

  // Per-vehicle target persistence (Section 9)
  const [vehicleTargets, setVehicleTargets] = useState<Record<string, number>>({
    vinfast_feliz_2025: 80,
    vinfast_evo_200: 90,
    vinfast_klara_s: 80,
  });

  const [chargers] = useState<ChargerProfile[]>(CHARGER_PROFILES);

  // Settings
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);

  // Live Metrics State (Initialized to reflect the screenshot context)
  const [metrics, setMetrics] = useState<LiveChargingMetrics>({
    isCharging: false,
    currentPercent: 35, // Can be calibrated to 100% or any value
    targetPercent: 80,
    currentPowerW: 980,
    currentVoltageV: 220,
    currentAmpsA: 4.5,
    batteryTempC: 31.5,
    sessionEnergyWh: 0,
    sessionDurationSeconds: 0,
    isAutoCutoffEnabled: true,
    isBmsConnected: false,
    isNightEcoMode: false,
    activeChargerId: 'fast_1000w',
    lastSyncTime: '14:13',
  });

  // History sessions
  const [sessions, setSessions] = useState<ChargingSession[]>(INITIAL_SESSIONS);

  // End SOC confirmation state
  const [isConfirmEndSocOpen, setIsConfirmEndSocOpen] = useState(false);
  const [suggestedEndSoc, setSuggestedEndSoc] = useState(80);

  // Synchronize target when switching vehicle
  const handleSelectVehicle = (id: string) => {
    setActiveVehicleId(id);
    const savedTarget = vehicleTargets[id] || settings.defaultTargetPercent || 80;
    setMetrics(prev => ({
      ...prev,
      targetPercent: savedTarget,
    }));
  };

  // Vehicle archiving handlers
  const handleArchiveVehicle = (id: string) => {
    setVehicles(prev => prev.map(v => v.id === id ? { ...v, isArchived: true } : v));
    // If active vehicle was archived, switch active vehicle to first unarchived
    if (activeVehicleId === id) {
      const remaining = vehicles.filter(v => v.id !== id && !v.isArchived);
      if (remaining.length > 0) {
        handleSelectVehicle(remaining[0].id);
      }
    }
  };

  const handleRestoreVehicle = (id: string) => {
    setVehicles(prev => prev.map(v => v.id === id ? { ...v, isArchived: false } : v));
  };

  // Data handlers
  const handleClearAllChargingData = () => {
    setSessions([]);
  };

  const handleRestoreSession = (id: string) => {
    setSessions(prev => prev.map(s => s.id === id ? { ...s, isHidden: false } : s));
  };

  // Modals state
  const [isPredictionOpen, setIsPredictionOpen] = useState(false);
  const [isCalibrateOpen, setIsCalibrateOpen] = useState(false);
  const [isVehicleSelectorOpen, setIsVehicleSelectorOpen] = useState(false);
  const [selectedSession, setSelectedSession] = useState<ChargingSession | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);

  // Timer simulation when charging is active
  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;
    if (metrics.isCharging) {
      interval = setInterval(() => {
        setMetrics(prev => {
          const nextDuration = prev.sessionDurationSeconds + 2;
          const currentCharger = chargers.find(c => c.id === prev.activeChargerId) || chargers[0];
          // Energy increment Wh = (PowerW * 2s) / 3600
          const addedWh = Math.round((currentCharger.powerW * 2) / 3600 * 10) / 10;
          const nextEnergy = prev.sessionEnergyWh + addedWh;
          
          // Progress SOC % slowly
          const batteryTotalWh = activeVehicle.batteryCapacityKWh * 1000;
          const pctIncrement = (addedWh / batteryTotalWh) * 100;
          const nextPercent = Math.min(100, Number((prev.currentPercent + (pctIncrement * 8)).toFixed(1)));

          // Check target auto cutoff
          if (prev.isAutoCutoffEnabled && nextPercent >= prev.targetPercent) {
            // Auto complete session!
            const newSession: ChargingSession = {
              id: `sess_${Date.now()}`,
              vehicleId: activeVehicle.id,
              vehicleNameSnapshot: activeVehicle.name,
              startTime: new Date(Date.now() - nextDuration * 1000).toISOString(),
              endTime: new Date().toISOString(),
              startPercent: Math.round(prev.currentPercent),
              endPercent: Math.round(nextPercent),
              targetPercent: prev.targetPercent,
              energyWh: Math.round(nextEnergy),
              durationMinutes: Math.max(1, Math.round(nextDuration / 60)),
              costVND: Math.round(((nextEnergy / 1000) / 0.9) * settings.electricityTariffVNDPerKWh),
              status: 'completed',
              terminalState: 'completed',
              triggerType: 'auto_target',
              strategy: 'ai_target',
              chargerName: currentCharger.name,
              dateStr: 'Hôm nay',
              timeStr: new Date().toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }),
              averagePowerW: currentCharger.powerW,
              peakPowerW: currentCharger.powerW + 20,
              averageVoltageV: currentCharger.voltageV,
              averageCurrentA: currentCharger.currentA,
              maxPlugTemperatureC: 37,
              predictedMinutes: Math.max(1, Math.round(nextDuration / 60)),
              trainingEligible: true,
              trainingReason: 'Phiên sạc tự động ngắt theo mục tiêu, dữ liệu đầy đủ',
              energyQuality: 'good',
            };
            setSessions(s => [newSession, ...s]);
            setChargingVehicleId(undefined);
            setSuggestedEndSoc(Math.round(nextPercent));
            setIsConfirmEndSocOpen(true);

            return {
              ...prev,
              isCharging: false,
              currentPercent: Math.round(nextPercent),
              sessionDurationSeconds: 0,
              sessionEnergyWh: 0,
            };
          }

          return {
            ...prev,
            sessionDurationSeconds: nextDuration,
            sessionEnergyWh: nextEnergy,
            currentPercent: nextPercent,
          };
        });
      }, 1000);
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [metrics.isCharging, metrics.activeChargerId, metrics.targetPercent, metrics.isAutoCutoffEnabled, activeVehicle, chargers, settings]);

  // Charging Handlers with Idempotency & Verified Relay Simulation
  const handleStartCharging = (mode: 'ai' | 'timed', targetOrDuration: number) => {
    setChargingVehicleId(activeVehicleId);
    setMetrics(prev => ({
      ...prev,
      isCharging: true,
      targetPercent: mode === 'ai' ? targetOrDuration : prev.targetPercent,
      sessionDurationSeconds: 0,
      sessionEnergyWh: 0, // Section 24: session energy starts at 0 Wh
    }));
  };

  const handleStopCharging = (reason: string) => {
    const currentCharger = chargers.find(c => c.id === metrics.activeChargerId) || chargers[0];
    const newSession: ChargingSession = {
      id: `sess_${Date.now()}`,
      vehicleId: activeVehicle.id,
      vehicleNameSnapshot: activeVehicle.name,
      startTime: new Date(Date.now() - metrics.sessionDurationSeconds * 1000).toISOString(),
      endTime: new Date().toISOString(),
      startPercent: Math.round(metrics.currentPercent),
      endPercent: Math.round(metrics.currentPercent),
      targetPercent: metrics.targetPercent,
      energyWh: Math.round(metrics.sessionEnergyWh),
      durationMinutes: Math.max(0, Math.round(metrics.sessionDurationSeconds / 60)),
      costVND: Math.round(((metrics.sessionEnergyWh / 1000) / 0.9) * settings.electricityTariffVNDPerKWh),
      status: 'stopped',
      terminalState: 'cancelled',
      triggerType: 'manual',
      strategy: 'ai_target',
      chargerName: currentCharger.name,
      dateStr: 'Hôm nay',
      timeStr: new Date().toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }),
      stopReason: reason || 'Người dùng chủ động dừng sạc',
      averagePowerW: currentCharger.powerW,
      peakPowerW: currentCharger.powerW + 15,
      averageVoltageV: currentCharger.voltageV,
      averageCurrentA: currentCharger.currentA,
      maxPlugTemperatureC: 36,
      trainingEligible: true,
      trainingReason: 'Học khoảng sạc thực tế do người dùng dừng sớm',
      energyQuality: 'good',
    };
    setSessions(s => [newSession, ...s]);
    setChargingVehicleId(undefined);
    setSuggestedEndSoc(Math.round(metrics.currentPercent));
    setIsConfirmEndSocOpen(true);

    setMetrics(prev => ({
      ...prev,
      isCharging: false,
      sessionDurationSeconds: 0,
      sessionEnergyWh: 0,
    }));
  };

  // Confirm actual end SOC & train Personal AI for active vehicle (Section 33 & 38)
  const handleConfirmActualSoc = (actualSoc: number) => {
    setMetrics(prev => ({
      ...prev,
      currentPercent: actualSoc,
    }));

    // Update vehicle's Personal AI training metrics
    setVehicles(prev => prev.map(v => {
      if (v.id === activeVehicleId) {
        const nextSessions = (v.sessionsUsedForAi || 0) + 1;
        let nextStage: 'learning_intro' | 'learning_habits' | 'personalized' = 'learning_intro';
        if (nextSessions >= 10) nextStage = 'personalized';
        else if (nextSessions >= 3) nextStage = 'learning_habits';

        return {
          ...v,
          sessionsUsedForAi: nextSessions,
          personalAiStage: nextStage,
          lastAiUpdate: 'Vừa xong',
        };
      }
      return v;
    }));
  };

  const handleTargetChange = (target: number) => {
    setMetrics(prev => ({
      ...prev,
      targetPercent: target
    }));
    // Save target per vehicle
    setVehicleTargets(prev => ({
      ...prev,
      [activeVehicleId]: target,
    }));
  };

  const handleCurrentPercentChange = (current: number) => {
    const clampedCurrent = Math.max(1, Math.min(100, Math.round(current)));
    setMetrics(prev => {
      const nextTarget = prev.targetPercent <= clampedCurrent 
        ? Math.min(100, Math.max(clampedCurrent + 5, 80)) 
        : prev.targetPercent;
      return {
        ...prev,
        currentPercent: clampedCurrent,
        targetPercent: nextTarget,
      };
    });
  };

  const handleSyncBms = () => {
    setIsSyncing(true);
    setTimeout(() => {
      setIsSyncing(false);
      const now = new Date();
      const timeStr = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
      setMetrics(prev => ({
        ...prev,
        lastSyncTime: timeStr,
        isBmsConnected: true,
      }));
    }, 700);
  };

  return (
    <AndroidFrame
      activeTab={activeTab}
      onChangeTab={setActiveTab}
      activeVehicle={activeVehicle}
      onOpenVehicleSelector={() => setIsVehicleSelectorOpen(true)}
      isCharging={metrics.isCharging}
    >
      {activeTab === 'charge' && (
        <SmartChargeTab
          vehicle={activeVehicle}
          vehicles={vehicles}
          activeVehicleId={activeVehicleId}
          onSelectVehicle={handleSelectVehicle}
          onOpenVehicleSelector={() => setIsVehicleSelectorOpen(true)}
          chargers={chargers}
          metrics={metrics}
          recentSessions={sessions}
          settings={settings}
          onStartCharging={handleStartCharging}
          onStopCharging={handleStopCharging}
          onTargetChange={handleTargetChange}
          onCurrentChange={handleCurrentPercentChange}
          onOpenPrediction={() => setIsPredictionOpen(true)}
          onOpenCalibrate={() => setIsCalibrateOpen(true)}
          onOpenSessionDetail={setSelectedSession}
          onNavigateToHistory={() => setActiveTab('history')}
          onToggleAutoCutoff={() => setMetrics(p => ({ ...p, isAutoCutoffEnabled: !p.isAutoCutoffEnabled }))}
          onToggleNightEco={() => setMetrics(p => ({ ...p, isNightEcoMode: !p.isNightEcoMode }))}
          onSyncBms={handleSyncBms}
          isSyncing={isSyncing}
          chargingVehicleId={chargingVehicleId}
        />
      )}

      {activeTab === 'history' && (
        <HistoryTab
          sessions={sessions}
          vehicle={activeVehicle}
          allVehicles={vehicles}
          liveMetrics={metrics}
          onOpenSessionDetail={setSelectedSession}
          onNavigateToCharging={() => setActiveTab('charge')}
          onHideSession={(id) => setSessions(prev => prev.map(s => s.id === id ? { ...s, isHidden: true, hiddenByUserAt: new Date().toISOString() } : s))}
        />
      )}

      {activeTab === 'overview' && (
        <OverviewTab
          vehicle={activeVehicle}
          metrics={metrics}
          onNavigateToCharging={() => setActiveTab('charge')}
        />
      )}

      {activeTab === 'settings' && (
        <SettingsTab
          settings={settings}
          vehicles={vehicles}
          activeVehicleId={activeVehicleId}
          sessions={sessions}
          profile={profile}
          onUpdateProfile={setProfile}
          onSelectVehicle={handleSelectVehicle}
          onArchiveVehicle={handleArchiveVehicle}
          onRestoreVehicle={handleRestoreVehicle}
          onOpenGarage={() => setIsVehicleSelectorOpen(true)}
          onUpdateSettings={(newVals) => setSettings(p => ({ ...p, ...newVals }))}
          onNavigateToHistory={() => setActiveTab('history')}
          onClearAllChargingData={handleClearAllChargingData}
          onRestoreSession={handleRestoreSession}
        />
      )}

      {/* Prediction Sheet Modal */}
      <PredictionSheet
        isOpen={isPredictionOpen}
        onClose={() => setIsPredictionOpen(false)}
        vehicle={activeVehicle}
        chargers={chargers}
        activeChargerId={metrics.activeChargerId}
        onSelectCharger={(id) => setMetrics(p => ({ ...p, activeChargerId: id }))}
        currentPercent={metrics.currentPercent}
        targetPercent={metrics.targetPercent}
        tariffVNDPerKWh={settings.electricityTariffVNDPerKWh}
        onStartChargingWithPreset={() => {
          if (!metrics.isCharging) handleStartCharging('ai', metrics.targetPercent);
        }}
        onScheduleNightCharge={() => {
          setMetrics(p => ({ ...p, isNightEcoMode: true }));
        }}
      />

      {/* Calibrate Battery % Modal */}
      <CalibrateModal
        isOpen={isCalibrateOpen}
        onClose={() => setIsCalibrateOpen(false)}
        currentPercent={Math.round(metrics.currentPercent)}
        onSavePercent={(newPercent) => {
          setMetrics(p => ({
            ...p,
            currentPercent: newPercent,
            targetPercent: Math.max(newPercent, p.targetPercent)
          }));
        }}
        isBmsConnected={metrics.isBmsConnected}
        onToggleBmsSync={() => setMetrics(p => ({ ...p, isBmsConnected: true }))}
      />

      {/* Vehicle Selector Modal */}
      <VehicleSelectorModal
        isOpen={isVehicleSelectorOpen}
        onClose={() => setIsVehicleSelectorOpen(false)}
        vehicles={vehicles}
        activeVehicleId={activeVehicleId}
        onSelectVehicle={handleSelectVehicle}
      />

      {/* Confirm End SOC Modal (Section 33 & 67) */}
      <ConfirmEndSocModal
        isOpen={isConfirmEndSocOpen}
        onClose={() => setIsConfirmEndSocOpen(false)}
        onConfirmActualSoc={handleConfirmActualSoc}
        vehicle={activeVehicle}
        suggestedSoc={suggestedEndSoc}
      />

      {/* Session Detail Modal */}
      <SessionDetailModal
        session={selectedSession}
        onClose={() => setSelectedSession(null)}
        onHideSession={(id) => {
          setSessions(prev => prev.map(s => s.id === id ? { ...s, isHidden: true, hiddenByUserAt: new Date().toISOString() } : s));
        }}
        onConfirmActualSoc={(id, confirmedSoc) => {
          setSessions(prev => prev.map(s => s.id === id ? { ...s, confirmedEndSoc: confirmedSoc, isSocEstimated: false } : s));
          handleConfirmActualSoc(confirmedSoc);
        }}
      />
    </AndroidFrame>
  );
}

