import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Info, Zap, ShieldCheck, Heart } from 'lucide-react';

interface AboutModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const AboutModal: React.FC<AboutModalProps> = ({ isOpen, onClose }) => {
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
            <div className="flex justify-end">
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="w-16 h-16 rounded-3xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center mx-auto shadow-lg shadow-emerald-500/20">
              <Zap className="w-8 h-8 fill-current" />
            </div>

            <h3 className="text-lg font-extrabold text-white mt-3">EV Smart Charge</h3>
            <p className="text-xs text-emerald-400 font-mono font-semibold">Phiên bản V1.0.83+2084</p>
            <p className="text-xs text-slate-400 mt-2 leading-relaxed">
              Giải pháp quản lý sạc thông minh, thuật toán tối ưu hóa tuổi thọ pin LFP và tự động ngắt nguồn an toàn cho xe điện.
            </p>

            <div className="mt-4 p-3 rounded-2xl bg-white/5 border border-white/5 text-left text-xs space-y-2">
              <div className="flex justify-between">
                <span className="text-slate-400">Kênh phát hành:</span>
                <span className="text-emerald-400 font-mono font-bold">STABLE CHANNEL</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Cập nhật lần cuối:</span>
                <span className="text-slate-300 font-mono">31/08/2026</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-400">Trạng thái hệ thống:</span>
                <span className="text-emerald-400 font-semibold flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                  Trực tuyến
                </span>
              </div>
            </div>

            <div className="mt-5">
              <button
                type="button"
                onClick={onClose}
                className="w-full py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-200 text-xs font-bold border border-white/5"
              >
                Đóng
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
