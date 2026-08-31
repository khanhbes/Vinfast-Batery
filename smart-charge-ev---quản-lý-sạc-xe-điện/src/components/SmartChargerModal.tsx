import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Zap, Wifi, Server, Shield, Check, Cpu } from 'lucide-react';
import { AppSettings } from '../types';

interface SmartChargerModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const SmartChargerModal: React.FC<SmartChargerModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
  const [mode, setMode] = useState<'cloud' | 'lan' | 'direct'>(settings.smartChargerMode || 'cloud');
  const [ipAddress, setIpAddress] = useState('192.168.1.188');
  const [isSaved, setIsSaved] = useState(false);

  const handleSave = () => {
    onUpdateSettings({ smartChargerMode: mode });
    setIsSaved(true);
    setTimeout(() => {
      setIsSaved(false);
      onClose();
    }, 800);
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
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[85vh] overflow-y-auto"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Smart Charger Hardware</h3>
                  <p className="text-[11px] text-slate-400">Giao thức kết nối thiết bị đóng cắt & đo đạc</p>
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

            <div className="mt-4 space-y-3">
              {/* Protocols */}
              {[
                {
                  id: 'cloud',
                  icon: Server,
                  title: 'Cloud Direct (MQTT / Tuya Cloud)',
                  desc: 'Điều khiển từ xa mọi lúc mọi nơi qua Internet tốc độ cao',
                },
                {
                  id: 'lan',
                  icon: Wifi,
                  title: 'Local LAN Direct (ESP32 / Tasmota)',
                  desc: 'Phản hồi cực nhanh <50ms không phụ thuộc Internet nhà',
                },
                {
                  id: 'direct',
                  icon: Cpu,
                  title: 'Bluetooth Low Energy (BMS Direct)',
                  desc: 'Đọc điện áp trực tiếp từ mạch bảo vệ xe VinFast LFP',
                },
              ].map((item) => {
                const IconComp = item.icon;
                const isSelected = mode === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setMode(item.id as any)}
                    className={`w-full p-3.5 rounded-2xl border text-left flex items-start gap-3 transition-all ${
                      isSelected
                        ? 'bg-emerald-500/10 border-emerald-500 shadow-md shadow-emerald-500/10'
                        : 'bg-white/5 border-white/5 hover:border-white/20'
                    }`}
                  >
                    <div className={`w-8 h-8 rounded-xl flex items-center justify-center shrink-0 ${
                      isSelected ? 'bg-emerald-500 text-slate-950' : 'bg-white/5 text-slate-400'
                    }`}>
                      <IconComp className="w-4 h-4" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-bold text-white">{item.title}</span>
                        {isSelected && <Check className="w-4 h-4 text-emerald-400" />}
                      </div>
                      <p className="text-[11px] text-slate-400 mt-0.5 leading-relaxed">{item.desc}</p>
                    </div>
                  </button>
                );
              })}

              {mode === 'lan' && (
                <div className="p-3 rounded-2xl bg-white/5 border border-white/5 space-y-2">
                  <label className="text-[11px] text-slate-400 block">Địa chỉ IP Local thiết bị đóng cắt:</label>
                  <input
                    type="text"
                    value={ipAddress}
                    onChange={(e) => setIpAddress(e.target.value)}
                    className="w-full bg-[#050505] border border-white/10 rounded-xl px-3 py-2 text-xs font-mono text-emerald-400 focus:outline-none focus:border-emerald-500"
                  />
                </div>
              )}

              {/* Safety Shield */}
              <div className="p-3 rounded-2xl bg-emerald-500/5 border border-emerald-500/20 text-xs text-slate-300 flex items-start gap-2.5">
                <Shield className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                <p className="text-[11px] text-slate-400 leading-relaxed">
                  Tự động ngắt dòng rò, chống quá áp &gt;250V và chống ngắn mạch khi nhiệt độ pin vượt ngưỡng 45°C.
                </p>
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
                onClick={handleSave}
                className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-1.5"
              >
                {isSaved ? <Check className="w-4 h-4 stroke-[3]" /> : null}
                {isSaved ? 'Đã lưu cấu hình' : 'Lưu cài đặt'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
