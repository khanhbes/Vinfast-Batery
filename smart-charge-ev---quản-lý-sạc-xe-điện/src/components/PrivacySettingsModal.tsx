import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Shield, Lock, Trash2, AlertTriangle, Check, Smartphone, Key, FileText } from 'lucide-react';

interface PrivacySettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onClearAllChargingData?: () => void;
}

export const PrivacySettingsModal: React.FC<PrivacySettingsModalProps> = ({
  isOpen,
  onClose,
  onClearAllChargingData,
}) => {
  const [showConfirmDelete, setShowConfirmDelete] = useState(false);
  const [deleteSuccess, setDeleteSuccess] = useState(false);

  const handleDelete = () => {
    onClearAllChargingData?.();
    setShowConfirmDelete(false);
    setDeleteSuccess(true);
    setTimeout(() => {
      setDeleteSuccess(false);
      onClose();
    }, 1500);
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
                  <Shield className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Quyền riêng tư & bảo mật</h3>
                  <p className="text-[11px] text-slate-400">Minh bạch xử lý dữ liệu và quyền cá nhân</p>
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

            {/* AI Isolation Highlight Card */}
            <div className="mt-4 p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 space-y-1.5">
              <div className="flex items-center gap-2 text-emerald-400 text-xs font-bold">
                <Lock className="w-3.5 h-3.5" />
                Nguyên tắc cô lập dữ liệu AI
              </div>
              <p className="text-xs text-slate-300 leading-relaxed">
                AI của từng xe được xử lý riêng biệt. Xe A không sử dụng dữ liệu của xe B. Dữ liệu từ tài khoản khác tuyệt đối không được dùng cho AI cá nhân của bạn.
              </p>
            </div>

            {/* Privacy Sections */}
            <div className="mt-4 space-y-2.5">
              {/* Dữ liệu AI */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Dữ liệu AI cá nhân</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Lưu trữ cục bộ & mã hóa AES-256</div>
                </div>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/5 text-emerald-400 border border-white/10 font-mono">
                  Mã hóa
                </span>
              </div>

              {/* Dữ liệu sạc */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Dữ liệu telemetry sạc</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Điện áp, dòng điện, công suất từng giây</div>
                </div>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/5 text-slate-300 border border-white/10 font-mono">
                  Bảo mật
                </span>
              </div>

              {/* Thiết bị liên kết */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Thiết bị đã ghép đôi</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Shelly Plug S Gen3 (Xác thực cục bộ)</div>
                </div>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/5 text-slate-300 border border-white/10">
                  1 thiết bị
                </span>
              </div>

              {/* Quyền hệ điều hành */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                <div className="text-xs font-bold text-white">Quyền ứng dụng Android</div>
                <div className="grid grid-cols-2 gap-2 text-[11px]">
                  <div className="p-2 rounded-xl bg-white/5 text-slate-300 flex items-center justify-between">
                    <span>Thông báo</span>
                    <span className="text-emerald-400 font-bold">Đã cấp</span>
                  </div>
                  <div className="p-2 rounded-xl bg-white/5 text-slate-300 flex items-center justify-between">
                    <span>Bluetooth/WiFi</span>
                    <span className="text-emerald-400 font-bold">Đã cấp</span>
                  </div>
                </div>
              </div>
            </div>

            {/* Dangerous Action: Clear all data */}
            <div className="mt-5 pt-3 border-t border-white/5">
              <div className="text-[11px] font-bold text-red-400 uppercase tracking-wider mb-2">
                Vùng nguy hiểm
              </div>
              <button
                type="button"
                onClick={() => setShowConfirmDelete(true)}
                className="w-full py-3 rounded-2xl bg-red-500/10 hover:bg-red-500/20 text-red-400 font-bold text-xs border border-red-500/20 flex items-center justify-center gap-2 transition-colors"
              >
                <Trash2 className="w-3.5 h-3.5" />
                Xóa dữ liệu sạc vĩnh viễn
              </button>
            </div>

            {deleteSuccess && (
              <div className="mt-3 p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl text-xs text-emerald-400 text-center">
                Đã xóa dữ liệu sạc thành công!
              </div>
            )}

            {/* Confirmation Dialog */}
            <AnimatePresence>
              {showConfirmDelete && (
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
                    <h4 className="text-base font-bold text-white">Xóa vĩnh viễn dữ liệu sạc?</h4>
                    <p className="text-xs text-slate-300 mt-2 leading-relaxed">
                      Toàn bộ các phiên sạc, số kWh và biểu đồ sẽ bị xóa hoàn toàn. AI cá nhân của các xe sẽ phải học lại từ đầu. Hành động này không thể hoàn tác.
                    </p>

                    <div className="mt-5 flex gap-2">
                      <button
                        type="button"
                        onClick={() => setShowConfirmDelete(false)}
                        className="flex-1 py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
                      >
                        Hủy
                      </button>
                      <button
                        type="button"
                        onClick={handleDelete}
                        className="flex-1 py-2.5 rounded-2xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/20"
                      >
                        Tôi hiểu, xóa dữ liệu
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
