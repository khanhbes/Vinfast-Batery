import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Power, AlertTriangle, Check, ShieldAlert } from 'lucide-react';
import { Vehicle } from '../types';

interface StopChargeModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirmStop: (reason: string) => void;
  vehicle: Vehicle;
  currentPercent: number;
  targetPercent: number;
  remainingMinutes: number;
}

export const StopChargeModal: React.FC<StopChargeModalProps> = ({
  isOpen,
  onClose,
  onConfirmStop,
  vehicle,
  currentPercent,
  targetPercent,
  remainingMinutes,
}) => {
  const [selectedReason, setSelectedReason] = useState<string>('need_vehicle');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const reasons = [
    { id: 'need_vehicle', label: 'Cần dùng xe gấp' },
    { id: 'enough_charge', label: 'Pin đã đủ dùng' },
    { id: 'safety_concern', label: 'Lo ngại an toàn' },
    { id: 'other', label: 'Lý do khác' },
  ];

  const handleStop = () => {
    if (isSubmitting) return;
    setIsSubmitting(true);
    setTimeout(() => {
      onConfirmStop(selectedReason);
      setIsSubmitting(false);
      onClose();
    }, 350);
  };

  const formatHoursMinutes = (mins: number) => {
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
            className="relative w-full max-w-sm bg-[#0e0e0e] border border-red-500/30 rounded-3xl p-5 md:p-6 shadow-2xl z-10 overflow-hidden"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-red-500/20 text-red-400 border border-red-500/30 flex items-center justify-center">
                  <Power className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Dừng sạc?</h3>
                  <p className="text-[11px] text-slate-400">{vehicle.name}</p>
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

            {/* Current State Info */}
            <div className="mt-4 p-4 rounded-2xl bg-[#141414] border border-white/5 space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Mức pin hiện tại</span>
                <span className="text-sm font-extrabold text-white font-mono-num">
                  {Math.round(currentPercent)}%
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Mục tiêu ban đầu</span>
                <span className="text-xs font-bold text-emerald-400 font-mono-num">
                  {targetPercent}%
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-xs text-slate-400 font-medium">Thời gian còn lại</span>
                <span className="text-xs font-bold text-slate-300 font-mono-num">
                  {formatHoursMinutes(remainingMinutes)}
                </span>
              </div>
            </div>

            {/* Reason selector for business analytics */}
            <div className="mt-4 space-y-2">
              <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider block">
                Lý do dừng sạc
              </label>
              <div className="grid grid-cols-2 gap-2">
                {reasons.map((r) => {
                  const isSelected = selectedReason === r.id;
                  return (
                    <button
                      key={r.id}
                      type="button"
                      onClick={() => setSelectedReason(r.id)}
                      className={`p-2.5 rounded-2xl text-xs font-medium border text-left transition-colors flex items-center justify-between ${
                        isSelected
                          ? 'bg-red-500/15 border-red-500/40 text-red-300'
                          : 'bg-[#141414] border-white/5 text-slate-400 hover:text-white hover:bg-white/5'
                      }`}
                    >
                      <span>{r.label}</span>
                      {isSelected && <Check className="w-3.5 h-3.5 text-red-400 stroke-[3]" />}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Action Buttons */}
            <div className="mt-5 flex gap-2">
              <button
                type="button"
                onClick={onClose}
                disabled={isSubmitting}
                className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-bold border border-white/5 transition-colors"
              >
                Tiếp tục sạc
              </button>

              <button
                type="button"
                onClick={handleStop}
                disabled={isSubmitting}
                className="flex-1 py-3 rounded-2xl bg-red-500 hover:bg-red-600 text-white text-xs font-bold shadow-lg shadow-red-500/25 transition-all flex items-center justify-center gap-1.5 active:scale-[0.98]"
              >
                {isSubmitting ? (
                  <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  <>
                    <Power className="w-3.5 h-3.5" />
                    <span>Dừng sạc</span>
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
