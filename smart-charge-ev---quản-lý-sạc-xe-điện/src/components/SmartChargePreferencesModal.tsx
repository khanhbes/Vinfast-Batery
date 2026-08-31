import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, BatteryCharging, Shield, Check, Lock, Bell, AlertTriangle } from 'lucide-react';
import { AppSettings } from '../types';

interface SmartChargePreferencesModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const SmartChargePreferencesModal: React.FC<SmartChargePreferencesModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
  const [targetPercent, setTargetPercent] = useState(settings.defaultTargetPercent || 80);
  const [notifyComplete, setNotifyComplete] = useState(settings.notifyOnTargetReached ?? true);
  const [notifyInterrupted, setNotifyInterrupted] = useState(settings.notifyOnInterrupted ?? true);
  const [savedSuccess, setSavedSuccess] = useState(false);

  const handleSave = () => {
    onUpdateSettings({
      defaultTargetPercent: targetPercent,
      notifyOnTargetReached: notifyComplete,
      notifyOnInterrupted: notifyInterrupted,
    });
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
      onClose();
    }, 600);
  };

  const targetPresets = [
    { pct: 80, label: '80% (Khuyên dùng)', desc: 'Tối ưu tuổi thọ cell pin LFP hàng ngày' },
    { pct: 90, label: '90% (Cân bằng)', desc: 'Thêm quãng đường di chuyển' },
    { pct: 100, label: '100% (Đầy bình)', desc: 'Chạy đường dài / Cân bằng cell định kỳ' },
  ];

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
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[88vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <BatteryCharging className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Sạc thông minh</h3>
                  <p className="text-[11px] text-slate-400">Tùy chọn hành vi sạc tự động an toàn</p>
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
              {/* Target Percent Selection */}
              <div className="space-y-2">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Mức pin thường dùng
                </label>
                <div className="grid grid-cols-1 gap-2">
                  {targetPresets.map((preset) => {
                    const isSelected = targetPercent === preset.pct;
                    return (
                      <button
                        key={preset.pct}
                        type="button"
                        onClick={() => setTargetPercent(preset.pct)}
                        className={`p-3.5 rounded-2xl border text-left flex items-start justify-between transition-colors ${
                          isSelected
                            ? 'bg-emerald-500/10 border-emerald-500 shadow-sm'
                            : 'bg-[#111] border-white/5 hover:border-white/20'
                        }`}
                      >
                        <div>
                          <div className="text-xs font-bold text-white">{preset.label}</div>
                          <div className="text-[11px] text-slate-400 mt-0.5">{preset.desc}</div>
                        </div>
                        {isSelected && <Check className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Safety lock: Confirm when stopping charge */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-xl bg-white/5 text-slate-400 flex items-center justify-center">
                    <Shield className="w-4 h-4 text-emerald-400" />
                  </div>
                  <div>
                    <div className="text-xs font-bold text-white">Xác nhận khi dừng sạc</div>
                    <div className="text-[10px] text-slate-400 mt-0.5">Luôn bật vì an toàn dòng điện</div>
                  </div>
                </div>
                <span className="px-2.5 py-1 rounded-full bg-white/5 text-slate-400 text-[10px] font-semibold flex items-center gap-1">
                  <Lock className="w-3 h-3" />
                  Mặc định
                </span>
              </div>

              {/* Reminder on complete */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Nhắc khi sạc hoàn tất</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Thông báo ngay khi pin đạt mức đích</div>
                </div>
                <button
                  type="button"
                  onClick={() => setNotifyComplete(!notifyComplete)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    notifyComplete ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    notifyComplete ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              {/* Reminder on interrupted */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Nhắc khi sạc bị gián đoạn</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Cảnh báo nếu mất nguồn đột ngột hoặc ngắt an toàn</div>
                </div>
                <button
                  type="button"
                  onClick={() => setNotifyInterrupted(!notifyInterrupted)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    notifyInterrupted ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    notifyInterrupted ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              <div className="p-3 rounded-2xl bg-white/[0.02] border border-white/5 text-[11px] text-slate-500 leading-relaxed">
                Ngưỡng an toàn phần cứng (nhiệt độ cắt 45°C, quá áp &gt;250V, chống ngắn mạch) được quản lý tự động bởi phần cứng và máy chủ.
              </div>
            </div>

            {/* Actions */}
            <div className="mt-5 flex gap-2">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
              >
                Hủy
              </button>
              <button
                type="button"
                onClick={handleSave}
                className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-1.5"
              >
                {savedSuccess ? <Check className="w-4 h-4 stroke-[3]" /> : null}
                {savedSuccess ? 'Đã lưu' : 'Lưu tùy chọn'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
