import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { LogOut, X } from 'lucide-react';

interface LogoutModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirmLogout: () => void;
}

export const LogoutModal: React.FC<LogoutModalProps> = ({
  isOpen,
  onClose,
  onConfirmLogout,
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
            className="relative w-full max-w-sm bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 text-center"
          >
            <div className="w-14 h-14 rounded-3xl bg-red-500/10 text-red-400 border border-red-500/20 flex items-center justify-center mx-auto mb-3">
              <LogOut className="w-6 h-6" />
            </div>

            <h3 className="text-base font-bold text-white">Đăng xuất tài khoản?</h3>
            <p className="text-xs text-slate-400 mt-1.5 leading-relaxed">
              Phiên sạc hiện tại vẫn tiếp tục chạy độc lập trên bộ sạc ngay cả khi bạn đăng xuất khỏi ứng dụng điện thoại.
            </p>

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
                onClick={() => {
                  onConfirmLogout();
                  onClose();
                }}
                className="flex-1 py-3 rounded-2xl bg-red-600 hover:bg-red-500 text-white font-bold text-xs shadow-lg shadow-red-600/20"
              >
                Đăng xuất
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
