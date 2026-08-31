import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  X, Zap, Clock, TrendingUp, DollarSign, BatteryCharging, 
  Info, CheckCircle2, ShieldCheck, Sparkles, Moon, ArrowRight, Gauge
} from 'lucide-react';
import { Vehicle, ChargerProfile, ChargingPrediction } from '../types';
import { calculateChargingPrediction, formatDuration, formatCurrencyVND } from '../utils/chargingCalculator';

interface PredictionSheetProps {
  isOpen: boolean;
  onClose: () => void;
  vehicle: Vehicle;
  chargers: ChargerProfile[];
  activeChargerId: string;
  onSelectCharger: (id: string) => void;
  currentPercent: number;
  targetPercent: number;
  tariffVNDPerKWh: number;
  onStartChargingWithPreset: () => void;
  onScheduleNightCharge: () => void;
}

export const PredictionSheet: React.FC<PredictionSheetProps> = ({
  isOpen,
  onClose,
  vehicle,
  chargers,
  activeChargerId,
  onSelectCharger,
  currentPercent,
  targetPercent,
  tariffVNDPerKWh,
  onStartChargingWithPreset,
  onScheduleNightCharge,
}) => {
  const currentCharger = chargers.find(c => c.id === activeChargerId) || chargers[0];
  const prediction: ChargingPrediction = calculateChargingPrediction(
    vehicle,
    currentCharger,
    currentPercent,
    targetPercent,
    tariffVNDPerKWh
  );

  const gasSavingsVND = Math.max(0, Math.round((prediction.rangeAddedKm / 100) * 2.2 * 23500) - prediction.estimatedCostVND);

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/80 backdrop-blur-md"
          />

          {/* Android Bottom Sheet / Modal Dialog */}
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 28, stiffness: 300 }}
            className="relative w-full max-w-lg bg-[#0c0c0c] border-t sm:border border-white/10 rounded-t-[36px] sm:rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[90vh] overflow-y-auto"
          >
            {/* Sheet Handle */}
            <div className="w-12 h-1 bg-white/20 rounded-full mx-auto mb-4 sm:hidden" />

            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center shadow-lg shadow-emerald-500/20">
                  <Sparkles className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white flex items-center gap-1.5">
                    Dự đoán thời gian sạc
                  </h3>
                  <p className="text-xs text-slate-400">
                    Thuật toán mô phỏng đường cong sạc LFP
                  </p>
                </div>
              </div>

              <button
                type="button"
                onClick={onClose}
                aria-label="Đóng"
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center hover:bg-white/10 border border-white/5 transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Main Result Card */}
            <div className="mt-4 p-5 rounded-3xl bg-[#111] border border-emerald-500/30 relative overflow-hidden shadow-xl">
              <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/10 blur-3xl -mr-16 -mt-16 pointer-events-none"></div>

              <div className="flex items-center justify-between">
                <div>
                  <span className="text-xs font-bold uppercase tracking-widest text-emerald-500">Thời gian sạc dự kiến</span>
                  <div className="text-2xl md:text-3xl font-extrabold text-white font-mono-num mt-0.5">
                    {formatDuration(prediction.estimatedMinutes)}
                  </div>
                  <div className="text-xs text-slate-300 mt-1.5 flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Dự kiến xong lúc:</span>
                    <strong className="text-emerald-400 font-mono-num bg-white/5 px-2 py-0.5 rounded-lg border border-white/10">
                      {prediction.estimatedCompletionTime}
                    </strong>
                  </div>
                </div>

                <div className="text-right">
                  <div className="w-16 h-16 rounded-2xl bg-[#050505] border border-emerald-500/40 flex flex-col items-center justify-center shadow-inner">
                    <span className="text-[10px] text-slate-400">Nạp thêm</span>
                    <span className="text-lg font-bold text-emerald-400 font-mono-num">+{prediction.deltaPercent}%</span>
                  </div>
                </div>
              </div>

              {/* Progress Summary bar */}
              <div className="mt-4 pt-4 border-t border-white/5 grid grid-cols-3 gap-2 text-center">
                <div className="bg-white/5 p-2 rounded-xl border border-white/5">
                  <span className="text-[10px] text-slate-400 block">Năng lượng</span>
                  <span className="text-xs font-bold text-slate-100 font-mono-num">
                    +{(prediction.energyNeededWh / 1000).toFixed(2)} kWh
                  </span>
                </div>

                <div className="bg-white/5 p-2 rounded-xl border border-white/5">
                  <span className="text-[10px] text-slate-400 block">Quãng đường</span>
                  <span className="text-xs font-bold text-emerald-400 font-mono-num">
                    +{prediction.rangeAddedKm} km
                  </span>
                </div>

                <div className="bg-white/5 p-2 rounded-xl border border-white/5">
                  <span className="text-[10px] text-slate-400 block">Công suất</span>
                  <span className="text-xs font-bold text-emerald-300 font-mono-num">
                    {currentCharger.powerW >= 1000 ? `${(currentCharger.powerW / 1000).toFixed(1)} kW` : `${currentCharger.powerW} W`}
                  </span>
                </div>
              </div>
            </div>

            {/* Charger Power Selection */}
            <div className="mt-4">
              <label className="text-xs font-bold text-slate-400 uppercase tracking-widest block mb-2">
                Công suất củ sạc đang dùng
              </label>
              <div className="grid grid-cols-2 gap-2">
                {chargers.map((ch) => {
                  const isSelected = ch.id === activeChargerId;
                  return (
                    <button
                      key={ch.id}
                      type="button"
                      onClick={() => onSelectCharger(ch.id)}
                      className={`p-3 rounded-2xl text-left border transition-all ${
                        isSelected
                          ? 'bg-emerald-500/20 border-emerald-500 text-white shadow-sm shadow-emerald-500/20'
                          : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <span className={`text-xs font-bold ${isSelected ? 'text-emerald-400' : 'text-slate-200'}`}>
                          {ch.powerW >= 1000 ? `${ch.powerW / 1000} kW` : `${ch.powerW} W`}
                        </span>
                        {isSelected && <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />}
                      </div>
                      <p className="text-[11px] text-slate-400 mt-0.5 truncate">{ch.name}</p>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Charging Curve Breakdown / Phases */}
            <div className="mt-4 p-4 rounded-3xl bg-[#111] border border-white/5">
              <div className="flex items-center justify-between text-xs text-slate-300 mb-2.5">
                <span className="font-semibold flex items-center gap-1.5">
                  <Gauge className="w-3.5 h-3.5 text-emerald-400" />
                  Đường cong sạc chi tiết
                </span>
                <span className="text-[11px] text-slate-400 font-mono">Pin {vehicle.batteryType}</span>
              </div>

              <div className="space-y-2">
                {prediction.phases.map((ph, idx) => (
                  <div key={idx} className="flex items-center justify-between text-xs bg-white/5 p-2.5 rounded-2xl border border-white/5">
                    <div>
                      <div className="font-medium text-slate-200 flex items-center gap-1.5">
                        <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                        {ph.name} • {ph.fromPercent}% → {ph.toPercent}%
                      </div>
                      <div className="text-[10px] text-slate-400">{ph.description}</div>
                    </div>
                    <div className="text-right">
                      <div className="font-bold text-slate-100 font-mono-num">{formatDuration(ph.minutes)}</div>
                      <div className="text-[10px] text-emerald-400 font-mono-num">{ph.powerW} W</div>
                    </div>
                  </div>
                ))}
              </div>

              {prediction.targetPercent > 85 && (
                <div className="mt-3 p-3 rounded-2xl bg-amber-500/10 border border-amber-500/20 text-[11px] text-amber-300 flex items-start gap-2">
                  <Info className="w-3.5 h-3.5 text-amber-400 shrink-0 mt-0.5" />
                  <span>
                    Từ 85% đến 100%, bộ sạc giảm dòng để cân bằng cell pin, bảo vệ tuổi thọ tối đa.
                  </span>
                </div>
              )}
            </div>

            {/* Battery Health Assurance */}
            <div className="mt-3 flex items-center justify-between px-4 py-2.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-xs">
              <span className="text-emerald-300 flex items-center gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                Bảo vệ cell LFP:
              </span>
              <strong className="text-emerald-400">
                Tự ngắt khi đạt {targetPercent}%
              </strong>
            </div>

            {/* Action Buttons */}
            <div className="mt-5 grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <button
                type="button"
                onClick={() => {
                  onScheduleNightCharge();
                  onClose();
                }}
                className="py-3.5 px-4 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-200 font-semibold text-xs flex items-center justify-center gap-2 border border-white/5 transition-colors"
              >
                <Moon className="w-4 h-4 text-emerald-400" />
                Sạc giờ đêm
              </button>

              <button
                type="button"
                onClick={() => {
                  onStartChargingWithPreset();
                  onClose();
                }}
                className="py-3.5 px-4 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs flex items-center justify-center gap-2 shadow-lg shadow-emerald-500/25 transition-all active:scale-[0.98]"
              >
                <Zap className="w-4 h-4 fill-current" />
                Bắt đầu sạc ngay
                <ArrowRight className="w-3.5 h-3.5 ml-1" />
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};

