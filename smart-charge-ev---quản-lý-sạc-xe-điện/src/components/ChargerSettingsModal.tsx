import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Zap, Check, Wifi, AlertCircle, RefreshCw, Unlink, ChevronRight, ShieldCheck } from 'lucide-react';
import { Vehicle } from '../types';

interface ChargerSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicles: Vehicle[];
}

export const ChargerSettingsModal: React.FC<ChargerSettingsModalProps> = ({
  isOpen,
  onClose,
  vehicles,
}) => {
  const [selectedVehicle, setSelectedVehicle] = useState<Vehicle | null>(null);
  const [isTesting, setIsTesting] = useState(false);
  const [testResult, setTestResult] = useState<string | null>(null);
  const [localVehicles, setLocalVehicles] = useState<Vehicle[]>(vehicles);

  const activeVehicles = localVehicles.filter(v => !v.isArchived);

  const handleTestConnection = () => {
    setIsTesting(true);
    setTestResult(null);
    setTimeout(() => {
      setIsTesting(false);
      setTestResult('Phản hồi tốt (38ms) • Tín hiệu WiFi ổn định -54dBm');
    }, 900);
  };

  const handleDisconnect = (vehicleId: string) => {
    setLocalVehicles(prev => prev.map(v => {
      if (v.id === vehicleId) {
        return {
          ...v,
          chargerBinding: {
            chargerName: 'Chưa kết nối bộ sạc',
            isConnected: false,
          }
        };
      }
      return v;
    }));
    if (selectedVehicle?.id === vehicleId) {
      setSelectedVehicle(prev => prev ? {
        ...prev,
        chargerBinding: {
          chargerName: 'Chưa kết nối bộ sạc',
          isConnected: false,
        }
      } : null);
    }
  };

  const handleConnectNew = (vehicleId: string) => {
    setLocalVehicles(prev => prev.map(v => {
      if (v.id === vehicleId) {
        return {
          ...v,
          chargerBinding: {
            chargerName: 'Shelly sạc xe',
            isConnected: true,
            deviceModel: 'Shelly Plug S Gen3',
          }
        };
      }
      return v;
    }));
    if (selectedVehicle?.id === vehicleId) {
      setSelectedVehicle(prev => prev ? {
        ...prev,
        chargerBinding: {
          chargerName: 'Shelly sạc xe',
          isConnected: true,
          deviceModel: 'Shelly Plug S Gen3',
        }
      } : null);
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
                  <Zap className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Bộ sạc & kết nối</h3>
                  <p className="text-[11px] text-slate-400">Thiết bị sạc liên kết theo từng phương tiện</p>
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

            {/* List by Vehicle */}
            {!selectedVehicle ? (
              <div className="mt-4 space-y-3">
                <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Bộ sạc của từng xe
                </div>

                {activeVehicles.map((veh) => {
                  const binding = veh.chargerBinding;
                  const isConnected = binding?.isConnected;
                  return (
                    <button
                      key={veh.id}
                      type="button"
                      onClick={() => {
                        setSelectedVehicle(veh);
                        setTestResult(null);
                      }}
                      className="w-full p-4 rounded-2xl bg-[#111] hover:bg-[#151515] border border-white/5 flex items-center justify-between text-left transition-colors group"
                    >
                      <div className="flex items-center gap-3">
                        <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                          isConnected ? 'bg-emerald-500/20 text-emerald-400' : 'bg-white/5 text-slate-500'
                        }`}>
                          <Zap className="w-5 h-5" />
                        </div>
                        <div>
                          <div className="text-sm font-bold text-white group-hover:text-emerald-400 transition-colors">
                            {veh.name}
                          </div>
                          <div className="text-xs text-slate-400 mt-0.5 flex items-center gap-1.5">
                            <span>{binding?.chargerName || 'Chưa kết nối bộ sạc'}</span>
                            {isConnected ? (
                              <span className="text-emerald-400 font-medium flex items-center gap-1">
                                • <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 inline-block" /> Đã kết nối
                              </span>
                            ) : (
                              <span className="text-slate-500">• Chưa kết nối</span>
                            )}
                          </div>
                        </div>
                      </div>

                      <ChevronRight className="w-5 h-5 text-slate-500 group-hover:text-white transition-colors" />
                    </button>
                  );
                })}

                <div className="mt-4 p-3.5 rounded-2xl bg-emerald-500/5 border border-emerald-500/20 text-xs text-slate-300 flex items-start gap-2.5">
                  <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                  <p className="text-[11px] text-slate-400 leading-relaxed">
                    Khi bắt đầu sạc, thời gian an toàn được lưu trực tiếp vào bộ sạc. Vì vậy việc sạc vẫn được bảo vệ ngay cả khi điện thoại mất kết nối.
                  </p>
                </div>
              </div>
            ) : (
              /* Vehicle Charger Detail View */
              <div className="mt-4 space-y-4">
                <div className="flex items-center justify-between">
                  <button
                    type="button"
                    onClick={() => setSelectedVehicle(null)}
                    className="text-xs text-emerald-400 hover:text-emerald-300 font-medium flex items-center gap-1"
                  >
                    ← Quay lại danh sách xe
                  </button>
                  <span className="text-xs font-bold text-white">{selectedVehicle.name}</span>
                </div>

                <div className="p-4 rounded-2xl bg-[#111] border border-white/5 space-y-3">
                  <div className="flex items-center justify-between pb-3 border-b border-white/5">
                    <span className="text-xs text-slate-400">Trạng thái kết nối</span>
                    {selectedVehicle.chargerBinding?.isConnected ? (
                      <span className="px-2.5 py-1 rounded-full bg-emerald-500/15 text-emerald-400 text-xs font-bold border border-emerald-500/30 flex items-center gap-1.5">
                        <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                        Đã kết nối
                      </span>
                    ) : (
                      <span className="px-2.5 py-1 rounded-full bg-white/5 text-slate-400 text-xs font-medium border border-white/10">
                        Chưa kết nối
                      </span>
                    )}
                  </div>

                  <div className="flex items-center justify-between pb-3 border-b border-white/5">
                    <span className="text-xs text-slate-400">Thiết bị sạc</span>
                    <span className="text-xs font-bold text-white">
                      {selectedVehicle.chargerBinding?.deviceModel || 'Chưa thiết lập'}
                    </span>
                  </div>

                  {selectedVehicle.chargerBinding?.isConnected && (
                    <div>
                      <button
                        type="button"
                        onClick={handleTestConnection}
                        disabled={isTesting}
                        className="w-full py-2.5 rounded-xl bg-white/5 hover:bg-white/10 text-slate-200 text-xs font-bold border border-white/10 flex items-center justify-center gap-2 transition-colors"
                      >
                        <RefreshCw className={`w-3.5 h-3.5 ${isTesting ? 'animate-spin text-emerald-400' : ''}`} />
                        {isTesting ? 'Đang kiểm tra kết nối...' : 'Kiểm tra kết nối'}
                      </button>

                      {testResult && (
                        <div className="mt-2 p-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-[11px] text-emerald-400 font-mono text-center">
                          {testResult}
                        </div>
                      )}
                    </div>
                  )}
                </div>

                {/* Actions */}
                <div className="space-y-2">
                  {selectedVehicle.chargerBinding?.isConnected ? (
                    <>
                      <button
                        type="button"
                        onClick={() => handleConnectNew(selectedVehicle.id)}
                        className="w-full py-3 rounded-2xl bg-white/10 hover:bg-white/15 text-white font-bold text-xs border border-white/10 transition-colors"
                      >
                        Đổi bộ sạc khác
                      </button>
                      <button
                        type="button"
                        onClick={() => handleDisconnect(selectedVehicle.id)}
                        className="w-full py-3 rounded-2xl bg-red-500/10 hover:bg-red-500/20 text-red-400 font-bold text-xs border border-red-500/20 flex items-center justify-center gap-2 transition-colors"
                      >
                        <Unlink className="w-3.5 h-3.5" />
                        Ngắt kết nối bộ sạc
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => handleConnectNew(selectedVehicle.id)}
                      className="w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-2 transition-colors"
                    >
                      <Zap className="w-4 h-4 fill-current" />
                      Kết nối bộ sạc mới
                    </button>
                  )}
                </div>
              </div>
            )}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
