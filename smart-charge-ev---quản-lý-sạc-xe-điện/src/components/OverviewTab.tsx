import React from 'react';
import { motion } from 'motion/react';
import { 
  Zap, Battery, ShieldCheck, MapPin, Lock, Unlock, 
  Key, Radio, Gauge, Compass, AlertCircle, Sparkles, Navigation,
  Clock, Thermometer
} from 'lucide-react';
import { Vehicle, LiveChargingMetrics } from '../types';

interface OverviewTabProps {
  vehicle: Vehicle;
  metrics: LiveChargingMetrics;
  onNavigateToCharging: () => void;
}

export const OverviewTab: React.FC<OverviewTabProps> = ({
  vehicle,
  metrics,
  onNavigateToCharging,
}) => {
  const [isLocked, setIsLocked] = React.useState(true);
  const [isTrunkOpen, setIsTrunkOpen] = React.useState(false);
  const [showLocationAlert, setShowLocationAlert] = React.useState(false);

  const currentRangeKm = Math.round((metrics.currentPercent / 100) * vehicle.maxRangeKm);

  return (
    <div id="overview-view" className="space-y-4 pb-20 pt-1">
      {/* Header Info */}
      <div className="flex items-center justify-between px-1">
        <div>
          <span className="text-[10px] font-bold text-emerald-400 uppercase tracking-widest">Garage xe điện</span>
          <h1 className="text-xl md:text-2xl font-extrabold text-white tracking-tight">
            {vehicle.name}
          </h1>
        </div>

        <div className="flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-semibold">
          <Radio className="w-3.5 h-3.5 animate-pulse" />
          Online (4G/BLE)
        </div>
      </div>

      {/* Vehicle Hero Card with Range & Battery */}
      <div className="bg-[#111] border border-white/5 rounded-3xl p-5 shadow-2xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/10 blur-3xl -mr-16 -mt-16 pointer-events-none"></div>

        <div className="flex items-start justify-between">
          <div>
            <span className="text-xs font-bold uppercase tracking-widest text-slate-400">
              Quãng đường khả dụng
            </span>
            <div className="flex items-baseline gap-1 mt-1">
              <span className="text-4xl font-extrabold text-white font-mono-num tracking-tight">
                {currentRangeKm}
              </span>
              <span className="text-sm font-bold text-emerald-400">km</span>
            </div>
            <p className="text-xs text-slate-400 mt-1">
              Mức pin hiện tại: <strong className="text-emerald-400 font-mono-num">{metrics.currentPercent}%</strong> / {vehicle.batteryCapacityKWh} kWh
            </p>
          </div>

          <div className="text-right">
            <div className="w-14 h-14 rounded-2xl bg-white/5 border border-white/5 flex flex-col items-center justify-center">
              <Battery className="w-6 h-6 text-emerald-400" />
              <span className="text-[10px] font-bold text-white mt-0.5">{metrics.currentPercent}%</span>
            </div>
          </div>
        </div>

        {/* Quick Vehicle Remote Controls */}
        <div className="mt-5 pt-4 border-t border-white/5 grid grid-cols-3 gap-2">
          <button
            type="button"
            onClick={() => setIsLocked(!isLocked)}
            className={`p-3 rounded-2xl border text-center transition-all flex flex-col items-center gap-1.5 ${
              isLocked
                ? 'bg-white/5 border-white/5 text-slate-300 hover:bg-white/10'
                : 'bg-amber-500/15 border-amber-500/40 text-amber-300'
            }`}
          >
            {isLocked ? <Lock className="w-5 h-5 text-emerald-400" /> : <Unlock className="w-5 h-5 text-amber-400" />}
            <span className="text-xs font-semibold">{isLocked ? 'Đã khóa xe' : 'Đang mở khóa'}</span>
          </button>

          <button
            type="button"
            onClick={() => setIsTrunkOpen(!isTrunkOpen)}
            className={`p-3 rounded-2xl border text-center transition-all flex flex-col items-center gap-1.5 ${
              isTrunkOpen
                ? 'bg-emerald-500/20 border-emerald-500/40 text-emerald-300'
                : 'bg-white/5 border-white/5 text-slate-300 hover:bg-white/10'
            }`}
          >
            <Key className="w-5 h-5 text-slate-300" />
            <span className="text-xs font-semibold">{isTrunkOpen ? 'Đã mở cốp' : 'Mở cốp xe'}</span>
          </button>

          <button
            type="button"
            onClick={onNavigateToCharging}
            className="p-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-center transition-all flex flex-col items-center gap-1.5 shadow-lg shadow-emerald-500/25 active:scale-95"
          >
            <Zap className="w-5 h-5 fill-current" />
            <span className="text-xs font-bold">Vào sạc pin</span>
          </button>
        </div>
      </div>

      {/* Bento Grid: Vehicle Telemetry & Health */}
      <div className="grid grid-cols-2 gap-3">
        {/* Battery Health SOH */}
        <div className="p-4 rounded-3xl bg-[#111] border border-white/5 shadow-xl">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span className="flex items-center gap-1 font-semibold text-slate-300">
              <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
              Sức khỏe Pin (SOH)
            </span>
            <span className="text-emerald-400 font-bold">Rất tốt</span>
          </div>
          <div className="text-2xl font-extrabold text-white font-mono-num mt-2">
            99.2%
          </div>
          <p className="text-[11px] text-slate-400 mt-1">
            Pin LFP độ bền ~2000 chu kỳ sạc
          </p>
        </div>

        {/* Odometer */}
        <div className="p-4 rounded-3xl bg-[#111] border border-white/5 shadow-xl">
          <div className="flex items-center justify-between text-slate-400 text-xs">
            <span className="flex items-center gap-1 font-semibold text-slate-300">
              <Gauge className="w-3.5 h-3.5 text-slate-300" />
              Odo tổng cộng
            </span>
          </div>
          <div className="text-2xl font-extrabold text-white font-mono-num mt-2">
            {vehicle.odometerKm.toLocaleString('vi-VN')} <span className="text-xs text-slate-400 font-normal">km</span>
          </div>
          <p className="text-[11px] text-slate-400 mt-1">
            Bảo dưỡng: 5.000 km
          </p>
        </div>

        {/* Location / Parking */}
        <div className="p-4 rounded-3xl bg-[#111] border border-white/5 col-span-2 flex items-center justify-between shadow-xl">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-2xl bg-white/5 border border-white/5 text-emerald-400 flex items-center justify-center">
              <MapPin className="w-5 h-5" />
            </div>
            <div>
              <div className="text-xs font-semibold text-white">Vị trí đỗ xe hiện tại</div>
              <div className="text-xs text-slate-400">Trạm sạc VinFast Times City, Hà Nội</div>
            </div>
          </div>

          <button
            type="button"
            onClick={() => setShowLocationAlert(true)}
            className="px-3.5 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-xs text-emerald-400 font-medium flex items-center gap-1 border border-white/5 transition-colors"
          >
            <Navigation className="w-3.5 h-3.5" />
            Tìm xe
          </button>
        </div>
      </div>

      {showLocationAlert && (
        <div className="p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl text-xs text-emerald-300 flex items-center justify-between">
          <span>Đã gửi tọa độ xe (20.9958° N, 105.8674° E) đến Google Maps.</span>
          <button onClick={() => setShowLocationAlert(false)} className="text-slate-400 hover:text-white text-xs ml-2">Đóng</button>
        </div>
      )}
    </div>
  );
};

