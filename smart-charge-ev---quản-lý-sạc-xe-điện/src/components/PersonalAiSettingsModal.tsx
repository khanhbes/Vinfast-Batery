import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Sparkles, ChevronRight, Check, AlertTriangle, Trash2, Power, Shield } from 'lucide-react';
import { Vehicle } from '../types';

interface PersonalAiSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicles: Vehicle[];
}

export const PersonalAiSettingsModal: React.FC<PersonalAiSettingsModalProps> = ({
  isOpen,
  onClose,
  vehicles,
}) => {
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(null);
  const [vehiclesState, setVehiclesState] = useState<Vehicle[]>(vehicles);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [actionSuccessToast, setActionSuccessToast] = useState<string | null>(null);

  const activeVehicles = vehiclesState.filter(v => !v.isArchived);
  const currentVehicle = vehiclesState.find(v => v.id === selectedVehicleId);

  const getStageLabel = (stage?: string) => {
    switch (stage) {
      case 'personalized':
        return 'Đã cá nhân hóa cho xe này';
      case 'learning_habits':
        return 'AI đang học thói quen sạc';
      case 'learning_intro':
      default:
        return 'AI đang làm quen với xe của bạn';
    }
  };

  const handleToggleAiLearning = (vehicleId: string) => {
    setVehiclesState(prev => prev.map(v => {
      if (v.id === vehicleId) {
        const nextState = !v.personalAiEnabled;
        setActionSuccessToast(nextState ? 'Đã bật học tập AI cho xe' : 'Đã tạm dừng AI cá nhân');
        setTimeout(() => setActionSuccessToast(null), 2500);
        return { ...v, personalAiEnabled: nextState };
      }
      return v;
    }));
  };

  const handleResetAiData = () => {
    if (!selectedVehicleId) return;
    setVehiclesState(prev => prev.map(v => {
      if (v.id === selectedVehicleId) {
        return {
          ...v,
          personalAiStage: 'learning_intro',
          sessionsUsedForAi: 0,
          lastAiUpdate: 'Vừa đặt lại',
        };
      }
      return v;
    }));
    setShowDeleteConfirm(false);
    setActionSuccessToast('Đã xóa dữ liệu AI cá nhân. Mô hình sẽ học lại từ các phiên sạc tới.');
    setTimeout(() => setActionSuccessToast(null), 3000);
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
                  <Sparkles className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">AI cá nhân</h3>
                  <p className="text-[11px] text-slate-400">Mô hình máy học dự đoán thời gian sạc riêng từng xe</p>
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

            {/* Toast feedback */}
            {actionSuccessToast && (
              <div className="mt-3 p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl text-xs text-emerald-400 flex items-center justify-center gap-2 animate-fadeIn">
                <Check className="w-4 h-4 stroke-[3]" />
                {actionSuccessToast}
              </div>
            )}

            {/* Vehicle AI List */}
            {!currentVehicle ? (
              <div className="mt-4 space-y-3">
                <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Trạng thái AI từng xe
                </div>

                {activeVehicles.map((veh) => (
                  <button
                    key={veh.id}
                    type="button"
                    onClick={() => setSelectedVehicleId(veh.id)}
                    className="w-full p-4 rounded-2xl bg-[#111] hover:bg-[#151515] border border-white/5 flex items-center justify-between text-left transition-colors group"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-xl bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center justify-center">
                        <Sparkles className="w-5 h-5" />
                      </div>
                      <div>
                        <div className="text-sm font-bold text-white group-hover:text-emerald-400 transition-colors">
                          {veh.name}
                        </div>
                        <div className="text-xs text-slate-400 mt-0.5">
                          {veh.personalAiEnabled
                            ? getStageLabel(veh.personalAiStage)
                            : 'Đã tạm dừng AI'}
                        </div>
                      </div>
                    </div>

                    <ChevronRight className="w-5 h-5 text-slate-500 group-hover:text-white transition-colors" />
                  </button>
                ))}

                <div className="p-3.5 rounded-2xl bg-white/5 border border-white/5 text-xs text-slate-400 leading-relaxed space-y-1">
                  <div className="font-bold text-white flex items-center gap-1.5">
                    <Shield className="w-3.5 h-3.5 text-emerald-400" />
                    Bảo mật dữ liệu học tập
                  </div>
                  <p className="text-[11px]">
                    AI của từng xe được xử lý riêng biệt. Xe A không sử dụng dữ liệu của xe B. Dữ liệu từ tài khoản khác không được dùng cho AI cá nhân của bạn.
                  </p>
                </div>
              </div>
            ) : (
              /* Detail AI Configuration for Selected Vehicle */
              <div className="mt-4 space-y-4">
                <button
                  type="button"
                  onClick={() => setSelectedVehicleId(null)}
                  className="text-xs text-emerald-400 hover:text-emerald-300 font-medium flex items-center gap-1"
                >
                  ← Quay lại danh sách xe
                </button>

                <div className="p-4 rounded-2xl bg-[#111] border border-white/5 space-y-3.5">
                  <div className="flex items-center justify-between pb-3 border-b border-white/5">
                    <div>
                      <div className="text-sm font-bold text-white">{currentVehicle.name}</div>
                      <div className="text-xs text-slate-400 mt-0.5">Cho phép AI học từ các lần sạc</div>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleToggleAiLearning(currentVehicle.id)}
                      className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                        currentVehicle.personalAiEnabled ? 'bg-emerald-500' : 'bg-white/10'
                      }`}
                    >
                      <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                        currentVehicle.personalAiEnabled ? 'translate-x-5' : 'translate-x-0'
                      }`} />
                    </button>
                  </div>

                  {/* Stage status */}
                  <div className="p-3 rounded-xl bg-white/5 border border-white/5 space-y-1">
                    <div className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">
                      Trạng thái mô hình
                    </div>
                    <div className="text-xs font-bold text-emerald-400">
                      {getStageLabel(currentVehicle.personalAiStage)}
                    </div>
                    <p className="text-[11px] text-slate-400 leading-relaxed pt-1">
                      AI sử dụng lịch sử sạc của riêng chiếc xe để dự đoán thời gian sạc chính xác hơn theo đường cong nạp thực tế.
                    </p>
                  </div>

                  {/* Stats */}
                  <div className="flex items-center justify-between text-xs text-slate-400 pt-1 font-mono">
                    <span>{currentVehicle.sessionsUsedForAi || 0} phiên sạc đã được sử dụng</span>
                    <span>Cập nhật: {currentVehicle.lastAiUpdate || 'Hôm nay'}</span>
                  </div>
                </div>

                {/* Separation between Stop AI vs Delete AI */}
                <div className="space-y-2 pt-1">
                  <button
                    type="button"
                    onClick={() => handleToggleAiLearning(currentVehicle.id)}
                    className="w-full py-3 rounded-2xl bg-white/10 hover:bg-white/15 text-white font-bold text-xs border border-white/10 flex items-center justify-center gap-2 transition-colors"
                  >
                    <Power className="w-3.5 h-3.5" />
                    {currentVehicle.personalAiEnabled ? 'Tắt AI cá nhân (Tạm dừng)' : 'Bật lại AI cá nhân'}
                  </button>

                  <button
                    type="button"
                    onClick={() => setShowDeleteConfirm(true)}
                    className="w-full py-3 rounded-2xl bg-red-500/10 hover:bg-red-500/20 text-red-400 font-bold text-xs border border-red-500/20 flex items-center justify-center gap-2 transition-colors"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                    Xóa dữ liệu AI cá nhân
                  </button>
                </div>
              </div>
            )}

            {/* Strong Confirmation Modal for AI Deletion */}
            <AnimatePresence>
              {showDeleteConfirm && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
                  <motion.div
                    initial={{ scale: 0.9, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    exit={{ scale: 0.9, opacity: 0 }}
                    className="w-full max-w-sm bg-[#111] border border-red-500/30 rounded-3xl p-5 shadow-2xl text-left"
                  >
                    <div className="w-12 h-12 rounded-2xl bg-red-500/10 text-red-400 border border-red-500/20 flex items-center justify-center mb-3">
                      <AlertTriangle className="w-6 h-6" />
                    </div>
                    <h4 className="text-base font-bold text-white">Xóa dữ liệu AI cá nhân?</h4>
                    <p className="text-xs text-slate-300 mt-2 leading-relaxed">
                      Dữ liệu học máy cá nhân hóa của chiếc xe này sẽ bị xóa vĩnh viễn. Lịch sử sạc vẫn được giữ nguyên và mô hình AI sẽ phải học lại từ đầu khi được kích hoạt.
                    </p>

                    <div className="mt-5 flex gap-2">
                      <button
                        type="button"
                        onClick={() => setShowDeleteConfirm(false)}
                        className="flex-1 py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
                      >
                        Hủy
                      </button>
                      <button
                        type="button"
                        onClick={handleResetAiData}
                        className="flex-1 py-2.5 rounded-2xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/20"
                      >
                        Tôi hiểu, xóa dữ liệu AI
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
