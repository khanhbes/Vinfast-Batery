import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Database, History, EyeOff, RotateCcw, Download, Sparkles, Check, ChevronRight } from 'lucide-react';
import { ChargingSession } from '../types';

interface DataSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  sessions: ChargingSession[];
  onNavigateToHistory: () => void;
  onRestoreSession?: (id: string) => void;
  allowDataForAi: boolean;
  onToggleAllowDataForAi: (enabled: boolean) => void;
}

export const DataSettingsModal: React.FC<DataSettingsModalProps> = ({
  isOpen,
  onClose,
  sessions,
  onNavigateToHistory,
  onRestoreSession,
  allowDataForAi,
  onToggleAllowDataForAi,
}) => {
  const [showHiddenList, setShowHiddenList] = useState(false);
  const [downloadSuccess, setDownloadSuccess] = useState(false);

  const hiddenSessions = sessions.filter(s => s.isHidden);

  const handleExportData = () => {
    // Generate JSON export payload
    const exportPayload = {
      app: 'EV Smart Charge',
      version: '1.4.0',
      exportedAt: new Date().toISOString(),
      sessionsCount: sessions.length,
      sessions: sessions,
    };
    const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(exportPayload, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute("href", dataStr);
    downloadAnchor.setAttribute("download", `ev_charging_data_${new Date().toISOString().slice(0, 10)}.json`);
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();

    setDownloadSuccess(true);
    setTimeout(() => setDownloadSuccess(false), 2500);
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
                  <Database className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Lịch sử & dữ liệu</h3>
                  <p className="text-[11px] text-slate-400">Quản lý các bản ghi sạc và xuất dữ liệu</p>
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

            {/* List of Data Actions */}
            <div className="mt-4 space-y-2.5">
              {/* Shortcut to History Tab */}
              <button
                type="button"
                onClick={() => {
                  onClose();
                  onNavigateToHistory();
                }}
                className="w-full p-4 rounded-2xl bg-[#111] hover:bg-[#151515] border border-white/5 flex items-center justify-between text-left transition-colors group"
              >
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                    <History className="w-4 h-4" />
                  </div>
                  <div>
                    <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                      Lịch sử sạc
                    </div>
                    <div className="text-[11px] text-slate-400 mt-0.5">
                      Xem danh sách {sessions.length} phiên sạc đã ghi nhận
                    </div>
                  </div>
                </div>
                <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
              </button>

              {/* Mục đã ẩn */}
              <div className="rounded-2xl bg-[#111] border border-white/5 overflow-hidden">
                <button
                  type="button"
                  onClick={() => setShowHiddenList(!showHiddenList)}
                  className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-9 h-9 rounded-xl bg-white/5 text-slate-300 flex items-center justify-center">
                      <EyeOff className="w-4 h-4" />
                    </div>
                    <div>
                      <div className="text-xs font-bold text-white">Mục đã ẩn</div>
                      <div className="text-[11px] text-slate-400 mt-0.5">
                        {hiddenSessions.length} phiên sạc bị ẩn khỏi dòng thời gian
                      </div>
                    </div>
                  </div>
                  <span className="text-[11px] font-medium text-emerald-400">
                    {showHiddenList ? 'Thu gọn' : 'Xem & Khôi phục'}
                  </span>
                </button>

                {showHiddenList && (
                  <div className="p-3 bg-[#050505] border-t border-white/5 space-y-2">
                    {hiddenSessions.length === 0 ? (
                      <div className="py-2 text-center text-xs text-slate-500">
                        Không có phiên sạc nào đang bị ẩn
                      </div>
                    ) : (
                      hiddenSessions.map(s => (
                        <div
                          key={s.id}
                          className="p-2.5 rounded-xl bg-white/5 flex items-center justify-between text-xs"
                        >
                          <div>
                            <span className="font-bold text-white">{s.dateStr} • {s.timeStr}</span>
                            <span className="text-[10px] text-slate-400 block">{s.energyWh} Wh • {s.chargerName}</span>
                          </div>
                          <button
                            type="button"
                            onClick={() => onRestoreSession?.(s.id)}
                            className="px-2.5 py-1 rounded-lg bg-emerald-500/20 text-emerald-400 text-xs font-bold flex items-center gap-1 hover:bg-emerald-500 hover:text-slate-950 transition-colors"
                          >
                            <RotateCcw className="w-3 h-3" />
                            Khôi phục
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                )}
              </div>

              {/* Xuất dữ liệu */}
              <button
                type="button"
                onClick={handleExportData}
                className="w-full p-4 rounded-2xl bg-[#111] hover:bg-[#151515] border border-white/5 flex items-center justify-between text-left transition-colors group"
              >
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                    <Download className="w-4 h-4" />
                  </div>
                  <div>
                    <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                      Xuất dữ liệu (JSON / CSV)
                    </div>
                    <div className="text-[11px] text-slate-400 mt-0.5">
                      Sao lưu toàn bộ lịch sử sạc & chu kỳ pin
                    </div>
                  </div>
                </div>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-white/5 text-slate-300 border border-white/10">
                  {downloadSuccess ? 'Đã tải xuống' : 'Tải về'}
                </span>
              </button>

              {/* Quyền sử dụng dữ liệu cho AI */}
              <div className="p-4 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-xl bg-white/5 text-slate-300 flex items-center justify-center">
                    <Sparkles className="w-4 h-4 text-emerald-400" />
                  </div>
                  <div>
                    <div className="text-xs font-bold text-white">Quyền sử dụng dữ liệu cho AI</div>
                    <div className="text-[11px] text-slate-400 mt-0.5">
                      Cho phép thuật toán học từ các lần sạc của xe
                    </div>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => onToggleAllowDataForAi(!allowDataForAi)}
                  className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                    allowDataForAi ? 'bg-emerald-500' : 'bg-white/10'
                  }`}
                >
                  <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                    allowDataForAi ? 'translate-x-5' : 'translate-x-0'
                  }`} />
                </button>
              </div>
            </div>

            {/* Close button */}
            <div className="mt-5">
              <button
                type="button"
                onClick={onClose}
                className="w-full py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-200 text-xs font-bold border border-white/5 transition-colors"
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
