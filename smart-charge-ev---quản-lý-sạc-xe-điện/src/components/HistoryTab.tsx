import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Zap, Clock, ChevronRight, CheckCircle2, AlertTriangle, 
  ShieldCheck, EyeOff, Sparkles, SlidersHorizontal, ArrowRight, BatteryCharging
} from 'lucide-react';
import { ChargingSession, Vehicle, LiveChargingMetrics } from '../types';

interface HistoryTabProps {
  sessions: ChargingSession[];
  vehicle: Vehicle;
  allVehicles?: Vehicle[];
  liveMetrics?: LiveChargingMetrics;
  onOpenSessionDetail: (session: ChargingSession) => void;
  onNavigateToCharging?: () => void;
  onHideSession?: (sessionId: string) => void;
}

type VehicleScope = 'current' | 'all';
type StrategyFilter = 'all' | 'ai' | 'manual';

export const HistoryTab: React.FC<HistoryTabProps> = ({
  sessions,
  vehicle,
  allVehicles = [],
  liveMetrics,
  onOpenSessionDetail,
  onNavigateToCharging,
  onHideSession,
}) => {
  const [vehicleScope, setVehicleScope] = useState<VehicleScope>('current');
  const [strategyFilter, setStrategyFilter] = useState<StrategyFilter>('all');
  const [visibleCount, setVisibleCount] = useState<number>(10);
  const [hiddenSessionToast, setHiddenSessionToast] = useState<string | null>(null);

  // 1. Filter out hidden sessions (Section 29)
  const unhiddenSessions = sessions.filter(s => !s.isHidden);

  // 2. Vehicle scope filter (Section 5)
  const scopedSessions = unhiddenSessions.filter(s => {
    if (vehicleScope === 'current') {
      return s.vehicleId === vehicle.id;
    }
    return true;
  });

  // 3. Strategy filter (Section 6)
  const filteredSessions = scopedSessions.filter(s => {
    if (strategyFilter === 'all') return true;
    if (strategyFilter === 'ai') return s.strategy === 'ai_target';
    if (strategyFilter === 'manual') return s.strategy === 'manual_timed' || s.strategy === 'manual';
    return true;
  });

  // 4. Pagination (Section 7 & 47)
  const paginatedSessions = filteredSessions.slice(0, visibleCount);
  const hasMore = visibleCount < filteredSessions.length;

  const handleLoadMore = () => {
    setVisibleCount(prev => prev + 10);
  };

  // 5. Monthly Summary stats (Section 32)
  const totalEnergyWh = scopedSessions.reduce((acc, s) => acc + (s.energyWh || 0), 0);
  const totalMinutes = scopedSessions.reduce((acc, s) => acc + (s.durationMinutes || 0), 0);
  const totalSessionCount = scopedSessions.length;

  const formatHoursMinutes = (mins: number) => {
    if (mins < 60) return `${mins} phút`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h} giờ ${m} phút` : `${h} giờ`;
  };

  const handleHide = (e: React.MouseEvent, sessionId: string) => {
    e.stopPropagation();
    if (onHideSession) {
      onHideSession(sessionId);
      setHiddenSessionToast('Đã ẩn phiên sạc khỏi danh sách.');
      setTimeout(() => setHiddenSessionToast(null), 3000);
    }
  };

  // Status mapping based on Section 12
  const getStatusBadge = (session: ChargingSession) => {
    if (session.terminalState === 'completed' || session.status === 'completed') {
      return (
        <span className="text-[11px] font-semibold text-emerald-400">
          Hoàn tất
        </span>
      );
    }
    if (session.terminalState === 'cancelled' || session.status === 'stopped') {
      return (
        <span className="text-[11px] font-semibold text-amber-400">
          Dừng sớm
        </span>
      );
    }
    if (session.terminalState === 'interrupted') {
      return (
        <span className="text-[11px] font-semibold text-orange-400">
          Bị gián đoạn
        </span>
      );
    }
    if (session.terminalState === 'safety_stop') {
      return (
        <span className="text-[11px] font-semibold text-rose-400">
          Đã ngắt an toàn
        </span>
      );
    }
    return (
      <span className="text-[11px] font-semibold text-slate-400">
        Không hoàn tất
      </span>
    );
  };

  return (
    <div id="history-view" className="space-y-4 pb-20 pt-1">
      {/* Scope Switcher & Strategy Header (Section 4 & 5) */}
      <div className="flex items-center justify-between gap-2 px-1">
        <h1 className="text-xl md:text-2xl font-black text-white tracking-tight">
          Lịch sử sạc
        </h1>

        {/* Vehicle Scope Switcher: [ Xe này ] [ Tất cả xe ] */}
        <div className="flex items-center gap-1 bg-white/5 p-1 rounded-2xl border border-white/5">
          <button
            type="button"
            onClick={() => setVehicleScope('current')}
            className={`px-3 py-1 rounded-xl text-xs font-semibold transition-all ${
              vehicleScope === 'current'
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            Xe này
          </button>
          <button
            type="button"
            onClick={() => setVehicleScope('all')}
            className={`px-3 py-1 rounded-xl text-xs font-semibold transition-all ${
              vehicleScope === 'all'
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            Tất cả xe
          </button>
        </div>
      </div>

      {/* Toast Notification */}
      {hiddenSessionToast && (
        <div className="p-3 bg-white/5 border border-white/10 rounded-2xl text-xs text-slate-300 flex items-center justify-between">
          <span>{hiddenSessionToast}</span>
          <button onClick={() => setHiddenSessionToast(null)} className="text-slate-400 hover:text-white text-xs">Đóng</button>
        </div>
      )}

      {/* LIVE SESSION CARD (Section 8) */}
      {liveMetrics?.isCharging && (
        <motion.div
          initial={{ opacity: 0, y: -8 }}
          animate={{ opacity: 1, y: 0 }}
          className="p-4 rounded-3xl bg-gradient-to-r from-emerald-950/40 via-[#0e1713] to-emerald-950/30 border border-emerald-500/40 shadow-xl relative overflow-hidden"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <span className="relative flex h-2.5 w-2.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-400"></span>
              </span>
              <span className="text-xs font-black text-emerald-400 uppercase tracking-wider">
                Đang sạc
              </span>
            </div>
            <span className="text-xs text-slate-300 font-semibold">{vehicle.name}</span>
          </div>

          <div className="flex items-baseline justify-between py-1">
            <div className="text-2xl font-black text-white font-mono-num">
              {Math.round(liveMetrics.currentPercent)}% <span className="text-emerald-400 text-lg">→</span> {liveMetrics.targetPercent}%
            </div>

            <div className="text-right">
              <span className="text-[10px] text-slate-400 block uppercase font-medium">Năng lượng</span>
              <span className="text-sm font-bold text-emerald-400 font-mono-num">
                {(liveMetrics.sessionEnergyWh / 1000).toFixed(2)} kWh
              </span>
            </div>
          </div>

          <div className="mt-3 pt-2.5 border-t border-white/5 flex items-center justify-between">
            <div className="text-xs text-slate-400 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5 text-emerald-400" />
              <span>Đã sạc {Math.round(liveMetrics.sessionDurationSeconds / 60)} phút</span>
            </div>

            {onNavigateToCharging && (
              <button
                type="button"
                onClick={onNavigateToCharging}
                className="px-3 py-1 rounded-xl bg-emerald-500 text-slate-950 text-xs font-bold flex items-center gap-1 hover:bg-emerald-400 transition-colors"
              >
                <span>Xem phiên sạc</span>
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </motion.div>
      )}

      {/* Monthly Summary Compact Box (Section 32) */}
      <div className="bg-[#111] border border-white/5 rounded-3xl p-4 shadow-md">
        <div className="flex items-center justify-between pb-3 border-b border-white/5 mb-3">
          <span className="text-xs font-bold text-slate-300">
            Tháng này
          </span>
          <span className="text-xs text-slate-500 font-mono">
            {vehicleScope === 'current' ? vehicle.name : 'Tất cả phương tiện'}
          </span>
        </div>

        <div className="grid grid-cols-3 gap-2 text-center">
          <div className="bg-white/5 p-2.5 rounded-2xl border border-white/5">
            <span className="text-[10px] text-slate-400 block mb-0.5">Số phiên</span>
            <span className="text-sm font-extrabold text-white font-mono-num">
              {totalSessionCount} <span className="text-[10px] text-slate-400 font-normal">phiên</span>
            </span>
          </div>

          <div className="bg-white/5 p-2.5 rounded-2xl border border-white/5">
            <span className="text-[10px] text-slate-400 block mb-0.5">Điện nạp</span>
            <span className="text-sm font-extrabold text-emerald-400 font-mono-num">
              {(totalEnergyWh / 1000).toFixed(2)} <span className="text-[10px] text-emerald-400/80 font-normal">kWh</span>
            </span>
          </div>

          <div className="bg-white/5 p-2.5 rounded-2xl border border-white/5">
            <span className="text-[10px] text-slate-400 block mb-0.5">Thời gian</span>
            <span className="text-sm font-extrabold text-slate-200 font-mono-num">
              {formatHoursMinutes(totalMinutes)}
            </span>
          </div>
        </div>
      </div>

      {/* Filter Tabs: [ Tất cả ] [ Sạc AI ] [ Thủ công ] (Section 6) */}
      <div className="flex items-center gap-1.5">
        <button
          type="button"
          onClick={() => setStrategyFilter('all')}
          className={`px-3.5 py-1.5 rounded-2xl text-xs font-semibold transition-all ${
            strategyFilter === 'all'
              ? 'bg-white/15 text-white font-bold border border-white/10'
              : 'bg-white/5 text-slate-400 border border-white/5 hover:text-white'
          }`}
        >
          Tất cả ({scopedSessions.length})
        </button>

        <button
          type="button"
          onClick={() => setStrategyFilter('ai')}
          className={`px-3.5 py-1.5 rounded-2xl text-xs font-semibold transition-all flex items-center gap-1.5 ${
            strategyFilter === 'ai'
              ? 'bg-white/15 text-white font-bold border border-white/10'
              : 'bg-white/5 text-slate-400 border border-white/5 hover:text-white'
          }`}
        >
          <Sparkles className="w-3 h-3 text-emerald-400" />
          <span>Sạc AI</span>
        </button>

        <button
          type="button"
          onClick={() => setStrategyFilter('manual')}
          className={`px-3.5 py-1.5 rounded-2xl text-xs font-semibold transition-all ${
            strategyFilter === 'manual'
              ? 'bg-white/15 text-white font-bold border border-white/10'
              : 'bg-white/5 text-slate-400 border border-white/5 hover:text-white'
          }`}
        >
          Thủ công
        </button>
      </div>

      {/* History Items Timeline (Section 11 & 12) */}
      <div className="space-y-2.5">
        {paginatedSessions.length === 0 ? (
          <div className="p-8 text-center rounded-3xl bg-[#111] border border-white/5 text-slate-500 text-xs">
            Chưa có phiên sạc nào phù hợp với bộ lọc hiện tại.
          </div>
        ) : (
          paginatedSessions.map((session) => {
            const isAi = session.strategy === 'ai_target';
            const energyStr = session.energyWh >= 1000 ? `${(session.energyWh / 1000).toFixed(2)} kWh` : `${session.energyWh} Wh`;

            return (
              <div
                key={session.id}
                onClick={() => onOpenSessionDetail(session)}
                className="w-full p-4 rounded-3xl bg-[#111] hover:bg-[#151515] border border-white/5 hover:border-emerald-500/25 transition-all text-left cursor-pointer group shadow-sm relative overflow-hidden"
              >
                {/* Top Line: Date · Time ─── Status */}
                <div className="flex items-center justify-between text-xs pb-1.5 border-b border-white/[0.04]">
                  <div className="flex items-center gap-1.5 text-slate-400 font-medium">
                    <span>{session.dateStr} · {session.timeStr}</span>
                    {vehicleScope === 'all' && (
                      <span className="text-[10px] bg-white/5 px-2 py-0.2 rounded-full text-slate-300 border border-white/5 font-normal ml-1">
                        {session.vehicleNameSnapshot}
                      </span>
                    )}
                  </div>

                  <div className="flex items-center gap-2">
                    {getStatusBadge(session)}
                    <button
                      type="button"
                      onClick={(e) => handleHide(e, session.id)}
                      className="opacity-0 group-hover:opacity-100 text-slate-500 hover:text-slate-300 p-1 transition-opacity"
                      title="Ẩn khỏi lịch sử"
                    >
                      <EyeOff className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {/* Middle Line: Start% → End% (and target if stopped early) */}
                <div className="py-2 flex items-baseline justify-between">
                  <div className="flex items-baseline gap-2">
                    <span className="text-xl font-black text-white font-mono-num">
                      {session.startPercent}% → {session.endPercent}%
                    </span>
                    {session.terminalState === 'cancelled' && (
                      <span className="text-[11px] text-slate-500 font-medium">
                        (Mục tiêu {session.targetPercent}%)
                      </span>
                    )}
                  </div>

                  <span className="text-xs font-bold text-slate-300">
                    {isAi ? 'Sạc AI' : 'Thủ công'}
                  </span>
                </div>

                {/* Bottom Line: Duration · Energy */}
                <div className="flex items-center justify-between text-xs text-slate-400 pt-0.5">
                  <span className="font-mono-num">
                    {formatHoursMinutes(session.durationMinutes)} · {energyStr}
                  </span>

                  <span className="text-emerald-400 opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5 text-[11px] font-semibold">
                    Chi tiết <ChevronRight className="w-3.5 h-3.5" />
                  </span>
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Load More Button (Section 4 & 47) */}
      {hasMore && (
        <div className="pt-2 text-center">
          <button
            type="button"
            onClick={handleLoadMore}
            className="px-6 py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-bold transition-colors border border-white/5"
          >
            Tải thêm
          </button>
        </div>
      )}
    </div>
  );
};
