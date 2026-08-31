import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Zap, Clock, ShieldCheck, BatteryCharging, Sparkles, Check } from 'lucide-react';
import { Vehicle } from '../types';

interface StartChargeModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirmStart: () => void;
  vehicle: Vehicle;
  mode: 'ai' | 'timed';
  currentPercent: number;
  targetPercent: number;
  timedMinutes?: number;
  estimatedMinutes: number;
  estimatedCompletionTime: string;
}

export const StartChargeModal: React.FC<StartChargeModalProps> = ({
  isOpen,
  onClose,
  onConfirmStart,
  vehicle,
  mode,
  currentPercent,
  targetPercent,
  timedMinutes = 120,
  estimatedMinutes,
  estimatedCompletionTime,
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleStart = () => {
    if (isSubmitting) return;
    setIsSubmitting(true);
    // Simulate idempotent verified relay start
    setTimeout(() => {
      onConfirmStart();
      setIsSubmitting(false);
      onClose();
    }, 450);
  };

  const formatHoursMinutes = (mins: number) => {
    if (mins === 0) return 'Ngay lập tức';
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    if (h === 0) return `${m} phút`;
    if (m === 0) return `${h} giờ`;
    return `${h} giờ ${m} phút`;
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/80 backdrop-blur-md"
          />

          <motion.div
            initial={{ scale: 0.95, opacity: 0, y: 10 }}
            animate={{ scale: 1, opacity: 1, y: 0 }}
            exit={{ scale: 0.95, opacity: 0, y: 10 }}
            className="relative w-full max-w-sm bg-[#0e0e0e] border border-emerald-500/30 rounded-3xl p-5 md:p-6 shadow-2xl z-10 overflow-hidden"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Bắt đầu sạc?</h3>
                  <p className="text-[11px] text-slate-400">
                    {mode === 'ai' ? 'Sạc thông minh theo AI' : 'Sạc hẹn giờ trực tiếp'}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5 transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Vehicle & Target Card */}
            <div className="mt-4 p-4 rounded-2xl bg-[#141414] border border-white/5 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Phương tiện</span>
                <span className="text-xs font-bold text-white">{vehicle.name}</span>
              </div>

              {mode === 'ai' ? (
                <>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400 font-medium">Mục tiêu pin</span>
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs text-slate-400">{currentPercent}% →</span>
                      <span className="text-sm font-extrabold text-emerald-400 font-mono-num">
                        {targetPercent}%
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400 font-medium">Dự kiến hoàn tất</span>
                    <span className="text-xs font-bold text-white font-mono-num">
                      {formatHoursMinutes(estimatedMinutes)} • {estimatedCompletionTime}
                    </span>
                  </div>
                </>
              ) : (
                <>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400 font-medium">Thời gian hẹn giờ</span>
                    <span className="text-sm font-extrabold text-emerald-400 font-mono-num">
                      {formatHoursMinutes(timedMinutes)}
                    </span>
                  </div>
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-400 font-medium">Tự ngắt lúc</span>
                    <span className="text-xs font-bold text-white font-mono-num">
                      {timedMinutes === 0
                        ? 'Thủ công hoặc khi đầy'
                        : new Date(Date.now() + timedMinutes * 60000).toLocaleTimeString('vi-VN', {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                    </span>
                  </div>
                </>
              )}
            </div>

            {/* Hardware safety timer reassurance */}
            <div className="mt-3.5 p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-start gap-2.5">
              <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
              <p className="text-[11px] text-slate-300 leading-relaxed">
                Bộ đếm giờ tự ngắt sẽ được kích hoạt trực tiếp trên thiết bị Shelly. Bộ sạc sẽ tự ngắt an toàn ngay cả khi điện thoại tắt mạng.
              </p>
            </div>

            {/* Action Buttons */}
            <div className="mt-5 flex gap-2">
              <button
                type="button"
                onClick={onClose}
                disabled={isSubmitting}
                className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-bold border border-white/5 transition-colors"
              >
                Hủy
              </button>

              <button
                type="button"
                onClick={handleStart}
                disabled={isSubmitting}
                className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-bold shadow-lg shadow-emerald-500/25 transition-all flex items-center justify-center gap-1.5 active:scale-[0.98]"
              >
                {isSubmitting ? (
                  <div className="w-4 h-4 border-2 border-slate-950 border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <Zap className="w-3.5 h-3.5 fill-current" />
                    <span>Bắt đầu sạc</span>
                  </>
                )}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
