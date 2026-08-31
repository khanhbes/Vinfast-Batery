import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, BatteryMedium, Bluetooth, RefreshCw, CheckCircle, Info } from 'lucide-react';

interface CalibrateModalProps {
  isOpen: boolean;
  onClose: () => void;
  currentPercent: number;
  onSavePercent: (percent: number) => void;
  isBmsConnected: boolean;
  onToggleBmsSync: () => void;
}

export const CalibrateModal: React.FC<CalibrateModalProps> = ({
  isOpen,
  onClose,
  currentPercent,
  onSavePercent,
  isBmsConnected,
  onToggleBmsSync,
}) => {
  const [val, setVal] = useState(currentPercent);
  const [isSyncing, setIsSyncing] = useState(false);

  const handleSyncBMS = () => {
    setIsSyncing(true);
    setTimeout(() => {
      setIsSyncing(false);
      onToggleBmsSync();
      // Simulate BMS returning true battery level
      const syncedVal = Math.max(10, Math.min(100, Math.round(val)));
      setVal(syncedVal);
      onSavePercent(syncedVal);
      onClose();
    }, 900);
  };

  const handleSave = () => {
    onSavePercent(val);
    onClose();
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
            className="relative w-full max-w-sm bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 shadow-2xl z-10"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <BatteryMedium className="w-4 h-4" />
                </div>
                <h3 className="text-sm font-bold text-white">Hiệu chỉnh pin hiện tại</h3>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-7 h-7 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="mt-4 space-y-4">
              <div className="text-center py-4 bg-[#050505] rounded-2xl border border-white/5 shadow-inner">
                <div className="text-4xl font-extrabold font-mono-num text-emerald-400">{val}%</div>
                <p className="text-xs text-slate-400 mt-1">Dung lượng pin thực tế trên đồng hồ xe</p>
              </div>

              {/* Slider */}
              <input
                type="range"
                min="5"
                max="100"
                value={val}
                onChange={(e) => setVal(Number(e.target.value))}
                className="w-full h-2 bg-white/10 rounded-lg appearance-none cursor-pointer accent-emerald-400"
              />

              {/* Quick Jump Buttons */}
              <div className="grid grid-cols-4 gap-1.5">
                {[20, 50, 75, 100].map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setVal(p)}
                    className="py-1.5 px-2 rounded-xl bg-white/5 hover:bg-white/10 text-xs font-mono-num text-slate-300 border border-white/5 transition-colors"
                  >
                    {p}%
                  </button>
                ))}
              </div>

              {/* Bluetooth BMS Sync Option */}
              <div className="p-3.5 rounded-2xl bg-white/5 border border-white/5 flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <Bluetooth className={`w-4 h-4 ${isBmsConnected ? 'text-emerald-400' : 'text-slate-500'}`} />
                  <div>
                    <div className="text-xs font-semibold text-slate-200">Đồng bộ BMS qua Bluetooth</div>
                    <div className="text-[10px] text-slate-400">
                      {isBmsConnected ? 'Đã kết nối BMS VinFast' : 'Chưa kết nối Bluetooth xe'}
                    </div>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={handleSyncBMS}
                  disabled={isSyncing}
                  className="px-3 py-1.5 rounded-xl bg-white/5 hover:bg-white/10 text-emerald-400 text-xs font-medium flex items-center gap-1 border border-emerald-500/30 transition-colors disabled:opacity-50"
                >
                  <RefreshCw className={`w-3 h-3 ${isSyncing ? 'animate-spin' : ''}`} />
                  {isSyncing ? 'Đang đọc...' : 'Đọc BMS'}
                </button>
              </div>

              <p className="text-[11px] text-slate-400 flex items-start gap-1.5 leading-relaxed">
                <Info className="w-3.5 h-3.5 text-emerald-400/80 shrink-0 mt-0.5" />
                Nếu chưa kết nối Bluetooth trực tiếp với xe, bạn có thể nhập % pin hiển thị trên màn hình xe để thuật toán tính giờ sạc chuẩn xác nhất.
              </p>
            </div>

            <div className="mt-5 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={onClose}
                className="py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-semibold border border-white/5"
              >
                Hủy
              </button>
              <button
                type="button"
                onClick={handleSave}
                className="py-2.5 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-bold shadow-lg shadow-emerald-500/20"
              >
                Lưu hiệu chỉnh
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};

