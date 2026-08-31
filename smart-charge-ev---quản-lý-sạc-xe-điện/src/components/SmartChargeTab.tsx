import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Zap, Power, Sparkles, Clock, ShieldCheck, 
  ChevronRight, ChevronDown, RefreshCw, Pencil, Bluetooth,
  Thermometer, Gauge, Moon, Bell, CheckCircle2,
  AlertTriangle, BatteryCharging, ArrowUpRight, Battery,
  Activity, Info, Wifi, WifiOff, Lock, Play, ChevronUp
} from 'lucide-react';
import { Vehicle, ChargerProfile, ChargingSession, LiveChargingMetrics, AppSettings } from '../types';
import { BatteryVisualizer } from './BatteryVisualizer';
import { calculateChargingPrediction, formatDuration, formatCurrencyVND } from '../utils/chargingCalculator';
import { StartChargeModal } from './StartChargeModal';
import { StopChargeModal } from './StopChargeModal';

interface SmartChargeTabProps {
  vehicle: Vehicle;
  vehicles: Vehicle[];
  activeVehicleId: string;
  onSelectVehicle: (id: string) => void;
  onOpenVehicleSelector: () => void;
  chargers: ChargerProfile[];
  metrics: LiveChargingMetrics;
  recentSessions: ChargingSession[];
  settings: AppSettings;
  onStartCharging: (mode: 'ai' | 'timed', targetOrDuration: number) => void;
  onStopCharging: (reason: string) => void;
  onTargetChange: (target: number) => void;
  onCurrentChange?: (current: number) => void;
  onOpenPrediction: () => void;
  onOpenCalibrate: () => void;
  onOpenSessionDetail: (session: ChargingSession) => void;
  onNavigateToHistory: () => void;
  onToggleAutoCutoff: () => void;
  onToggleNightEco: () => void;
  onSyncBms: () => void;
  isSyncing: boolean;
  chargingVehicleId?: string;
}

export const SmartChargeTab: React.FC<SmartChargeTabProps> = ({
  vehicle,
  vehicles,
  activeVehicleId,
  onSelectVehicle,
  onOpenVehicleSelector,
  chargers,
  metrics,
  recentSessions,
  settings,
  onStartCharging,
  onStopCharging,
  onTargetChange,
  onCurrentChange,
  onOpenPrediction,
  onOpenCalibrate,
  onOpenSessionDetail,
  onNavigateToHistory,
  onToggleAutoCutoff,
  onToggleNightEco,
  onSyncBms,
  isSyncing,
  chargingVehicleId,
}) => {
  // Mode selection: 'ai' vs 'timed'
  const [chargeMode, setChargeMode] = useState<'ai' | 'timed'>('ai');
  const [timedDurationMinutes, setTimedDurationMinutes] = useState<number>(120); // default 2 hours

  // Expandable metrics drawer on active charging
  const [showActiveDetails, setShowActiveDetails] = useState<boolean>(false);

  // Network connection state simulation (for edge-case testing & offline reassurance)
  const [isNetworkOffline, setIsNetworkOffline] = useState<boolean>(false);
  const [isReconnecting, setIsReconnecting] = useState<boolean>(false);

  // Modals state
  const [isStartModalOpen, setIsStartModalOpen] = useState<boolean>(false);
  const [isStopModalOpen, setIsStopModalOpen] = useState<boolean>(false);

  const currentCharger = chargers.find(c => c.id === metrics.activeChargerId) || chargers[0];
  const prediction = calculateChargingPrediction(
    vehicle,
    currentCharger,
    metrics.currentPercent,
    metrics.targetPercent
  );

  // Check if ANOTHER vehicle is charging
  const otherChargingVehicle = vehicles.find(
    v => v.id !== activeVehicleId && v.id === chargingVehicleId && metrics.isCharging
  );

  // Live timer formatting
  const liveMinutes = Math.floor(metrics.sessionDurationSeconds / 60);
  const liveSeconds = metrics.sessionDurationSeconds % 60;
  const timeFormatted = `${liveMinutes.toString().padStart(2, '0')}:${liveSeconds.toString().padStart(2, '0')}`;

  // AI Stage Badge text & styling
  const getAiStageInfo = () => {
    const stage = vehicle.personalAiStage || 'learning_intro';
    const sessions = vehicle.sessionsUsedForAi || 0;
    if (stage === 'personalized' || sessions >= 10) {
      return {
        label: 'Đã cá nhân hóa cho xe này',
        tag: 'Mô hình riêng • Độ chính xác cao',
        color: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/30',
      };
    }
    if (stage === 'learning_habits' || sessions >= 3) {
      return {
        label: `AI đang học xe của bạn (${sessions} phiên)`,
        tag: 'Đang tinh chỉnh hệ số nạp',
        color: 'text-sky-400 bg-sky-500/10 border-sky-500/30',
      };
    }
    return {
      label: 'AI đang làm quen với xe',
      tag: 'Cần thêm 2 phiên sạc để học',
      color: 'text-amber-400 bg-amber-500/10 border-amber-500/30',
    };
  };

  const aiStage = getAiStageInfo();

  // Reconnection simulation
  const handleRetryConnection = () => {
    setIsReconnecting(true);
    setTimeout(() => {
      setIsReconnecting(false);
      setIsNetworkOffline(false);
    }, 1200);
  };

  // Timed presets (including "Ngay lập tức")
  const timedPresets = [
    { mins: 0, label: 'Ngay lập tức', badge: 'Không ngắt' },
    { mins: 30, label: '30 phút', badge: 'Sạc nhanh' },
    { mins: 60, label: '1 giờ', badge: 'Tiêu chuẩn' },
    { mins: 120, label: '2 giờ', badge: 'Khuyên dùng' },
    { mins: 240, label: '4 giờ', badge: 'Sạc sâu' },
    { mins: 360, label: '6 giờ', badge: 'Đầy 100%' },
  ];

  return (
    <div id="smart-charge-view" className="space-y-4 pb-24 pt-1 max-w-lg mx-auto animate-fadeIn">
      {/* 1. SMART CHARGE HEADER (Clean, vehicle selector removed, prominent Smart Charge branding) */}
      <div className="flex items-center justify-between px-1">
        <div className="flex items-center gap-3">
          <motion.div 
            animate={{ rotate: [0, 5, -5, 0] }}
            transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}
            className="w-9 h-9 rounded-2xl bg-gradient-to-tr from-emerald-500 via-teal-500 to-sky-500 flex items-center justify-center text-slate-950 font-bold shadow-lg shadow-emerald-500/25 shrink-0"
          >
            <Zap className="w-5 h-5 fill-slate-950 stroke-[2.5]" />
          </motion.div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-black tracking-tight text-white flex items-center gap-1.5">
                Smart Charge
              </h1>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 border border-emerald-500/30 uppercase tracking-wider font-mono">
                AI Powered
              </span>
            </div>
            <p className="text-[11px] text-slate-400 font-medium flex items-center gap-1.5 mt-0.5">
              <span className="text-slate-300 font-semibold">{vehicle.name}</span>
              <span className="text-slate-600">•</span>
              <span className="font-mono text-emerald-400 font-bold">{Math.round(metrics.currentPercent)}% pin</span>
            </p>
          </div>
        </div>

        {/* Sync BMS button */}
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          type="button"
          onClick={onSyncBms}
          disabled={isSyncing}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/10 text-[11px] text-slate-300 hover:text-emerald-400 hover:border-emerald-500/30 transition-all shadow-sm"
        >
          <RefreshCw className={`w-3 h-3 text-emerald-400 ${isSyncing ? 'animate-spin' : ''}`} />
          <span>{isSyncing ? 'Đang đồng bộ...' : metrics.lastSyncTime}</span>
        </motion.button>
      </div>

      {/* 2. GLOBAL PERSISTENT PILL (If another vehicle is currently charging) */}
      {otherChargingVehicle && (
        <motion.div
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          onClick={() => onSelectVehicle(otherChargingVehicle.id)}
          className="p-3 rounded-2xl bg-emerald-500/15 border border-emerald-500/40 text-xs text-white flex items-center justify-between cursor-pointer hover:bg-emerald-500/20 transition-all shadow-lg"
        >
          <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span>
            <span className="font-bold">{otherChargingVehicle.name} đang sạc</span>
            <span className="text-slate-300 text-[11px]">• Còn {formatDuration(prediction.estimatedMinutes)}</span>
          </div>
          <span className="text-[11px] font-bold text-emerald-400 flex items-center gap-0.5">
            Mở xem <ChevronRight className="w-3 h-3" />
          </span>
        </motion.div>
      )}

      {/* 3. CONNECTION STATE BANNER / REASSURANCE (Section 28-30) */}
      {isNetworkOffline ? (
        <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-between text-xs">
          <div className="flex items-center gap-2.5">
            <WifiOff className="w-4 h-4 text-amber-400 shrink-0" />
            <div>
              <span className="font-bold text-amber-400 block">Mất Internet • Sạc vẫn được bảo vệ</span>
              <span className="text-[11px] text-slate-400">Timer phần cứng trên bộ sạc Shelly vẫn tự ngắt an toàn.</span>
            </div>
          </div>
          <button
            type="button"
            onClick={handleRetryConnection}
            disabled={isReconnecting}
            className="px-2.5 py-1 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 text-[11px] font-bold border border-amber-500/30 transition-colors"
          >
            {isReconnecting ? 'Đang thử...' : 'Thử lại'}
          </button>
        </div>
      ) : (
        <div className="flex items-center justify-between px-2 text-[11px] text-slate-400">
          <div className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span className="text-slate-300 font-medium">
              {vehicle.chargerBinding?.isConnected ? 'Bộ sạc đã kết nối' : 'Đang tìm bộ sạc'}
            </span>
          </div>
        </div>
      )}

      {/* 4. MAIN STATUS CARD (Active Charging vs Standby) */}
      {metrics.isCharging ? (
        /* ACTIVE CHARGING VIEW (Section 21, 22, 23, 24) */
        <div
          id="active-charging-container"
          className="rounded-3xl bg-[#111] border border-emerald-500/50 p-5 shadow-[0_0_40px_rgba(16,185,129,0.15)] relative overflow-hidden space-y-4"
        >
          <div className="absolute top-0 right-0 w-40 h-40 bg-emerald-500/10 blur-3xl -mr-20 -mt-20 pointer-events-none"></div>

          {/* Active Header & Permanent Target Pin */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-emerald-400 animate-ping"></div>
              <span className="text-sm font-extrabold text-emerald-400 uppercase tracking-wide">
                Đang sạc
              </span>
            </div>

            {/* MỤC TIÊU XX% IS PERMANENTLY VISIBLE IN ACTIVE STATE */}
            <div className="px-3 py-1 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 text-xs font-extrabold font-mono flex items-center gap-1.5 shadow-sm">
              <ShieldCheck className="w-3.5 h-3.5" />
              <span>Mục tiêu {metrics.targetPercent}%</span>
            </div>
          </div>

          {/* Animated Horizontal Battery with Real/Interpolated Telemetry */}
          <div className="space-y-2">
            <div className="flex items-baseline justify-between">
              <div>
                <span className="text-3xl font-extrabold text-white font-mono-num">
                  {Math.round(metrics.currentPercent)}%
                </span>
                <span className="text-xs text-slate-400 ml-2">
                  • {metrics.isBmsConnected ? 'BMS xe' : 'Ước tính'}
                </span>
              </div>
              <div className="text-right">
                <span className="text-xs text-slate-400 block">Thời gian đã sạc</span>
                <span className="text-sm font-bold text-slate-200 font-mono-num">
                  {timeFormatted}
                </span>
              </div>
            </div>

            {/* Horizontal Battery Track */}
            <div className="relative h-10 bg-[#080808] rounded-2xl p-1 border border-emerald-500/40 overflow-hidden shadow-inner flex items-center">
              <motion.div
                className="h-full rounded-xl bg-gradient-to-r from-emerald-600 via-emerald-500 to-emerald-400 relative overflow-hidden shadow-lg shadow-emerald-500/20"
                style={{ width: `${Math.min(100, metrics.currentPercent)}%` }}
                layout
              >
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-energy-gradient rounded-xl" />
              </motion.div>

              {/* Target vertical indicator line */}
              <div
                className="absolute top-0 bottom-0 z-20 pointer-events-none flex flex-col items-center justify-between py-0.5"
                style={{ left: `${metrics.targetPercent}%` }}
              >
                <div className="w-0.5 h-2 bg-white rounded-full"></div>
                <span className="text-[9px] font-bold text-white font-mono bg-black/60 px-1 rounded">
                  {metrics.targetPercent}%
                </span>
                <div className="w-0.5 h-2 bg-white rounded-full"></div>
              </div>
            </div>
          </div>

          {/* Remaining Time & Session Energy starting at 0 Wh */}
          <div className="grid grid-cols-2 gap-3 pt-1">
            <div className="p-3 rounded-2xl bg-[#161616] border border-white/5">
              <span className="text-[11px] text-slate-400 font-medium block">Còn lại</span>
              <span className="text-sm font-extrabold text-white font-mono-num mt-0.5 block">
                {formatDuration(prediction.estimatedMinutes)}
              </span>
              <span className="text-[10px] text-slate-500 mt-0.5 block">
                Xong lúc {prediction.estimatedCompletionTime}
              </span>
            </div>

            <div className="p-3 rounded-2xl bg-[#161616] border border-white/5">
              <span className="text-[11px] text-slate-400 font-medium block">Năng lượng phiên</span>
              <span className="text-sm font-extrabold text-emerald-400 font-mono-num mt-0.5 block">
                {(metrics.sessionEnergyWh / 1000).toFixed(2)} kWh
              </span>
              <span className="text-[10px] text-slate-500 mt-0.5 block">
                Công suất {metrics.chargingPowerW} W
              </span>
            </div>
          </div>

          {/* Expandable Technical Telemetry Accordion */}
          <div className="border-t border-white/5 pt-3">
            <button
              type="button"
              onClick={() => setShowActiveDetails(!showActiveDetails)}
              className="w-full flex items-center justify-between text-xs text-slate-400 hover:text-white transition-colors py-1"
            >
              <span className="font-medium flex items-center gap-1.5">
                <Activity className="w-3.5 h-3.5 text-emerald-400" />
                Chi tiết thông số dòng điện
              </span>
              {showActiveDetails ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            </button>

            {showActiveDetails && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                className="grid grid-cols-3 gap-2 mt-2 pt-2 border-t border-white/5 text-center font-mono"
              >
                <div className="p-2 rounded-xl bg-white/5 border border-white/5">
                  <span className="text-[10px] text-slate-500 block">Công suất</span>
                  <span className="text-xs font-bold text-white">{metrics.currentPowerW} W</span>
                </div>
                <div className="p-2 rounded-xl bg-white/5 border border-white/5">
                  <span className="text-[10px] text-slate-500 block">Điện áp / Dòng</span>
                  <span className="text-xs font-bold text-white">{metrics.currentVoltageV}V • {metrics.currentAmpsA}A</span>
                </div>
                <div className="p-2 rounded-xl bg-white/5 border border-white/5">
                  <span className="text-[10px] text-slate-500 block">Nhiệt độ Shelly</span>
                  <span className="text-xs font-bold text-emerald-400">{metrics.batteryTempC}°C</span>
                </div>
              </motion.div>
            )}
          </div>

          {/* Primary Stop Button */}
          <div className="pt-2">
            <button
              type="button"
              onClick={() => setIsStopModalOpen(true)}
              className="w-full py-3.5 rounded-2xl bg-red-500/15 hover:bg-red-500/25 text-red-400 font-bold text-xs border border-red-500/30 flex items-center justify-center gap-2 transition-all active:scale-[0.99] shadow-lg shadow-red-500/10"
            >
              <Power className="w-4 h-4" />
              <span>Dừng sạc</span>
            </button>
          </div>
        </div>
      ) : (
        /* STANDBY / CONFIGURATION VIEW */
        <div className="space-y-4">
          {/* Dual Mode Switcher (Sạc theo AI vs Sạc hẹn giờ) with smooth animated tab indicator */}
          <div className="flex p-1 bg-[#141414] rounded-2xl border border-white/5 relative">
            <button
              type="button"
              onClick={() => setChargeMode('ai')}
              className={`flex-1 py-2.5 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 relative z-10 ${
                chargeMode === 'ai'
                  ? 'text-slate-950 font-black'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              {chargeMode === 'ai' && (
                <motion.div
                  layoutId="chargeModeTab"
                  className="absolute inset-0 bg-emerald-500 rounded-xl shadow-md -z-10"
                  transition={{ type: 'spring', stiffness: 450, damping: 32 }}
                />
              )}
              <Sparkles className="w-3.5 h-3.5" />
              <span>Sạc theo AI</span>
            </button>

            <button
              type="button"
              onClick={() => setChargeMode('timed')}
              className={`flex-1 py-2.5 rounded-xl text-xs font-bold transition-all flex items-center justify-center gap-2 relative z-10 ${
                chargeMode === 'timed'
                  ? 'text-slate-950 font-black'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              {chargeMode === 'timed' && (
                <motion.div
                  layoutId="chargeModeTab"
                  className="absolute inset-0 bg-emerald-500 rounded-xl shadow-md -z-10"
                  transition={{ type: 'spring', stiffness: 450, damping: 32 }}
                />
              )}
              <Clock className="w-3.5 h-3.5" />
              <span>Sạc hẹn giờ</span>
            </button>
          </div>

          <AnimatePresence mode="wait">
            {chargeMode === 'ai' ? (
              /* MODE 1: SẠC THEO AI (Section 4.1 & 8-16) */
              <motion.div
                key="ai-mode"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.2 }}
                className="space-y-4"
              >
                {/* Battery Selector */}
                {metrics.currentPercent >= 100 ? (
                  <div className="p-6 rounded-3xl bg-[#111] border border-white/5 text-center space-y-2 shadow-xl">
                    <div className="w-12 h-12 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center mx-auto">
                      <CheckCircle2 className="w-6 h-6" />
                    </div>
                    <h3 className="text-base font-bold text-white">Pin đã đầy 100%</h3>
                    <p className="text-xs text-slate-400">
                      Xe đã sẵn sàng cho hành trình tiếp theo. Rút sạc khi không sử dụng.
                    </p>
                  </div>
                ) : (
                  <BatteryVisualizer
                    currentPercent={metrics.currentPercent}
                    targetPercent={metrics.targetPercent}
                    isCharging={metrics.isCharging}
                    onTargetChange={onTargetChange}
                    onCurrentChange={onCurrentChange}
                    batteryCapacityKWh={vehicle.batteryCapacityKWh}
                  />
                )}

                {/* AI Prediction & Circular Power Trigger Card */}
                <div className="p-5 rounded-3xl bg-[#111] border border-white/5 relative overflow-hidden shadow-xl space-y-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-emerald-400">
                      <Sparkles className="w-3.5 h-3.5" />
                      <span>Dự báo thời gian</span>
                    </div>

                    <span className={`text-[10px] font-bold px-2.5 py-0.5 rounded-full border ${aiStage.color}`}>
                      {aiStage.label}
                    </span>
                  </div>

                  <div className="flex items-baseline justify-between">
                    <div>
                      <span className="text-2xl font-extrabold text-white font-mono-num">
                        {formatDuration(prediction.estimatedMinutes)}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={onOpenPrediction}
                      className="text-emerald-400 hover:text-emerald-300 font-semibold text-xs flex items-center gap-0.5"
                    >
                      Tinh chỉnh <ChevronRight className="w-3 h-3" />
                    </button>
                  </div>

                  {/* CIRCULAR AI CHARGE BUTTON */}
                  <div className="pt-3 pb-1 flex flex-col items-center justify-center">
                    <div className="relative flex items-center justify-center">
                      {/* Ambient Glowing Halo Animation */}
                      {!(metrics.currentPercent >= 100 || metrics.targetPercent <= metrics.currentPercent) && (
                        <>
                          <motion.div
                            animate={{
                              scale: [1, 1.28, 1],
                              opacity: [0.35, 0.08, 0.35],
                            }}
                            transition={{
                              duration: 2.8,
                              repeat: Infinity,
                              ease: 'easeInOut',
                            }}
                            className="absolute w-32 h-32 rounded-full bg-emerald-500/20 blur-xl pointer-events-none"
                          />
                          <motion.div
                            animate={{
                              scale: [1, 1.15, 1],
                              opacity: [0.6, 0.2, 0.6],
                            }}
                            transition={{
                              duration: 2,
                              repeat: Infinity,
                              ease: 'easeInOut',
                            }}
                            className="absolute w-24 h-24 rounded-full border border-emerald-500/40 pointer-events-none"
                          />
                        </>
                      )}

                      {/* Main Circular AI ON Button */}
                      <motion.button
                        whileHover={{ scale: 1.08 }}
                        whileTap={{ scale: 0.92 }}
                        type="button"
                        onClick={() => setIsStartModalOpen(true)}
                        disabled={metrics.currentPercent >= 100 || metrics.targetPercent <= metrics.currentPercent}
                        className="relative z-10 w-24 h-24 sm:w-28 sm:h-28 rounded-full bg-gradient-to-tr from-emerald-500 via-emerald-400 to-teal-300 text-slate-950 font-black shadow-[0_0_35px_rgba(16,185,129,0.4)] hover:shadow-[0_0_50px_rgba(16,185,129,0.6)] disabled:opacity-35 disabled:pointer-events-none disabled:shadow-none flex flex-col items-center justify-center transition-all border-2 border-emerald-200/40 group active:scale-95"
                      >
                        <motion.div
                          animate={{ rotate: [0, 360] }}
                          transition={{ duration: 20, repeat: Infinity, ease: 'linear' }}
                          className="absolute inset-1 rounded-full border border-dashed border-emerald-950/20 pointer-events-none"
                        />
                        <Sparkles className="w-10 h-10 sm:w-11 sm:h-11 text-slate-950 fill-slate-950 stroke-[1.2] drop-shadow-md group-hover:scale-110 transition-transform" />
                      </motion.button>
                    </div>
                  </div>
                </div>
              </motion.div>
            ) : (
              /* MODE 2: SẠC HẸN GIỜ (Section 4.2) */
              <motion.div
                key="timed-mode"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.2 }}
                className="p-5 rounded-3xl bg-[#111] border border-white/5 space-y-4 shadow-xl"
              >
                <div>
                  <h3 className="text-sm font-bold text-white flex items-center gap-2">
                    <Clock className="w-4 h-4 text-emerald-400" />
                    Thời gian hẹn giờ
                  </h3>
                  <p className="text-xs text-slate-400 mt-1">
                    Bộ sạc tự ngắt bằng bộ đếm giờ phần cứng sau thời gian đã chọn.
                  </p>
                </div>

                {/* Preset buttons with animations */}
                <div className="grid grid-cols-3 gap-2">
                  {timedPresets.map(preset => {
                    const isSelected = timedDurationMinutes === preset.mins;
                    return (
                      <motion.button
                        key={preset.mins}
                        whileHover={{ scale: 1.03 }}
                        whileTap={{ scale: 0.97 }}
                        type="button"
                        onClick={() => setTimedDurationMinutes(preset.mins)}
                        className={`p-3 rounded-2xl border text-center transition-all relative overflow-hidden ${
                          isSelected
                            ? 'bg-emerald-500/20 border-emerald-500 text-white shadow-lg shadow-emerald-500/10'
                            : 'bg-[#141414] border-white/5 text-slate-300 hover:border-white/20'
                        }`}
                      >
                        <span className="text-xs font-bold block">{preset.label}</span>
                        <span className={`text-[9px] font-mono mt-0.5 block ${isSelected ? 'text-emerald-400 font-semibold' : 'text-slate-500'}`}>
                          {preset.badge}
                        </span>
                      </motion.button>
                    );
                  })}
                </div>

                {/* Reassurance note */}
                <div className="p-3 rounded-2xl bg-white/5 border border-white/5 flex items-center gap-2 text-xs text-slate-400">
                  <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                  <span>
                    {timedDurationMinutes === 0
                      ? 'Chế độ sạc trực tiếp không đặt trước thời gian ngắt.'
                      : 'Timer được nạp thẳng vào rơ-le Shelly, an toàn độc lập với điện thoại.'}
                  </span>
                </div>

                {/* CIRCULAR ON/OFF POWER BUTTON (Timed Mode) */}
                <div className="pt-3 pb-1 flex flex-col items-center justify-center">
                  <div className="relative flex items-center justify-center">
                    {/* Ambient Glowing Halo Animation */}
                    <motion.div
                      animate={{
                        scale: [1, 1.28, 1],
                        opacity: [0.35, 0.08, 0.35],
                      }}
                      transition={{
                        duration: 2.8,
                        repeat: Infinity,
                        ease: 'easeInOut',
                      }}
                      className="absolute w-32 h-32 rounded-full bg-emerald-500/20 blur-xl pointer-events-none"
                    />
                    <motion.div
                      animate={{
                        scale: [1, 1.15, 1],
                        opacity: [0.6, 0.2, 0.6],
                      }}
                      transition={{
                        duration: 2,
                        repeat: Infinity,
                        ease: 'easeInOut',
                      }}
                      className="absolute w-24 h-24 rounded-full border border-emerald-500/40 pointer-events-none"
                    />

                    {/* Main Circular Power ON Button */}
                    <motion.button
                      whileHover={{ scale: 1.08 }}
                      whileTap={{ scale: 0.92 }}
                      type="button"
                      onClick={() => setIsStartModalOpen(true)}
                      className="relative z-10 w-24 h-24 sm:w-28 sm:h-28 rounded-full bg-gradient-to-tr from-emerald-500 via-emerald-400 to-teal-300 text-slate-950 font-black shadow-[0_0_35px_rgba(16,185,129,0.4)] hover:shadow-[0_0_50px_rgba(16,185,129,0.6)] flex flex-col items-center justify-center transition-all border-2 border-emerald-200/40 group active:scale-95"
                    >
                      <motion.div
                        animate={{ rotate: [0, 360] }}
                        transition={{ duration: 20, repeat: Infinity, ease: 'linear' }}
                        className="absolute inset-1 rounded-full border border-dashed border-emerald-950/20 pointer-events-none"
                      />
                      <Power className="w-10 h-10 sm:w-11 sm:h-11 stroke-[2.8] text-slate-950 drop-shadow-md group-hover:scale-110 transition-transform" />
                    </motion.button>
                  </div>

                  <p className="text-xs text-slate-300 font-bold mt-3 text-center flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5 text-emerald-400" />
                    <span>
                      {timedDurationMinutes === 0
                        ? 'Sạc trực tiếp'
                        : `Sạc ${timedDurationMinutes} phút`}
                    </span>
                  </p>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      )}

      {/* 5. RECENT SESSIONS SECTION (Tối giản theo Spec Section 36) */}
      <div id="recent-history-section" className="bg-[#111] border border-white/5 rounded-3xl p-5 shadow-xl">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h2 className="text-xs uppercase tracking-widest text-emerald-500 font-bold">Lịch sử sạc gần đây</h2>
            <span className="text-[11px] text-slate-500">{vehicle.name}</span>
          </div>

          <button
            type="button"
            onClick={onNavigateToHistory}
            className="text-xs font-semibold text-emerald-400 hover:text-emerald-300 flex items-center gap-0.5"
          >
            Tất cả
            <ChevronRight className="w-3.5 h-3.5" />
          </button>
        </div>

        {/* Minimal clean session rows */}
        <div className="space-y-2.5">
          {recentSessions.slice(0, 3).map((session) => (
            <button
              key={session.id}
              type="button"
              onClick={() => onOpenSessionDetail(session)}
              className="w-full flex items-center justify-between p-3 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 text-left transition-all"
            >
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center shrink-0">
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <div className="text-xs font-bold text-white">
                    {session.startPercent}% → {session.endPercent}%
                  </div>
                  <div className="text-[11px] text-slate-400">
                    {session.dateStr} • {session.durationMinutes} phút
                  </div>
                </div>
              </div>

              <div className="text-right">
                <div className="text-xs font-mono text-emerald-400 font-bold">
                  {session.energyWh >= 1000 ? `${(session.energyWh / 1000).toFixed(1)} kWh` : `${session.energyWh} Wh`}
                </div>
                <div className="text-[10px] text-slate-500">
                  {session.triggerType === 'auto_target' ? 'Sạc AI' : 'Hẹn giờ'}
                </div>
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* MODALS */}
      <StartChargeModal
        isOpen={isStartModalOpen}
        onClose={() => setIsStartModalOpen(false)}
        onConfirmStart={() => {
          if (chargeMode === 'ai') {
            onStartCharging('ai', metrics.targetPercent);
          } else {
            onStartCharging('timed', timedDurationMinutes);
          }
        }}
        vehicle={vehicle}
        mode={chargeMode}
        currentPercent={Math.round(metrics.currentPercent)}
        targetPercent={metrics.targetPercent}
        timedMinutes={timedDurationMinutes}
        estimatedMinutes={prediction.estimatedMinutes}
        estimatedCompletionTime={prediction.estimatedCompletionTime}
      />

      <StopChargeModal
        isOpen={isStopModalOpen}
        onClose={() => setIsStopModalOpen(false)}
        onConfirmStop={(reason) => {
          onStopCharging(reason);
        }}
        vehicle={vehicle}
        currentPercent={metrics.currentPercent}
        targetPercent={metrics.targetPercent}
        remainingMinutes={prediction.estimatedMinutes}
      />
    </div>
  );
};
