import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Check, BatteryCharging, Zap, Gauge, Plus } from 'lucide-react';
import { Vehicle } from '../types';

interface VehicleSelectorModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicles: Vehicle[];
  activeVehicleId: string;
  onSelectVehicle: (id: string) => void;
}

export const VehicleSelectorModal: React.FC<VehicleSelectorModalProps> = ({
  isOpen,
  onClose,
  vehicles,
  activeVehicleId,
  onSelectVehicle,
}) => {
  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/80 backdrop-blur-md"
          />

          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            className="relative w-full max-w-md bg-[#0c0c0c] border-t sm:border border-white/10 rounded-t-[36px] sm:rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[85vh] overflow-y-auto"
          >
            <div className="w-12 h-1 bg-white/20 rounded-full mx-auto mb-3 sm:hidden" />

            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div>
                <h3 className="text-base font-bold text-white">Chọn xe đang kết nối</h3>
                <p className="text-xs text-slate-400">Danh sách xe điện đã ghép nối trong garage</p>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="mt-4 space-y-2.5">
              {vehicles.map((v) => {
                const isSelected = v.id === activeVehicleId;
                return (
                  <button
                    key={v.id}
                    type="button"
                    onClick={() => {
                      onSelectVehicle(v.id);
                      onClose();
                    }}
                    className={`w-full p-4 rounded-3xl text-left border transition-all ${
                      isSelected
                        ? 'bg-emerald-500/10 border-emerald-500 shadow-lg shadow-emerald-500/10'
                        : 'bg-[#111] border-white/5 hover:border-white/20'
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className={`w-10 h-10 rounded-2xl flex items-center justify-center font-bold ${
                          isSelected ? 'bg-emerald-500 text-slate-950 shadow-md shadow-emerald-500/20' : 'bg-white/5 text-emerald-400 border border-white/5'
                        }`}>
                          <Zap className="w-5 h-5 fill-current" />
                        </div>
                        <div>
                          <div className="font-bold text-sm text-white flex items-center gap-2">
                            {v.name}
                            {isSelected && (
                              <span className="text-[10px] bg-emerald-500/20 text-emerald-400 px-2 py-0.5 rounded-full font-mono font-bold">
                                Đang chọn
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-slate-400">
                            Biển số: {v.plateNumber} • {v.model}
                          </div>
                        </div>
                      </div>

                      {isSelected && (
                        <div className="w-6 h-6 rounded-full bg-emerald-500 text-slate-950 flex items-center justify-center">
                          <Check className="w-3.5 h-3.5 stroke-[3]" />
                        </div>
                      )}
                    </div>

                    <div className="mt-3 pt-3 border-t border-white/5 grid grid-cols-3 gap-2 text-center text-xs">
                      <div>
                        <span className="text-[10px] text-slate-400 block">Dung lượng</span>
                        <span className="font-bold text-slate-200 font-mono-num">{v.batteryCapacityKWh} kWh</span>
                      </div>
                      <div>
                        <span className="text-[10px] text-slate-400 block">Quãng đường</span>
                        <span className="font-bold text-emerald-400 font-mono-num">{v.maxRangeKm} km</span>
                      </div>
                      <div>
                        <span className="text-[10px] text-slate-400 block">Loại pin</span>
                        <span className="font-bold text-emerald-400">{v.batteryType}</span>
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};

