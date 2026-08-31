import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  X, CheckCircle2, Clock, Zap, Battery, Calendar, ShieldCheck, 
  ChevronDown, ChevronUp, EyeOff, ThumbsUp, AlertTriangle, Sparkles, Flame 
} from 'lucide-react';
import { ChargingSession } from '../types';
import { ChargeHistoryChart } from './ChargeHistoryChart';

interface SessionDetailModalProps {
  session: ChargingSession | null;
  onClose: () => void;
  onHideSession?: (sessionId: string) => void;
  onConfirmActualSoc?: (sessionId: string, confirmedSoc: number) => void;
}

export const SessionDetailModal: React.FC<SessionDetailModalProps> = ({
  session,
  onClose,
  onHideSession,
  onConfirmActualSoc,
}) => {
  const [showTechnicalDetails, setShowTechnicalDetails] = useState(false);
  const [isEditingSoc, setIsEditingSoc] = useState(false);
  const [customSoc, setCustomSoc] = useState<number>(session ? (session.confirmedEndSoc || session.endPercent) : 80);
  const [showHideToast, setShowHideToast] = useState(false);

  if (!session) return null;

  const formatHoursMinutes = (mins: number) => {
    if (mins < 60) return `${mins} phút`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h} giờ ${m} phút` : `${h} giờ`;
  };

  // Status mapping based on Section 12
  const getStatusDisplay = () => {
    if (session.terminalState === 'completed' || session.status === 'completed') {
      return { label: 'Hoàn tất', color: 'text-emerald-400 bg-emerald-500/10 border-emerald-500/30', icon: CheckCircle2 };
    }
    if (session.terminalState === 'cancelled' || session.status === 'stopped') {
      return { label: 'Dừng sớm', color: 'text-amber-400 bg-amber-500/10 border-amber-500/30', icon: AlertTriangle };
    }
    if (session.terminalState === 'interrupted') {
      return { label: 'Bị gián đoạn', color: 'text-orange-400 bg-orange-500/10 border-orange-500/30', icon: AlertTriangle };
    }
    if (session.terminalState === 'safety_stop') {
      return { label: 'Đã ngắt an toàn', color: 'text-rose-400 bg-rose-500/10 border-rose-500/30', icon: ShieldCheck };
    }
    return { label: 'Không hoàn tất', color: 'text-slate-400 bg-white/5 border-white/10', icon: AlertTriangle };
  };

  const statusInfo = getStatusDisplay();
  const StatusIcon = statusInfo.icon;

  const handleHide = () => {
    setShowHideToast(true);
    setTimeout(() => {
      if (onHideSession) {
        onHideSession(session.id);
      }
      onClose();
    }, 400);
  };

  const handleSaveConfirmedSoc = (soc: number) => {
    if (onConfirmActualSoc) {
      onConfirmActualSoc(session.id, soc);
    }
    setIsEditingSoc(false);
  };

  return (
    <AnimatePresence>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 overflow-y-auto">
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          className="fixed inset-0 bg-black/80 backdrop-blur-md"
        />

        <motion.div
          initial={{ scale: 0.95, opacity: 0, y: 10 }}
          animate={{ scale: 1, opacity: 1, y: 0 }}
          exit={{ scale: 0.95, opacity: 0, y: 10 }}
          className="relative w-full max-w-md bg-[#0e0e0e] border border-white/10 rounded-3xl p-5 shadow-2xl z-10 my-auto max-h-[92vh] overflow-y-auto no-scrollbar"
        >
          {/* Header */}
          <div className="flex items-center justify-between pb-3 border-b border-white/5">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-2xl bg-emerald-500/15 text-emerald-400 border border-emerald-500/25 flex items-center justify-center">
                <Battery className="w-4 h-4" />
              </div>
              <div>
                <h3 className="text-sm font-bold text-white flex items-center gap-1.5">
                  <span>Chi tiết phiên sạc</span>
                  <span className="text-slate-600 font-normal">•</span>
                  <span className="text-slate-400 font-normal text-xs">{session.vehicleNameSnapshot || 'VinFast EV'}</span>
                </h3>
                <div className="text-[10px] text-slate-500 font-mono">
                  {session.dateStr} • {session.timeStr}
                </div>
              </div>
            </div>

            <button
              type="button"
              onClick={onClose}
              className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5 transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>

          {/* Body */}
          <div className="mt-4 space-y-3.5">
            {/* Primary Battery SOC Progress Card */}
            <div className="p-4 rounded-3xl bg-[#141414] border border-white/5 text-center relative overflow-hidden">
              <div className="flex items-center justify-between mb-1.5 px-1">
                <span className="text-[11px] text-slate-400">
                  {session.isSocEstimated ? 'Pin ước tính' : 'Mức pin thực tế'}
                </span>
                <span className={`text-[10px] px-2.5 py-0.5 rounded-full font-semibold border flex items-center gap-1 ${statusInfo.color}`}>
                  <StatusIcon className="w-3 h-3" />
                  {statusInfo.label}
                </span>
              </div>

              <div className="flex items-center justify-center gap-3 py-1">
                <span className="text-2xl font-bold font-mono-num text-slate-300">{session.startPercent}%</span>
                <span className="text-emerald-400 font-bold text-lg">→</span>
                <span className="text-3xl font-extrabold font-mono-num text-emerald-400">{session.endPercent}%</span>
              </div>

              {session.terminalState === 'cancelled' && (
                <div className="text-[11px] text-slate-400 font-medium mt-1">
                  Mục tiêu ban đầu: {session.targetPercent}%
                </div>
              )}
            </div>

            {/* Primary Metrics Grid (Duration, Energy, Mode) */}
            <div className="grid grid-cols-3 gap-2 text-center text-xs">
              <div className="p-3 rounded-2xl bg-white/5 border border-white/5">
                <span className="text-[10px] text-slate-400 block mb-1">Thời gian</span>
                <span className="text-xs font-bold text-white font-mono-num block">
                  {formatHoursMinutes(session.durationMinutes)}
                </span>
              </div>

              <div className="p-3 rounded-2xl bg-white/5 border border-white/5">
                <span className="text-[10px] text-slate-400 block mb-1">Năng lượng</span>
                <span className="text-xs font-bold text-emerald-400 font-mono-num block">
                  {session.energyWh >= 1000 ? `${(session.energyWh / 1000).toFixed(2)} kWh` : `${session.energyWh} Wh`}
                </span>
              </div>

              <div className="p-3 rounded-2xl bg-white/5 border border-white/5">
                <span className="text-[10px] text-slate-400 block mb-1">Chế độ sạc</span>
                <span className="text-xs font-bold text-slate-200 block">
                  {session.strategy === 'ai_target' ? 'Sạc AI' : 'Thủ công'}
                </span>
              </div>
            </div>

            {/* Interactive Telemetry Chart */}
            <div>
              <div className="text-xs font-semibold text-slate-300 mb-2 flex items-center justify-between">
                <span>Diễn biến phiên sạc</span>
                <span className="text-[10px] text-slate-500 font-mono">1 chart viewport</span>
              </div>
              <ChargeHistoryChart session={session} />
            </div>

            {/* AI Prediction vs Actual Comparison */}
            {session.predictedMinutes && session.predictedMinutes > 0 && (
              <div className="p-3.5 rounded-2xl bg-emerald-500/5 border border-emerald-500/15 text-xs flex items-center justify-between">
                <div>
                  <span className="text-slate-400 block text-[11px]">Dự đoán AI</span>
                  <span className="font-bold text-slate-200 font-mono-num mt-0.5 block">
                    {formatHoursMinutes(session.predictedMinutes)}
                  </span>
                </div>

                <div className="h-6 w-[1px] bg-white/10"></div>

                <div>
                  <span className="text-slate-400 block text-[11px]">Thực tế</span>
                  <span className="font-bold text-emerald-400 font-mono-num mt-0.5 block">
                    {formatHoursMinutes(session.durationMinutes)}
                  </span>
                </div>

                <div className="h-6 w-[1px] bg-white/10"></div>

                <div className="text-right">
                  <span className="text-slate-400 block text-[11px]">Độ lệch</span>
                  <span className="font-bold text-slate-300 font-mono-num mt-0.5 block">
                    {session.durationMinutes - session.predictedMinutes >= 0 ? `+${session.durationMinutes - session.predictedMinutes}m` : `${session.durationMinutes - session.predictedMinutes}m`}
                  </span>
                </div>
              </div>
            )}

            {/* End-of-charge SOC confirmation (Section 33) */}
            <div className="p-3.5 rounded-2xl bg-white/[0.03] border border-white/5 text-xs">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5 text-slate-300">
                  <ThumbsUp className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Pin sau khi sạc:</span>
                  <strong className="text-emerald-400 font-mono-num font-bold">
                    {session.confirmedEndSoc || session.endPercent}%
                  </strong>
                </div>

                {!isEditingSoc ? (
                  <button
                    type="button"
                    onClick={() => setIsEditingSoc(true)}
                    className="px-2.5 py-1 rounded-xl bg-white/5 hover:bg-white/10 text-slate-300 text-[11px] font-semibold transition-colors"
                  >
                    Chỉnh
                  </button>
                ) : (
                  <div className="flex items-center gap-1.5">
                    <input
                      type="number"
                      min={1}
                      max={100}
                      value={customSoc}
                      onChange={(e) => setCustomSoc(Number(e.target.value))}
                      className="w-12 bg-black/60 border border-white/10 rounded-lg px-1.5 py-0.5 text-xs font-mono text-center text-white"
                    />
                    <button
                      type="button"
                      onClick={() => handleSaveConfirmedSoc(customSoc)}
                      className="px-2 py-0.5 rounded-lg bg-emerald-500 text-slate-950 text-[11px] font-bold"
                    >
                      Lưu
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* Technical Detail Accordion (Section 13, 23, 36) */}
            <div className="border border-white/5 rounded-2xl overflow-hidden bg-white/[0.02]">
              <button
                type="button"
                onClick={() => setShowTechnicalDetails(!showTechnicalDetails)}
                className="w-full p-3.5 text-xs font-semibold text-slate-300 flex items-center justify-between hover:bg-white/5 transition-colors"
              >
                <span>Xem chi tiết kỹ thuật</span>
                {showTechnicalDetails ? <ChevronUp className="w-4 h-4 text-slate-400" /> : <ChevronDown className="w-4 h-4 text-slate-400" />}
              </button>

              {showTechnicalDetails && (
                <div className="p-3.5 pt-0 space-y-2 text-xs border-t border-white/5 text-slate-400">
                  <div className="flex justify-between py-1 border-b border-white/5">
                    <span>Điện áp trung bình:</span>
                    <span className="text-slate-200 font-mono">{session.averageVoltageV || 228} V</span>
                  </div>
                  <div className="flex justify-between py-1 border-b border-white/5">
                    <span>Dòng điện trung bình:</span>
                    <span className="text-slate-200 font-mono">{session.averageCurrentA || 4.14} A</span>
                  </div>
                  <div className="flex justify-between py-1 border-b border-white/5">
                    <span>Công suất đỉnh (Peak):</span>
                    <span className="text-slate-200 font-mono">{session.peakPowerW || 995} W</span>
                  </div>
                  <div className="flex justify-between py-1 border-b border-white/5">
                    <span>Nhiệt độ tối đa:</span>
                    <span className="text-slate-200 font-mono">{session.maxPlugTemperatureC || 38}°C</span>
                  </div>
                  <div className="flex justify-between py-1 border-b border-white/5">
                    <span>Chất lượng đo lường:</span>
                    <span className="text-emerald-400 font-semibold">{session.energyQuality === 'good' ? 'Hoàn hảo (Good)' : 'Một phần'}</span>
                  </div>
                  <div className="flex justify-between py-1">
                    <span>Huấn luyện Personal AI:</span>
                    <span className="text-emerald-400 font-semibold">{session.trainingEligible ? 'Đạt chuẩn huấn luyện' : 'Bỏ qua (Safety/Partial)'}</span>
                  </div>
                  {session.stopReason && (
                    <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-[11px] text-amber-300 mt-2">
                      <strong>Lý do kết thúc:</strong> {session.stopReason}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Soft Hide Action Button (Section 29: Hide không phải Delete) */}
            <div className="flex items-center justify-between pt-1">
              <button
                type="button"
                onClick={handleHide}
                className="text-xs text-slate-500 hover:text-slate-300 flex items-center gap-1.5 py-2 px-1 transition-colors"
              >
                <EyeOff className="w-3.5 h-3.5" />
                <span>Ẩn khỏi lịch sử</span>
              </button>

              <button
                type="button"
                onClick={onClose}
                className="py-2.5 px-6 rounded-2xl bg-white/10 hover:bg-white/15 text-white text-xs font-bold transition-colors"
              >
                Đóng
              </button>
            </div>
          </div>
        </motion.div>
      </div>
    </AnimatePresence>
  );
};
