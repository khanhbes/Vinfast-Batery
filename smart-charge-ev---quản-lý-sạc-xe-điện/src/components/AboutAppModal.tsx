import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Info, ShieldCheck, Sparkles, FileText, Code, Check, ExternalLink } from 'lucide-react';

interface AboutAppModalProps {
  isOpen: boolean;
  onClose: () => void;
  developerModeUnlocked: boolean;
  onUnlockDeveloperMode: () => void;
}

export const AboutAppModal: React.FC<AboutAppModalProps> = ({
  isOpen,
  onClose,
  developerModeUnlocked,
  onUnlockDeveloperMode,
}) => {
  const [tapCount, setTapCount] = useState(0);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const handleVersionTap = () => {
    if (developerModeUnlocked) {
      setToastMessage('Bạn đã là Nhà phát triển!');
      setTimeout(() => setToastMessage(null), 2000);
      return;
    }

    const nextCount = tapCount + 1;
    setTapCount(nextCount);

    if (nextCount >= 7) {
      onUnlockDeveloperMode();
      setToastMessage('Đã mở khóa Chế độ Nhà phát triển!');
      setTapCount(0);
      setTimeout(() => setToastMessage(null), 3000);
    } else if (nextCount >= 3) {
      const remaining = 7 - nextCount;
      setToastMessage(`Bạn còn ${remaining} bước nữa để trở thành Nhà phát triển.`);
      setTimeout(() => setToastMessage(null), 1500);
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
                  <Info className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Thông tin ứng dụng</h3>
                  <p className="text-[11px] text-slate-400">Phiên bản & chính sách hệ sinh thái</p>
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

            {/* App Icon Banner */}
            <div className="mt-4 p-5 rounded-2xl bg-[#111] border border-white/5 text-center space-y-2">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-tr from-emerald-600 to-sky-500 text-white font-black text-2xl flex items-center justify-center mx-auto shadow-xl shadow-emerald-500/20 border border-white/10">
                ⚡
              </div>
              <h4 className="font-extrabold text-white text-base">EV Smart Charging</h4>
              <p className="text-xs text-slate-400">Hệ thống quản lý sạc & AI dự đoán dành cho xe điện</p>
            </div>

            {/* Version & Easter Egg Developer Trigger */}
            <div className="mt-4 space-y-2.5">
              <button
                type="button"
                onClick={handleVersionTap}
                className="w-full p-4 rounded-2xl bg-[#111] hover:bg-[#151515] border border-white/5 flex items-center justify-between text-left transition-colors active:scale-[0.99]"
              >
                <div>
                  <div className="text-xs font-bold text-white">Phiên bản ứng dụng</div>
                  <div className="text-[11px] text-slate-400 mt-0.5 font-mono">1.4.0 (Build 2026.08.31-PROD)</div>
                </div>
                {developerModeUnlocked ? (
                  <span className="px-2.5 py-1 rounded-full bg-emerald-500/20 text-emerald-400 text-[10px] font-bold border border-emerald-500/30 flex items-center gap-1 font-mono">
                    <Code className="w-3 h-3" /> Dev Mode ON
                  </span>
                ) : (
                  <span className="text-[10px] text-slate-500 font-mono">Mới nhất</span>
                )}
              </button>

              {/* Toast message for tap counts */}
              {toastMessage && (
                <motion.div
                  initial={{ opacity: 0, y: -5 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/30 text-center text-xs text-emerald-400 font-bold"
                >
                  {toastMessage}
                </motion.div>
              )}

              {/* Terms of service */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between text-xs text-slate-300">
                <div className="flex items-center gap-2.5">
                  <FileText className="w-4 h-4 text-slate-400" />
                  <span>Điều khoản dịch vụ</span>
                </div>
                <ExternalLink className="w-3.5 h-3.5 text-slate-500" />
              </div>

              {/* Privacy Policy */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between text-xs text-slate-300">
                <div className="flex items-center gap-2.5">
                  <ShieldCheck className="w-4 h-4 text-emerald-400" />
                  <span>Chính sách quyền riêng tư</span>
                </div>
                <ExternalLink className="w-3.5 h-3.5 text-slate-500" />
              </div>
            </div>

            {/* Footer */}
            <div className="mt-5 text-center text-[10px] text-slate-500">
              © 2026 EV Smart Charge Ecosystem. Bảo vệ bản quyền.
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
