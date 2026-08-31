import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Bell, Check, ShieldAlert, Lock, Sparkles, Wrench, Zap } from 'lucide-react';
import { AppSettings } from '../types';

interface NotificationSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
}

export const NotificationSettingsModal: React.FC<NotificationSettingsModalProps> = ({
  isOpen,
  onClose,
  settings,
  onUpdateSettings,
}) => {
  const [complete, setComplete] = useState(settings.notifyOnTargetReached ?? true);
  const [remind, setRemind] = useState(settings.notifyReminder ?? true);
  const [aiUpdate, setAiUpdate] = useState(settings.notifyAiUpdate ?? false);
  const [maintenance, setMaintenance] = useState(settings.notifyMaintenance ?? true);
  const [savedSuccess, setSavedSuccess] = useState(false);

  const handleSave = () => {
    onUpdateSettings({
      notifyOnTargetReached: complete,
      notifyReminder: remind,
      notifyAiUpdate: aiUpdate,
      notifyMaintenance: maintenance,
    });
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
      onClose();
    }, 600);
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
                  <Bell className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Thông báo</h3>
                  <p className="text-[11px] text-slate-400">Tùy chỉnh các loại thông báo đẩy & cảnh báo</p>
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

            <div className="mt-4 space-y-2.5">
              {/* Row 1: Sạc hoàn tất */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Sạc hoàn tất</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Báo khi pin đạt % thiết lập</div>
                </div>
                <button
                  type="button"
                  onClick={() => setComplete(!complete)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    complete ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    complete ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              {/* Row 2: Sạc bị dừng bất thường (Locked ON) */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Sạc bị dừng bất thường</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Mất điện nguồn hoặc ngắt rơ le khẩn cấp</div>
                </div>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 text-[10px] font-bold border border-emerald-500/30 flex items-center gap-1">
                  <Lock className="w-2.5 h-2.5" /> Luôn bật
                </span>
              </div>

              {/* Row 3: Cảnh báo an toàn (Locked ON) */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Cảnh báo an toàn</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Quá nhiệt cell pin, quá áp &gt;250V, dòng rò</div>
                </div>
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-400 text-[10px] font-bold border border-emerald-500/30 flex items-center gap-1">
                  <Lock className="w-2.5 h-2.5" /> Luôn bật
                </span>
              </div>

              {/* Row 4: Nhắc sạc */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Nhắc sạc xe ban đêm</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Nhắc cắm sạc khi pin còn &lt;30% sau 21:00</div>
                </div>
                <button
                  type="button"
                  onClick={() => setRemind(!remind)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    remind ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    remind ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              {/* Row 5: AI đã cập nhật cho xe */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">AI đã cập nhật cho xe</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Thông báo khi mô hình máy học hoàn tất chu kỳ học mới</div>
                </div>
                <button
                  type="button"
                  onClick={() => setAiUpdate(!aiUpdate)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    aiUpdate ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    aiUpdate ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>

              {/* Row 6: Bảo dưỡng */}
              <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div>
                  <div className="text-xs font-bold text-white">Nhắc bảo dưỡng định kỳ</div>
                  <div className="text-[11px] text-slate-400 mt-0.5">Cân bằng cell pin LFP & kiểm tra xe mỗi 10.000km</div>
                </div>
                <button
                  type="button"
                  onClick={() => setMaintenance(!maintenance)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    maintenance ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    maintenance ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>
            </div>

            {/* Actions */}
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
                {savedSuccess ? <Check className="w-4 h-4 stroke-[3]" /> : null}
                {savedSuccess ? 'Đã lưu' : 'Lưu cấu hình'}
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
