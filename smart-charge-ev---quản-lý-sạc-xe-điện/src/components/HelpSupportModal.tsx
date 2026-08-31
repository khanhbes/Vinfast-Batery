import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, HelpCircle, BookOpen, ShieldCheck, Zap, Sparkles, Send, Check, ChevronDown, ChevronRight, Bug, AlertCircle } from 'lucide-react';

interface HelpSupportModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const HelpSupportModal: React.FC<HelpSupportModalProps> = ({
  isOpen,
  onClose,
}) => {
  const [expandedFaq, setExpandedFaq] = useState<string | null>('smart_charge');
  const [showReportBug, setShowReportBug] = useState(false);
  const [bugDescription, setBugDescription] = useState('');
  const [bugFunction, setBugFunction] = useState('charging_control');
  const [attachDiagnostics, setAttachDiagnostics] = useState(true);
  const [reportSent, setReportSent] = useState(false);

  const faqs = [
    {
      id: 'smart_charge',
      title: 'Sạc thông minh hoạt động thế nào?',
      icon: ShieldCheck,
      content: 'Khi bắt đầu phiên sạc, thời gian ngắt an toàn và giới hạn công suất được nạp trực tiếp vào bộ điều khiển rơ-le phần cứng. Nhờ vậy, ngay cả khi điện thoại tắt nguồn hoặc mất sóng Wi-Fi/4G, bộ sạc vẫn tự ngắt đúng thời điểm để bảo vệ cell pin.',
    },
    {
      id: 'pairing',
      title: 'Làm thế nào để kết nối bộ sạc mới?',
      icon: Zap,
      content: 'Cắm bộ sạc thông minh (ví dụ Shelly Plug S) vào nguồn điện. Mở Cài đặt > Bộ sạc & kết nối > Chọn xe và nhấn "Kết nối bộ sạc mới". Ứng dụng sẽ tự động dò tìm trong mạng nội bộ hoặc qua Cloud.',
    },
    {
      id: 'personal_ai',
      title: 'AI cá nhân dự đoán thời gian sạc như thế nào?',
      icon: Sparkles,
      content: 'AI cá nhân sử dụng thuật toán máy học cục bộ dựa trên dữ liệu sạc thực tế của riêng chiếc xe bạn (độ suy giảm cell pin, nhiệt độ môi trường, trở kháng thực tế). Dữ liệu này độc lập và không chia sẻ cho bất kỳ xe nào khác.',
    },
    {
      id: 'lfp_battery',
      title: 'Lời khuyên bảo vệ pin LFP (Lithium Iron Phosphate)?',
      icon: BookOpen,
      content: 'Pin LFP nên sạc hàng ngày đến 80-90% cho các nhu cầu di chuyển thông thường. Mỗi 1-2 tuần, bạn nên sạc đầy 100% để bộ quản lý pin (BMS) thực hiện cân bằng các cell điện áp đều nhau.',
    },
  ];

  const handleSendBugReport = (e: React.FormEvent) => {
    e.preventDefault();
    if (!bugDescription.trim()) return;
    setReportSent(true);
    setTimeout(() => {
      setReportSent(false);
      setShowReportBug(false);
      setBugDescription('');
    }, 2000);
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
                  <HelpCircle className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Hướng dẫn & trợ giúp</h3>
                  <p className="text-[11px] text-slate-400">Câu hỏi thường gặp & gửi báo cáo lỗi</p>
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

            {!showReportBug ? (
              <div className="mt-4 space-y-3">
                <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Kiến thức & Hướng dẫn
                </div>

                {faqs.map((faq) => {
                  const isExpanded = expandedFaq === faq.id;
                  const Icon = faq.icon;
                  return (
                    <div
                      key={faq.id}
                      className="rounded-2xl bg-[#111] border border-white/5 overflow-hidden transition-colors"
                    >
                      <button
                        type="button"
                        onClick={() => setExpandedFaq(isExpanded ? null : faq.id)}
                        className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02]"
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-xl bg-white/5 text-emerald-400 flex items-center justify-center shrink-0">
                            <Icon className="w-4 h-4" />
                          </div>
                          <span className="text-xs font-bold text-white pr-2">{faq.title}</span>
                        </div>
                        {isExpanded ? (
                          <ChevronDown className="w-4 h-4 text-slate-400 shrink-0" />
                        ) : (
                          <ChevronRight className="w-4 h-4 text-slate-500 shrink-0" />
                        )}
                      </button>

                      {isExpanded && (
                        <div className="px-4 pb-4 pt-1 text-xs text-slate-300 leading-relaxed bg-[#0c0c0c]/40 border-t border-white/5">
                          {faq.content}
                        </div>
                      )}
                    </div>
                  );
                })}

                {/* Bug Report Button */}
                <div className="pt-2">
                  <button
                    type="button"
                    onClick={() => setShowReportBug(true)}
                    className="w-full p-4 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/10 flex items-center justify-between text-left transition-colors group"
                  >
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-xl bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center justify-center">
                        <Bug className="w-4 h-4" />
                      </div>
                      <div>
                        <div className="text-xs font-bold text-white group-hover:text-amber-400 transition-colors">
                          Báo cáo sự cố hoặc lỗi
                        </div>
                        <div className="text-[11px] text-slate-400 mt-0.5">
                          Gửi phản hồi trực tiếp tới nhóm kỹ thuật
                        </div>
                      </div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
                  </button>
                </div>
              </div>
            ) : (
              /* Bug Report Form */
              <form onSubmit={handleSendBugReport} className="mt-4 space-y-3.5">
                <div className="flex items-center justify-between">
                  <button
                    type="button"
                    onClick={() => setShowReportBug(false)}
                    className="text-xs text-emerald-400 hover:text-emerald-300 font-medium flex items-center gap-1"
                  >
                    ← Quay lại câu hỏi thường gặp
                  </button>
                  <span className="text-xs font-bold text-amber-400">Gửi phản hồi</span>
                </div>

                <div className="space-y-1">
                  <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                    Chức năng gặp lỗi
                  </label>
                  <select
                    value={bugFunction}
                    onChange={(e) => setBugFunction(e.target.value)}
                    className="w-full bg-[#111] border border-white/10 rounded-2xl px-4 py-2.5 text-xs text-white focus:outline-none focus:border-emerald-500"
                  >
                    <option value="charging_control">Bật / Tắt sạc không phản hồi</option>
                    <option value="ai_prediction">Dự đoán thời gian sạc chưa chuẩn</option>
                    <option value="connection">Mất kết nối bộ sạc Shelly</option>
                    <option value="history_metrics">Lịch sử sạc bị sai số Wh/VNĐ</option>
                    <option value="other">Vấn đề khác</option>
                  </select>
                </div>

                <div className="space-y-1">
                  <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                    Mô tả vấn đề chi tiết
                  </label>
                  <textarea
                    rows={3}
                    required
                    value={bugDescription}
                    onChange={(e) => setBugDescription(e.target.value)}
                    placeholder="Mô tả sự cố bạn gặp phải và thời gian xảy ra..."
                    className="w-full bg-[#111] border border-white/10 rounded-2xl p-3 text-xs text-white placeholder:text-slate-600 focus:outline-none focus:border-emerald-500"
                  />
                </div>

                {/* Attach diagnostic data */}
                <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 flex items-center justify-between">
                  <div>
                    <div className="text-xs font-bold text-white">Đính kèm thông tin chẩn đoán</div>
                    <div className="text-[10px] text-slate-400 mt-0.5">Tự động loại bỏ mật khẩu, mã xác thực và token</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => setAttachDiagnostics(!attachDiagnostics)}
                    className={`w-12 h-7 rounded-full p-0.5 transition-colors ${
                      attachDiagnostics ? 'bg-emerald-500' : 'bg-white/10'
                    }`}
                  >
                    <div className={`w-6 h-6 rounded-full bg-slate-950 transition-transform shadow-md ${
                      attachDiagnostics ? 'translate-x-5' : 'translate-x-0'
                    }`} />
                  </button>
                </div>

                {reportSent && (
                  <div className="p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl text-xs text-emerald-400 text-center flex items-center justify-center gap-1.5">
                    <Check className="w-4 h-4 stroke-[3]" />
                    Cảm ơn bạn! Báo cáo lỗi đã được ghi nhận.
                  </div>
                )}

                <button
                  type="submit"
                  disabled={reportSent}
                  className="w-full py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-2 transition-colors"
                >
                  <Send className="w-4 h-4" />
                  Gửi báo cáo lỗi
                </button>
              </form>
            )}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
