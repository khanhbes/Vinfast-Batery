import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Moon, Sun, Monitor, Smartphone, Check, Sparkles, Vibrate } from 'lucide-react';
import { AppSettings } from '../types';

interface AppearanceSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const AppearanceSettingsModal: React.FC<AppearanceSettingsModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
  const [theme, setTheme] = useState(settings.theme || 'system');
  const [motionReduction, setMotionReduction] = useState(settings.motionReduction ?? false);
  const [haptic, setHaptic] = useState(settings.hapticFeedback ?? true);
  const [savedSuccess, setSavedSuccess] = useState(false);

  const handleSave = () => {
    onUpdateSettings({
      theme: theme as any,
      motionReduction,
      hapticFeedback: haptic,
    });
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
      onClose();
    }, 600);
  };

  const themes = [
    { id: 'system', label: 'Theo hệ thống', desc: 'Tự động đồng bộ với cài đặt Android', icon: Monitor },
    { id: 'dark', label: 'Tối Obsidian', desc: 'Màu nền than chì êm dịu ban đêm', icon: Moon },
    { id: 'amoled', label: 'Pure AMOLED (#000)', desc: 'Nền đen tuyệt đối, tiết kiệm pin tối đa', icon: Smartphone },
    { id: 'light', label: 'Sáng Clean', desc: 'Độ tương phản cao ngoài trời', icon: Sun },
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
                  <Moon className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Giao diện</h3>
                  <p className="text-[11px] text-slate-400">Tùy biến hiển thị và hiệu ứng mượt mà</p>
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

            <div className="mt-4 space-y-4">
              {/* Theme Options */}
              <div className="space-y-2">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Chế độ hiển thị
                </label>
                <div className="space-y-2">
                  {themes.map((t) => {
                    const isSelected = theme === t.id;
                    const Icon = t.icon;
                    return (
                      <button
                        key={t.id}
                        type="button"
                        onClick={() => setTheme(t.id as any)}
                        className={`w-full p-3.5 rounded-2xl border text-left flex items-center justify-between transition-colors ${
                          isSelected
                            ? 'bg-emerald-500/10 border-emerald-500 shadow-sm'
                            : 'bg-[#111] border-white/5 hover:border-white/20'
                        }`}
                      >
                        <div className="flex items-center gap-3">
                          <div className={`w-8 h-8 rounded-xl flex items-center justify-center ${
                            isSelected ? 'bg-emerald-500 text-slate-950' : 'bg-white/5 text-slate-400'
                          }`}>
                            <Icon className="w-4 h-4" />
                          </div>
                          <div>
                            <div className="text-xs font-bold text-white">{t.label}</div>
                            <div className="text-[11px] text-slate-400 mt-0.5">{t.desc}</div>
                          </div>
                        </div>
                        {isSelected && <Check className="w-4 h-4 text-emerald-400 shrink-0" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Reduced Motion Toggle */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Giảm chuyển động (Reduce Motion)</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Tắt hiệu ứng chuyển cảnh nặng cho máy yếu</div>
                </div>
                <button
                  type="button"
                  onClick={() => setMotionReduction(!motionReduction)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    motionReduction ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    motionReduction ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              {/* Haptic Feedback Toggle */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Rung phản hồi xúc giác (Haptic)</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Rung nhẹ khi nhấn nút & đổi trạng thái sạc</div>
                </div>
                <button
                  type="button"
                  onClick={() => setHaptic(!haptic)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    haptic ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    haptic ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
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
                {savedSuccess ? 'Đã lưu' : 'Áp dụng giao diện'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
