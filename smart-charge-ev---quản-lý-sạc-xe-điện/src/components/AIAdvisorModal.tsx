import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Sparkles, BatteryCharging, TrendingDown, Clock, ShieldCheck, Check } from 'lucide-react';
import { Vehicle } from '../types';

interface AIAdvisorModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicle: Vehicle;
}

export const AIAdvisorModal: React.FC<AIAdvisorModalProps> = ({
  isOpen,
  onClose,
  vehicle,
}) => {
  const [smartCommuteTime, setSmartCommuteTime] = useState('07:30');
  const [targetSoc, setTargetSoc] = useState(80);
  const [isDegradationProtection, setIsDegradationProtection] = useState(true);

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
            initial={{ scale: 0.95, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.95, opacity: 0 }}
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[85vh] overflow-y-auto"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Sparkles className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">AI Sạc Cá Nhân Hóa</h3>
                  <p className="text-[11px] text-slate-400">Thuật toán máy học riêng cho {vehicle.name}</p>
                </div>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="mt-4 space-y-3.5">
              {/* Vehicle AI Profile */}
              <div className="p-4 rounded-2xl bg-[#050505] border border-white/5">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-white">{vehicle.name}</span>
                  <span className="text-[10px] font-mono bg-emerald-500/20 text-emerald-400 px-2 py-0.5 rounded-full border border-emerald-500/30">
                    SOH: 99.2%
                  </span>
                </div>
                <div className="text-xs text-slate-400 leading-relaxed">
                  Mô hình AI đã phân tích <span className="text-emerald-400 font-semibold">14 chu kỳ sạc</span> gần nhất và thiết lập đường cong CC/CV tối ưu cho cell pin {vehicle.batteryType}.
                </div>
              </div>

              {/* Smart Feature 1: Departure Time Auto Ready */}
              <div className="p-3.5 rounded-2xl bg-white/5 border border-white/5">
                <div className="flex items-center justify-between mb-1.5">
                  <div className="flex items-center gap-2">
                    <Clock className="w-4 h-4 text-emerald-400" />
                    <span className="text-xs font-bold text-white">Giờ xuất phát đi làm</span>
                  </div>
                  <input
                    type="time"
                    value={smartCommuteTime}
                    onChange={(e) => setSmartCommuteTime(e.target.value)}
                    className="bg-[#050505] border border-white/10 rounded-xl px-2 py-1 text-xs font-mono text-emerald-400 focus:outline-none"
                  />
                </div>
                <p className="text-[11px] text-slate-400 leading-relaxed">
                  Hệ thống tự lùi giờ bắt đầu sạc vào ban đêm sao cho xe đạt đúng {targetSoc}% ngay trước {smartCommuteTime}, hạn chế pin nằm ở mức điện áp cao lâu gây chai pin.
                </p>
              </div>

              {/* Smart Feature 2: Degradation Protection */}
              <div className="p-3.5 rounded-2xl bg-white/5 border border-white/5 flex items-center justify-between">
                <div className="flex items-start gap-2.5">
                  <TrendingDown className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <div>
                    <div className="text-xs font-bold text-white">Bảo vệ suy hao theo nhiệt độ</div>
                    <div className="text-[11px] text-slate-400 mt-0.5">Tự giảm công suất khi trưa nắng nóng &gt;38°C</div>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setIsDegradationProtection(!isDegradationProtection)}
                  className={`w-10 h-6 rounded-full p-0.5 transition-colors shrink-0 ${
                    isDegradationProtection ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-5 h-5 rounded-full bg-white transition-transform shadow-sm ${
                    isDegradationProtection ? 'translate-x-4' : 'translate-x-0'
                  }`} />
                </button>
              </div>
            </div>

            <div className="mt-5">
              <button
                type="button"
                onClick={onClose}
                className="w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20"
              >
                Lưu cấu hình AI
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
