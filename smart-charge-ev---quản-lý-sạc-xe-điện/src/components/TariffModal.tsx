import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, DollarSign, Check, Save } from 'lucide-react';
import { AppSettings, Vehicle } from '../types';

interface TariffModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  vehicle: Vehicle;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const TariffModal: React.FC<TariffModalProps> = ({
  isOpen,
  onClose,
  settings,
  vehicle,
  onUpdateSettings,
}) => {
  const [tariff, setTariff] = useState(settings.electricityTariffVNDPerKWh);
  const [savedSuccess, setSavedSuccess] = useState(false);

  const handleSaveTariff = () => {
    onUpdateSettings({ electricityTariffVNDPerKWh: tariff });
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
      onClose();
    }, 600);
  };

  const presets = [
    { label: 'Điện sinh hoạt Bậc 3', rate: 2360, desc: 'Từ 101 - 200 kWh' },
    { label: 'Bình quân hộ gia đình', rate: 2800, desc: 'Mức phổ biến nhất' },
    { label: 'Điện sinh hoạt Bậc 5', rate: 3220, desc: 'Từ 301 - 400 kWh' },
    { label: 'Trạm sạc công cộng', rate: 3858, desc: 'VinFast / Trạm ngoài' },
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
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[85vh] overflow-y-auto"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <DollarSign className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Biểu giá điện áp dụng</h3>
                  <p className="text-[11px] text-slate-400">Tính toán chi phí sạc xe {vehicle.name}</p>
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
              <div>
                <label className="text-xs text-slate-400 block mb-1">Đơn giá điện (VNĐ / kWh):</label>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    value={tariff}
                    onChange={(e) => setTariff(Number(e.target.value))}
                    step="50"
                    className="flex-1 bg-[#050505] border border-white/10 rounded-2xl px-4 py-2.5 text-sm font-bold font-mono-num text-white focus:outline-none focus:border-emerald-500 transition-colors"
                  />
                  <span className="text-xs text-slate-400 font-medium whitespace-nowrap">đ / kWh</span>
                </div>
              </div>

              {/* Presets Grid */}
              <div className="space-y-2">
                <span className="text-xs font-bold text-slate-400 uppercase tracking-wider block">
                  Mức giá EVN tham khảo
                </span>
                <div className="grid grid-cols-2 gap-2">
                  {presets.map((p, idx) => (
                    <button
                      key={idx}
                      type="button"
                      onClick={() => setTariff(p.rate)}
                      className={`p-3 rounded-2xl border text-left text-xs transition-colors ${
                        tariff === p.rate
                          ? 'bg-emerald-500/20 border-emerald-500 text-emerald-300 shadow-sm'
                          : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20'
                      }`}
                    >
                      <div className="font-bold text-white text-xs">{p.rate.toLocaleString('vi-VN')} đ</div>
                      <div className="text-[11px] text-slate-300 font-medium mt-0.5">{p.label}</div>
                      <div className="text-[10px] text-slate-500">{p.desc}</div>
                    </button>
                  ))}
                </div>
              </div>

              {/* Cost Estimation Preview */}
              <div className="p-3.5 rounded-2xl bg-white/5 border border-white/5 text-xs space-y-1">
                <div className="flex justify-between text-slate-300">
                  <span>Ước tính sạc đầy 0% → 100% ({vehicle.batteryCapacityKWh} kWh):</span>
                  <span className="font-bold text-emerald-400 font-mono-num">
                    {Math.round(((vehicle.batteryCapacityKWh / 0.9) * tariff)).toLocaleString('vi-VN')} đ
                  </span>
                </div>
                <div className="text-[10px] text-slate-500">
                  (Bao gồm hệ số tiêu hao chuyển đổi nhiệt ~90% hiệu suất)
                </div>
              </div>
            </div>

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
                onClick={handleSaveTariff}
                className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-1.5"
              >
                {savedSuccess ? <Check className="w-4 h-4 stroke-[3]" /> : <Save className="w-4 h-4" />}
                {savedSuccess ? 'Đã lưu' : 'Áp dụng đơn giá'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
