import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Globe, Check, Gauge, Zap } from 'lucide-react';
import { AppSettings } from '../types';

interface LanguageUnitSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const LanguageUnitSettingsModal: React.FC<LanguageUnitSettingsModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
  const [lang, setLang] = useState(settings.language || 'vi');
  const [energyUnit, setEnergyUnit] = useState(settings.energyUnit || 'auto');
  const [savedSuccess, setSavedSuccess] = useState(false);

  const handleSave = () => {
    onUpdateSettings({
      language: lang as any,
      energyUnit: energyUnit as any,
    });
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
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
            initial={{ scale: 0.95, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.95, opacity: 0 }}
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[88vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Globe className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Ngôn ngữ & đơn vị</h3>
                  <p className="text-[11px] text-slate-400">Định dạng hiển thị số liệu đo lường</p>
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
              {/* Ngôn ngữ */}
              <div className="space-y-2">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Ngôn ngữ hiển thị
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setLang('vi')}
                    className={`p-3.5 rounded-2xl border text-left flex items-center justify-between transition-colors ${
                      lang === 'vi'
                        ? 'bg-emerald-500/10 border-emerald-500 text-white shadow-sm'
                        : 'bg-[#111] border-white/5 text-slate-400 hover:text-white'
                    }`}
                  >
                    <div>
                      <div className="text-xs font-bold">Tiếng Việt</div>
                      <div className="text-[10px] text-slate-500">Mặc định</div>
                    </div>
                    {lang === 'vi' && <Check className="w-4 h-4 text-emerald-400 shrink-0" />}
                  </button>

                  <button
                    type="button"
                    onClick={() => setLang('en')}
                    className={`p-3.5 rounded-2xl border text-left flex items-center justify-between transition-colors ${
                      lang === 'en'
                        ? 'bg-emerald-500/10 border-emerald-500 text-white shadow-sm'
                        : 'bg-[#111] border-white/5 text-slate-400 hover:text-white'
                    }`}
                  >
                    <div>
                      <div className="text-xs font-bold">English</div>
                      <div className="text-[10px] text-slate-500">International</div>
                    </div>
                    {lang === 'en' && <Check className="w-4 h-4 text-emerald-400 shrink-0" />}
                  </button>
                </div>
              </div>

              {/* Đơn vị năng lượng */}
              <div className="space-y-2">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Đơn vị điện năng
                </label>
                <div className="space-y-2">
                  {[
                    { id: 'auto', title: 'Tự động thích ứng (Wh / kWh)', desc: '< 1.000 Wh hiển thị Wh, ≥ 1.000 Wh hiển thị kWh' },
                    { id: 'kwh', title: 'Luôn hiển thị kWh', desc: 'Ví dụ: 0.89 kWh (Phù hợp xe điện lớn)' },
                    { id: 'wh', title: 'Luôn hiển thị Wh', desc: 'Ví dụ: 890 Wh (Độ chính xác cao)' },
                  ].map(unit => {
                    const isSelected = energyUnit === unit.id;
                    return (
                      <button
                        key={unit.id}
                        type="button"
                        onClick={() => setEnergyUnit(unit.id as any)}
                        className={`w-full p-3.5 rounded-2xl border text-left flex items-center justify-between transition-colors ${
                          isSelected
                            ? 'bg-emerald-500/10 border-emerald-500 shadow-sm'
                            : 'bg-[#111] border-white/5 hover:border-white/20'
                        }`}
                      >
                        <div>
                          <div className="text-xs font-bold text-white">{unit.title}</div>
                          <div className="text-[11px] text-slate-400 mt-0.5">{unit.desc}</div>
                        </div>
                        {isSelected && <Check className="w-4 h-4 text-emerald-400 shrink-0" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Fixed units */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <span className="text-xs text-slate-400">Đơn vị quãng đường</span>
                <span className="text-xs font-bold text-white font-mono">Kilômét (km)</span>
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
                {savedSuccess ? 'Đã lưu' : 'Lưu cài đặt'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
