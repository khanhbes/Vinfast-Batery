import React, { useState } from 'react';
import { 
  Wifi, BatteryMedium, Bell, ChevronDown, 
  LayoutGrid, Zap, History, MoreHorizontal,
  Smartphone, Monitor, ShieldCheck, CheckCircle2
} from 'lucide-react';
import { Vehicle } from '../types';

interface AndroidFrameProps {
  children: React.ReactNode;
  activeTab: 'overview' | 'charge' | 'history' | 'settings';
  onChangeTab: (tab: 'overview' | 'charge' | 'history' | 'settings') => void;
  activeVehicle: Vehicle;
  onOpenVehicleSelector: () => void;
  isCharging: boolean;
}

export const AndroidFrame: React.FC<AndroidFrameProps> = ({
  children,
  activeTab,
  onChangeTab,
  activeVehicle,
  onOpenVehicleSelector,
  isCharging,
}) => {
  const [deviceFrameMode, setDeviceFrameMode] = useState<boolean>(true);
  const [unreadNotifications, setUnreadNotifications] = useState(1);
  const [showNotificationToast, setShowNotificationToast] = useState(false);

  const handleNotificationClick = () => {
    setShowNotificationToast(true);
    setUnreadNotifications(0);
    setTimeout(() => setShowNotificationToast(false), 3500);
  };

  const navItems = [
    { id: 'overview', label: 'Tổng quan', icon: LayoutGrid },
    { id: 'charge', label: 'Sạc', icon: Zap, isPrimary: true },
    { id: 'history', label: 'Lịch sử', icon: History },
    { id: 'settings', label: 'Khác', icon: MoreHorizontal },
  ] as const;

  return (
    <div className="min-h-screen bg-[#050505] text-slate-200 flex flex-col items-center justify-start p-0 md:py-6 md:px-4 selection:bg-emerald-500 selection:text-black">
      {/* Top Device Viewport Switcher Toolbar */}
      <header className="w-full max-w-md hidden md:flex items-center justify-between px-4 py-2 mb-3 bg-[#111] border border-white/5 rounded-2xl shadow-xl backdrop-blur-md">
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></div>
          <span className="text-xs font-semibold uppercase tracking-wider text-emerald-400">Immersive EV Interface</span>
        </div>

        <div className="flex items-center gap-1 bg-[#050505] p-1 rounded-xl border border-white/5">
          <button
            type="button"
            onClick={() => setDeviceFrameMode(true)}
            className={`px-2.5 py-1 rounded-lg text-xs font-medium flex items-center gap-1.5 transition-colors ${
              deviceFrameMode
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Smartphone className="w-3.5 h-3.5" />
            Khung Android
          </button>
          <button
            type="button"
            onClick={() => setDeviceFrameMode(false)}
            className={`px-2.5 py-1 rounded-lg text-xs font-medium flex items-center gap-1.5 transition-colors ${
              !deviceFrameMode
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Monitor className="w-3.5 h-3.5" />
            Mở rộng
          </button>
        </div>
      </header>

      {/* Notification Toast Alert */}
      {showNotificationToast && (
        <div className="fixed top-4 z-50 animate-bounce bg-[#111] border border-emerald-500/40 text-white px-4 py-3 rounded-2xl shadow-2xl flex items-center gap-3 max-w-sm">
          <div className="w-8 h-8 rounded-xl bg-emerald-500/20 text-emerald-400 flex items-center justify-center shrink-0">
            <Zap className="w-4 h-4" />
          </div>
          <div className="text-xs">
            <strong className="text-emerald-400 block">Thông báo sạc xe</strong>
            {isCharging
              ? 'Xe đang sạc an toàn. Tự động ngắt khi đạt giới hạn.'
              : 'Trạng thái xe sẵn sàng. Đã đồng bộ dữ liệu pin qua 4G.'}
          </div>
        </div>
      )}

      {/* Main Android Phone Device Container */}
      <main
        className={`w-full transition-all duration-300 ${
          deviceFrameMode
            ? 'max-w-[430px] rounded-none sm:rounded-[48px] sm:border-[6px] sm:border-[#222] shadow-[0_0_80px_rgba(16,185,129,0.15)]'
            : 'max-w-2xl rounded-3xl border border-white/5 shadow-2xl'
        } bg-[#0c0c0c] flex flex-col relative overflow-hidden min-h-screen sm:min-h-[860px]`}
      >
        {/* 1. ANDROID STATUS BAR */}
        <div className="w-full bg-[#0c0c0c]/95 px-6 pt-3.5 pb-2 flex items-center justify-between text-xs font-semibold text-slate-300 select-none z-30 border-b border-white/5">
          <div className="flex items-center gap-2">
            <span className="font-mono-num font-bold text-white text-xs">14:30</span>
            {isCharging && (
              <span className="flex items-center gap-1 text-[10px] text-emerald-400 bg-emerald-500/15 border border-emerald-500/30 px-2 py-0.5 rounded-full font-mono">
                <Zap className="w-2.5 h-2.5 fill-current animate-pulse" /> Sạc
              </span>
            )}
          </div>

          {/* Camera Punch Hole center placeholder on modern Android */}
          <div className="w-3.5 h-3.5 rounded-full bg-[#050505] border border-white/10 mx-auto hidden sm:block"></div>

          <div className="flex items-center gap-2 text-slate-300 text-[11px]">
            <span className="font-mono text-[10px] text-slate-500">1.20 KB/s</span>
            <span className="text-[10px] font-bold text-slate-400 font-mono">VoLTE</span>
            <Wifi className="w-3.5 h-3.5 text-slate-300" />
            <div className="flex items-center gap-0.5 font-mono-num">
              <span className="text-white text-[11px] font-bold">58%</span>
              <BatteryMedium className="w-4 h-4 text-emerald-400" />
            </div>
          </div>
        </div>

        {/* 2. APP HEADER BAR (Vehicle dropdown & Notification Bell) */}
        <div className="w-full px-4 py-2.5 bg-[#0c0c0c] border-b border-white/5 flex items-center justify-between z-20">
          {/* Brand & Vehicle Selector Button */}
          <button
            type="button"
            onClick={onOpenVehicleSelector}
            className="flex items-center gap-2 py-1.5 px-3 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 text-left transition-all active:scale-95 shadow-sm"
          >
            <div className="w-6 h-6 rounded-lg bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center text-xs font-bold shadow-sm">
              <Zap className="w-3.5 h-3.5 fill-current" />
            </div>
            <div className="flex items-center gap-1">
              <span className="text-xs font-bold text-white tracking-tight">
                {activeVehicle.name}
              </span>
              <ChevronDown className="w-3.5 h-3.5 text-slate-400" />
            </div>
          </button>

          {/* Notification Bell */}
          <button
            type="button"
            onClick={handleNotificationClick}
            aria-label="Thông báo"
            className="relative w-9 h-9 rounded-2xl bg-white/5 hover:bg-white/10 border border-white/5 flex items-center justify-center text-slate-300 hover:text-white transition-colors"
          >
            <Bell className="w-4 h-4" />
            {unreadNotifications > 0 && (
              <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-emerald-400 ring-2 ring-[#0c0c0c] animate-ping"></span>
            )}
            {unreadNotifications > 0 && (
              <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-emerald-400 ring-2 ring-[#0c0c0c]"></span>
            )}
          </button>
        </div>

        {/* 3. MAIN CONTENT SCROLL AREA */}
        <div className="flex-1 overflow-y-auto px-4 py-3 scroll-smooth">
          {children}
        </div>

        {/* 4. ANDROID MATERIAL 3 BOTTOM NAVIGATION BAR */}
        <nav
          id="android-bottom-navigation"
          aria-label="Điều hướng chính"
          className="sticky bottom-0 w-full bg-[#0c0c0c]/95 backdrop-blur-xl border-t border-white/5 px-3 pt-2 pb-1 z-30"
        >
          <div className="flex items-center justify-around">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = activeTab === item.id;
              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => onChangeTab(item.id)}
                  className="flex flex-col items-center justify-center py-1 px-3 group transition-transform active:scale-95"
                >
                  {/* Active Indicator Pill */}
                  <div
                    className={`px-4 py-1 rounded-2xl flex items-center justify-center transition-all ${
                      isActive
                        ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 shadow-sm shadow-emerald-500/20'
                        : 'text-slate-400 group-hover:text-slate-200'
                    }`}
                  >
                    <Icon className={`w-5 h-5 ${isActive ? 'stroke-[2.4]' : 'stroke-[1.8]'}`} />
                  </div>

                  <span
                    className={`text-[11px] mt-1 font-medium tracking-tight ${
                      isActive ? 'text-emerald-400 font-bold' : 'text-slate-400'
                    }`}
                  >
                    {item.label}
                  </span>
                </button>
              );
            })}
          </div>

          {/* Android Home Gesture Indicator Bar */}
          <div className="w-32 h-1 bg-white/20 rounded-full mx-auto mt-2 mb-1"></div>
        </nav>
      </main>
    </div>
  );
};

