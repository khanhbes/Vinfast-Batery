import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Car, Bike, Plus, Archive, RotateCcw, AlertTriangle, Check, ShieldCheck, Battery } from 'lucide-react';
import { Vehicle } from '../types';

interface VehicleSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicles: Vehicle[];
  activeVehicleId: string;
  onSelectVehicle: (id: string) => void;
  onArchiveVehicle: (id: string) => void;
  onRestoreVehicle: (id: string) => void;
  onOpenGarage: () => void;
}

export const VehicleSettingsModal: React.FC<VehicleSettingsModalProps> = ({
  isOpen,
  onClose,
  vehicles,
  activeVehicleId,
  onSelectVehicle,
  onArchiveVehicle,
  onRestoreVehicle,
  onOpenGarage,
}) => {
  const [vehicleToArchive, setVehicleToArchive] = useState<Vehicle | null>(null);
  const [showArchivedList, setShowArchivedList] = useState(false);

  const activeVehicles = vehicles.filter(v => !v.isArchived);
  const archivedVehicles = vehicles.filter(v => v.isArchived);
  const maxVehiclesPerAccount = 2;
  const isLimitReached = activeVehicles.length >= maxVehiclesPerAccount;

  const currentVehicle = vehicles.find(v => v.id === activeVehicleId) || activeVehicles[0];

  const handleConfirmArchive = () => {
    if (vehicleToArchive) {
      onArchiveVehicle(vehicleToArchive.id);
      setVehicleToArchive(null);
    }
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
                  <Car className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Xe của tôi</h3>
                  <p className="text-[11px] text-slate-400">Quản lý phương tiện & giới hạn tài khoản</p>
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

            {/* Section 1: Active Vehicle Summary */}
            <div className="mt-4 p-4 rounded-2xl bg-[#111] border border-white/5">
              <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-2">
                Xe đang dùng
              </div>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                    <Bike className="w-5 h-5" />
                  </div>
                  <div>
                    <h4 className="text-sm font-bold text-white">{currentVehicle.name}</h4>
                    <p className="text-xs text-emerald-400 font-mono mt-0.5">
                      Pin 68% • Sức khỏe pin 99.2%
                    </p>
                  </div>
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                  Đang chọn
                </span>
              </div>
            </div>

            {/* Section 2: Active Vehicles List (Max 2 policy) */}
            <div className="mt-4 space-y-2">
              <div className="flex items-center justify-between px-1">
                <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">
                  Danh sách xe đang hoạt động ({activeVehicles.length}/{maxVehiclesPerAccount})
                </span>
                {isLimitReached && (
                  <span className="text-[10px] font-medium text-amber-400 bg-amber-500/10 px-2 py-0.5 rounded-full border border-amber-500/20">
                    Đã đạt giới hạn 2 xe
                  </span>
                )}
              </div>

              {activeVehicles.map((veh) => {
                const isSelected = veh.id === activeVehicleId;
                return (
                  <div
                    key={veh.id}
                    className={`p-3.5 rounded-2xl border transition-all flex items-center justify-between ${
                      isSelected
                        ? 'bg-white/[0.04] border-emerald-500/40 shadow-sm'
                        : 'bg-[#111] border-white/5'
                    }`}
                  >
                    <button
                      type="button"
                      onClick={() => onSelectVehicle(veh.id)}
                      className="flex items-center gap-3 flex-1 text-left"
                    >
                      <div className={`w-9 h-9 rounded-xl flex items-center justify-center ${
                        isSelected ? 'bg-emerald-500 text-slate-950' : 'bg-white/5 text-slate-300'
                      }`}>
                        <Bike className="w-4 h-4" />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-bold text-white">{veh.name}</span>
                          {isSelected && <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />}
                        </div>
                        <span className="text-[11px] text-slate-400 font-mono">
                          {veh.batteryCapacityKWh} kWh LFP • {veh.plateNumber}
                        </span>
                      </div>
                    </button>

                    <button
                      type="button"
                      onClick={() => setVehicleToArchive(veh)}
                      title="Lưu trữ xe"
                      className="p-2 rounded-xl text-slate-400 hover:text-amber-400 hover:bg-amber-500/10 transition-colors"
                    >
                      <Archive className="w-4 h-4" />
                    </button>
                  </div>
                );
              })}

              {/* Add Vehicle Button (Disabled if 2 active vehicles) */}
              <button
                type="button"
                disabled={isLimitReached}
                onClick={onOpenGarage}
                className={`w-full p-3 rounded-2xl border border-dashed flex items-center justify-center gap-2 text-xs font-bold transition-colors ${
                  isLimitReached
                    ? 'border-white/10 text-slate-600 bg-white/[0.01] cursor-not-allowed opacity-60'
                    : 'border-white/20 text-slate-300 hover:text-white hover:border-emerald-500/40 bg-white/5'
                }`}
              >
                <Plus className="w-4 h-4" />
                <span>{isLimitReached ? 'Đã đạt giới hạn 2 xe (Tài khoản tiêu chuẩn)' : '+ Thêm xe mới'}</span>
              </button>
            </div>

            {/* Section 3: Archived Vehicles section */}
            <div className="mt-4 pt-3 border-t border-white/5">
              <button
                type="button"
                onClick={() => setShowArchivedList(!showArchivedList)}
                className="w-full flex items-center justify-between text-xs text-slate-400 hover:text-white py-1 transition-colors"
              >
                <span className="font-semibold flex items-center gap-1.5">
                  <Archive className="w-3.5 h-3.5" />
                  Xe đã lưu trữ ({archivedVehicles.length})
                </span>
                <span className="text-[11px] text-emerald-400 font-medium">
                  {showArchivedList ? 'Thu gọn' : 'Xem danh sách'}
                </span>
              </button>

              {showArchivedList && (
                <div className="mt-2 space-y-2">
                  {archivedVehicles.length === 0 ? (
                    <div className="p-3 rounded-2xl bg-white/[0.02] text-center text-xs text-slate-500">
                      Không có xe nào trong danh sách lưu trữ
                    </div>
                  ) : (
                    archivedVehicles.map((archVeh) => (
                      <div
                        key={archVeh.id}
                        className="p-3 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between text-xs"
                      >
                        <div>
                          <div className="font-bold text-slate-300">{archVeh.name}</div>
                          <div className="text-[10px] text-slate-500 font-mono">{archVeh.plateNumber} • Đã lưu trữ</div>
                        </div>
                        <button
                          type="button"
                          disabled={isLimitReached}
                          onClick={() => onRestoreVehicle(archVeh.id)}
                          className={`px-3 py-1.5 rounded-xl font-bold text-xs flex items-center gap-1 transition-colors ${
                            isLimitReached
                              ? 'bg-white/5 text-slate-600 cursor-not-allowed'
                              : 'bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500 hover:text-slate-950 border border-emerald-500/30'
                          }`}
                        >
                          <RotateCcw className="w-3.5 h-3.5" />
                          Khôi phục
                        </button>
                      </div>
                    ))
                  )}
                </div>
              )}
            </div>

            {/* Section 4: Open Garage Shortcut */}
            <div className="mt-5">
              <button
                type="button"
                onClick={() => {
                  onClose();
                  onOpenGarage();
                }}
                className="w-full py-3 rounded-2xl bg-white/10 hover:bg-white/15 text-white font-bold text-xs border border-white/10 transition-colors"
              >
                Mở Garage chi tiết
              </button>
            </div>

            {/* Archive Confirmation Dialog */}
            <AnimatePresence>
              {vehicleToArchive && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
                  <motion.div
                    initial={{ scale: 0.9, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    exit={{ scale: 0.9, opacity: 0 }}
                    className="w-full max-w-sm bg-[#111] border border-white/10 rounded-3xl p-5 shadow-2xl text-left"
                  >
                    <div className="w-12 h-12 rounded-2xl bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center justify-center mb-3">
                      <Archive className="w-6 h-6" />
                    </div>
                    <h4 className="text-base font-bold text-white">Lưu trữ xe này?</h4>
                    <p className="text-xs text-slate-300 mt-1.5 leading-relaxed">
                      Xe <strong className="text-white">{vehicleToArchive.name}</strong> sẽ được ẩn khỏi danh sách sử dụng. Lịch sử sạc và dữ liệu AI vẫn được giữ nguyên vẹn.
                    </p>

                    <div className="mt-5 flex gap-2">
                      <button
                        type="button"
                        onClick={() => setVehicleToArchive(null)}
                        className="flex-1 py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
                      >
                        Hủy
                      </button>
                      <button
                        type="button"
                        onClick={handleConfirmArchive}
                        className="flex-1 py-2.5 rounded-2xl bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs shadow-lg shadow-amber-500/20"
                      >
                        Lưu trữ
                      </button>
                    </div>
                  </motion.div>
                </div>
              )}
            </AnimatePresence>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
