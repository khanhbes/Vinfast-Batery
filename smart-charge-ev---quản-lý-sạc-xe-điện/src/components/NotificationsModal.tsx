import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Bell, CheckCircle2, AlertTriangle, Zap, ShieldCheck } from 'lucide-react';

interface NotificationsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

interface NotificationItem {
  id: string;
  title: string;
  message: string;
  time: string;
  type: 'success' | 'warning' | 'info';
  read: boolean;
}

export const NotificationsModal: React.FC<NotificationsModalProps> = ({ isOpen, onClose }) => {
  const [notifications, setNotifications] = useState<NotificationItem[]>([
    {
      id: '1',
      title: 'Pin đã sạc đầy 100%',
      message: 'Xe VinFast Feliz 2025 đã đạt mức pin mục tiêu 100%. Tự động ngắt nguồn an toàn.',
      time: '08:17 Hôm nay',
      type: 'success',
      read: false,
    },
    {
      id: '2',
      title: 'Nhắc nhở cân bằng Cell Pin LFP',
      message: 'Đã 10 ngày kể từ lần sạc 100% gần nhất. Hãy cắm sạc đầy để BMS cân chỉnh điện áp.',
      time: 'Hôm qua, 21:00',
      type: 'info',
      read: true,
    },
    {
      id: '3',
      title: 'Cảnh báo nhiệt độ pin mùa hè',
      message: 'Nhiệt độ môi trường cao (36°C). Hệ thống giảm nhẹ dòng sạc xuống 4.2A để bảo vệ pin.',
      time: '28/08/2026',
      type: 'warning',
      read: true,
    },
  ]);

  const markAllAsRead = () => {
    setNotifications(notifications.map(n => ({ ...n, read: true })));
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
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[85vh] overflow-y-auto"
          >
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Bell className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Trung tâm thông báo</h3>
                  <p className="text-[11px] text-slate-400">Nhắc nhở sạc & cảnh báo an toàn xe</p>
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

            <div className="flex justify-between items-center mt-3 px-1">
              <span className="text-xs text-slate-400 font-medium">Lịch sử thông báo</span>
              <button
                type="button"
                onClick={markAllAsRead}
                className="text-xs text-emerald-400 hover:text-emerald-300 font-semibold"
              >
                Đánh dấu đã đọc
              </button>
            </div>

            <div className="mt-3 space-y-2.5">
              {notifications.map((item) => (
                <div
                  key={item.id}
                  className={`p-3.5 rounded-2xl border transition-all ${
                    item.read
                      ? 'bg-white/5 border-white/5 opacity-75'
                      : 'bg-[#111] border-emerald-500/30 shadow-sm'
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <div className={`w-8 h-8 rounded-xl shrink-0 flex items-center justify-center ${
                      item.type === 'success'
                        ? 'bg-emerald-500/20 text-emerald-400'
                        : item.type === 'warning'
                        ? 'bg-amber-500/20 text-amber-400'
                        : 'bg-sky-500/20 text-sky-400'
                    }`}>
                      {item.type === 'success' ? <Zap className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
                    </div>

                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-white">{item.title}</h4>
                        <span className="text-[10px] text-slate-500">{item.time}</span>
                      </div>
                      <p className="text-xs text-slate-300 mt-1 leading-relaxed">{item.message}</p>
                    </div>
                  </div>
                </div>
              ))}
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
