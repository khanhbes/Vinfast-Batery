import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, HelpCircle, ChevronDown, ChevronUp, ShieldCheck, Zap } from 'lucide-react';

interface HelpFaqModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const HelpFaqModal: React.FC<HelpFaqModalProps> = ({ isOpen, onClose }) => {
  const [openIdx, setOpenIdx] = useState<number | null>(0);

  const faqs = [
    {
      q: 'Tại sao pin LFP nên sạc 80% hàng ngày nhưng sạc 100% định kỳ?',
      a: 'Pin Lithium Iron Phosphate (LFP) có tuổi thọ chu kỳ rất cao. Giữ pin ở mức 20% - 80% giúp giảm ứng suất hóa học lên màng ngăn. Tuy nhiên, đường cong xả của pin LFP rất phẳng, nên cần sạc 100% mỗi 1-2 tuần để mạch BMS cân bằng điện áp các cell và đo đạc lại % pin chính xác nhất.',
    },
    {
      q: 'Tính năng Tự động ngắt khi đạt % pin hoạt động ra sao?',
      a: 'Ứng dụng liên tục tính toán năng lượng nạp và đồng bộ cùng mạch BMS/công tơ điện thông minh. Khi dung lượng pin đạt ngưỡng bạn đã thiết lập (ví dụ 80% hoặc 90%), lệnh ngắt relay an toàn sẽ được gửi qua Cloud/LAN để ngừng dòng điện.',
    },
    {
      q: 'Cách thiết lập giờ sạc đêm để tiết kiệm chi phí?',
      a: 'Bạn có thể chọn chế độ Night Eco trong màn hình sạc. Hệ thống sẽ tự động hẹn giờ bật sạc sau 22:00 khi biểu giá điện giờ thấp điểm có hiệu lực và tự ngắt trước 06:00 sáng hôm sau.',
    },
    {
      q: 'Làm sao để kết nối với xe qua Bluetooth BMS?',
      a: 'Bật Bluetooth trên điện thoại, đưa xe về gần trong phạm vi 5 mét. Vào mục Hiệu chỉnh pin -> Nhấn "Đọc BMS" để ứng dụng tự động dò và đồng bộ điện áp từng cell pin.',
    },
  ];

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
                  <HelpCircle className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">FAQ & Hướng dẫn</h3>
                  <p className="text-[11px] text-slate-400">Giải đáp thắc mắc & cẩm nang sạc xe điện</p>
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
              {faqs.map((faq, idx) => {
                const isOpenItem = openIdx === idx;
                return (
                  <div
                    key={idx}
                    className="rounded-2xl bg-white/5 border border-white/5 overflow-hidden transition-colors"
                  >
                    <button
                      type="button"
                      onClick={() => setOpenIdx(isOpenItem ? null : idx)}
                      className="w-full p-3.5 text-left flex items-center justify-between gap-2"
                    >
                      <span className="text-xs font-bold text-white leading-snug">{faq.q}</span>
                      {isOpenItem ? (
                        <ChevronUp className="w-4 h-4 text-emerald-400 shrink-0" />
                      ) : (
                        <ChevronDown className="w-4 h-4 text-slate-500 shrink-0" />
                      )}
                    </button>

                    {isOpenItem && (
                      <div className="px-3.5 pb-3.5 text-xs text-slate-300 leading-relaxed border-t border-white/5 pt-2.5 bg-[#050505]/40">
                        {faq.a}
                      </div>
                    )}
                  </div>
                );
              })}
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
