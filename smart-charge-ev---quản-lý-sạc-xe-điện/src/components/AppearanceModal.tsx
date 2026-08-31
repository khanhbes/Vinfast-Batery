import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Moon, Globe, Check } from 'lucide-react';
import { AppSettings } from '../types';

interface AppearanceModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const AppearanceModal: React.FC<AppearanceModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
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
            className="relative w-full max-w-sm bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Moon className="w-4 h-4" />
                </div>
                <h3 className="text-base font-bold text-white">Giao diện & Ngôn ngữ</h3>
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
              {/* Theme Selection */}
              <div>
                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider block mb-2">
                  Chủ đề giao diện
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => onUpdateSettings({ theme: 'dark' })}
                    className={`p-3.5 rounded-2xl border text-left flex items-center justify-between transition-all ${
                      settings.theme === 'dark'
                        ? 'bg-emerald-500/10 border-emerald-500 text-emerald-300'
                        : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                    }`}
                  >
                    <div>
                      <div className="text-xs font-bold text-white">Obsidian Dark</div>
                      <div className="text-[10px] text-slate-400 mt-0.5">Tối sâu cao cấp</div>
                    </div>
                    {settings.theme === 'dark' && <Check className="w-4 h-4 text-emerald-400" />}
                  </button>

                  <button
                    type="button"
                    onClick={() => onUpdateSettings({ theme: 'amoled' })}
                    className={`p-3.5 rounded-2xl border text-left flex items-center justify-between transition-all ${
                      settings.theme === 'amoled'
                        ? 'bg-emerald-500/10 border-emerald-500 text-emerald-300'
                        : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                    }`}
                  >
                    <div>
                      <div className="text-xs font-bold text-white">Pure AMOLED</div>
                      <div className="text-[10px] text-slate-400 mt-0.5">Đen tuyền tiết kiệm pin</div>
                    </div>
                    {settings.theme === 'amoled' && <Check className="w-4 h-4 text-emerald-400" />}
                  </button>
                </div>
              </div>

              {/* Language Selection */}
              <div>
                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider block mb-2 flex items-center gap-1.5">
                  <Globe className="w-3.5 h-3.5" />
                  Ngôn ngữ hiển thị
                </label>
                <div className="space-y-2">
                  <button
                    type="button"
                    onClick={() => onUpdateSettings({ language: 'vi' })}
                    className={`w-full p-3.5 rounded-2xl border text-left flex items-center justify-between transition-all ${
                      settings.language === 'vi'
                        ? 'bg-emerald-500/10 border-emerald-500 text-emerald-300'
                        : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                    }`}
                  >
                    <div className="flex items-center gap-2.5">
                      <span className="text-base">🇻🇳</span>
                      <div>
                        <div className="text-xs font-bold text-white">Tiếng Việt</div>
                        <div className="text-[10px] text-slate-400">Giao diện chuẩn Việt Nam</div>
                      </div>
                    </div>
                    {settings.language === 'vi' && <Check className="w-4 h-4 text-emerald-400" />}
                  </button>

                  <button
                    type="button"
                    onClick={() => onUpdateSettings({ language: 'en' })}
                    className={`w-full p-3.5 rounded-2xl border text-left flex items-center justify-between transition-all ${
                      settings.language === 'en'
                        ? 'bg-emerald-500/10 border-emerald-500 text-emerald-300'
                        : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                    }`}
                  >
                    <div className="flex items-center gap-2.5">
                      <span className="text-base">🇬🇧</span>
                      <div>
                        <div className="text-xs font-bold text-white">English</div>
                        <div className="text-[10px] text-slate-400">International format</div>
                      </div>
                    </div>
                    {settings.language === 'en' && <Check className="w-4 h-4 text-emerald-400" />}
                  </button>
                </div>
              </div>
            </div>

            <div className="mt-5">
              <button
                type="button"
                onClick={onClose}
                className="w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20"
              >
                Hoàn tất
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
