import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, BatteryCharging, Sparkles, Plus, Minus, Check, ThumbsUp } from 'lucide-react';
import { Vehicle } from '../types';

interface ConfirmEndSocModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirmActualSoc: (actualSoc: number) => void;
  vehicle: Vehicle;
  suggestedSoc: number;
}

export const ConfirmEndSocModal: React.FC<ConfirmEndSocModalProps> = ({
  isOpen,
  onClose,
  onConfirmActualSoc,
  vehicle,
  suggestedSoc,
}) => {
  const [actualSoc, setActualSoc] = useState(suggestedSoc);
  const [isSaved, setIsSaved] = useState(false);

  const increment = () => setActualSoc(p => Math.min(100, p + 1));
  const decrement = () => setActualSoc(p => Math.max(1, p - 1));

  const handleConfirm = () => {
    setIsSaved(true);
    setTimeout(() => {
      onConfirmActualSoc(actualSoc);
      setIsSaved(false);
      onClose();
    }, 600);
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
                  <BatteryCharging className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Xác nhận % pin thực tế</h3>
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

            {/* Stepper Card */}
            <div className="mt-4 p-5 rounded-2xl bg-[#141414] border border-white/5 text-center space-y-3">
              <span className="text-xs text-slate-400 block font-medium">
                Mức pin hiển thị trên đồng hồ xe sau khi sạc
              </span>

              <div className="flex items-center justify-center gap-4">
                <button
                  type="button"
                  onClick={decrement}
                  className="w-10 h-10 rounded-2xl bg-white/5 hover:bg-white/10 active:bg-white/20 border border-white/10 text-white flex items-center justify-center transition-colors text-base font-bold"
                >
                  <Minus className="w-4 h-4" />
                </button>

                <div className="min-w-24">
                  <span className="text-4xl font-black text-emerald-400 font-mono-num">
                    {actualSoc}%
                  </span>
                </div>

                <button
                  type="button"
                  onClick={increment}
                  className="w-10 h-10 rounded-2xl bg-white/5 hover:bg-white/10 active:bg-white/20 border border-white/10 text-white flex items-center justify-center transition-colors text-base font-bold"
                >
                  <Plus className="w-4 h-4" />
                </button>
              </div>

              {actualSoc === suggestedSoc ? (
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-500/10 text-emerald-400 text-[11px] font-medium border border-emerald-500/20">
                  <Check className="w-3 h-3" />
                  Khớp với ước tính của hệ thống
                </div>
              ) : (
                <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-sky-500/10 text-sky-400 text-[11px] font-medium border border-sky-500/20">
                  Chênh lệch {actualSoc - suggestedSoc > 0 ? `+${actualSoc - suggestedSoc}` : `${actualSoc - suggestedSoc}`}% so với ước tính
                </div>
              )}
            </div>

            {/* Value for Personal AI notice */}
            <div className="mt-3.5 p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-start gap-2.5">
              <Sparkles className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
              <p className="text-[11px] text-slate-300 leading-relaxed">
                Dữ liệu thực tế này sẽ giúp <strong>AI cá nhân</strong> của {vehicle.name} học dung lượng pin và tính thời gian sạc chuẩn xác hơn cho các lần sạc tới.
              </p>
            </div>

            {/* Actions */}
            <div className="mt-5 flex gap-2">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-bold border border-white/5 transition-colors"
              >
                Để sau
              </button>

              <button
                type="button"
                onClick={handleConfirm}
                disabled={isSaved}
                className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-bold shadow-lg shadow-emerald-500/25 transition-all flex items-center justify-center gap-1.5 active:scale-[0.98]"
              >
                {isSaved ? (
                  <>
                    <Check className="w-3.5 h-3.5 stroke-[3]" />
                    <span>Đã lưu vào AI!</span>
                  </>
                ) : (
                  <>
                    <ThumbsUp className="w-3.5 h-3.5" />
                    <span>Xác nhận</span>
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
