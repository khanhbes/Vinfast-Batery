import React, { useRef, useState } from 'react';
import { motion } from 'motion/react';
import { ShieldCheck, Zap, Minus, Plus, Battery } from 'lucide-react';

interface BatteryVisualizerProps {
  currentPercent: number;
  targetPercent: number;
  isCharging: boolean;
  onTargetChange: (value: number) => void;
  onCurrentChange?: (value: number) => void;
  batteryCapacityKWh: number;
}

export const BatteryVisualizer: React.FC<BatteryVisualizerProps> = ({
  currentPercent,
  targetPercent,
  isCharging,
  onTargetChange,
  onCurrentChange,
  batteryCapacityKWh,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);

  const presets = [
    { value: 80, label: '80%', tag: 'Tối ưu LFP', recommended: true },
    { value: 90, label: '90%', tag: 'Tiêu chuẩn', recommended: false },
    { value: 100, label: '100%', tag: 'Tối đa', recommended: false },
  ];

  const handlePointerInteraction = (clientX: number) => {
    if (!containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const width = rect.width;
    const offsetX = Math.max(0, Math.min(width, clientX - rect.left));
    const percentage = Math.round((offsetX / width) * 100);
    const clamped = Math.max(Math.min(currentPercent, 95), Math.max(5, Math.min(100, percentage)));
    onTargetChange(clamped);
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    setIsDragging(true);
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    handlePointerInteraction(e.clientX);
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isDragging) return;
    handlePointerInteraction(e.clientX);
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    setIsDragging(false);
    try {
      (e.target as HTMLElement).releasePointerCapture(e.pointerId);
    } catch {
      // ignore
    }
  };

  const incrementTarget = () => onTargetChange(Math.min(100, targetPercent + 1));
  const decrementTarget = () => onTargetChange(Math.max(currentPercent, Math.max(5, targetPercent - 1)));

  const incrementCurrent = () => {
    if (onCurrentChange) {
      onCurrentChange(Math.min(100, currentPercent + 1));
    }
  };

  const decrementCurrent = () => {
    if (onCurrentChange) {
      onCurrentChange(Math.max(1, currentPercent - 1));
    }
  };

  // Calculate energy in target
  const targetEnergyKWh = ((targetPercent / 100) * batteryCapacityKWh).toFixed(2);
  const deltaPercent = Math.max(0, targetPercent - currentPercent);

  // Circular gauge calculations
  const radius = 45;
  const circumference = 2 * Math.PI * radius;
  const strokeOffset = circumference - (currentPercent / 100) * circumference;

  return (
    <div id="battery-visualizer-card" className="w-full bg-[#111] border border-white/5 rounded-3xl p-5 shadow-2xl backdrop-blur-xl relative overflow-hidden">
      {/* Subtle background ambient blur glow */}
      <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/10 blur-3xl -mr-16 -mt-16 pointer-events-none"></div>

      {/* 1. Mức pin hiện tại của xe - Thanh trượt & Ô nhập trực tiếp bất kỳ % nào */}
      {!isCharging && onCurrentChange && (
        <div className="mb-4 p-3 rounded-2xl bg-white/[0.03] border border-white/5 space-y-2.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5 text-xs text-slate-300 font-semibold">
              <Battery className="w-4 h-4 text-emerald-400" />
              <span>Mức pin hiện tại</span>
            </div>
            <div className="flex items-center gap-1 bg-black/50 px-2 py-0.5 rounded-xl border border-white/10">
              <input
                type="number"
                min={1}
                max={100}
                value={currentPercent}
                onChange={(e) => {
                  const val = parseInt(e.target.value, 10);
                  if (!isNaN(val)) {
                    onCurrentChange(Math.max(1, Math.min(100, val)));
                  }
                }}
                className="w-8 bg-transparent text-right font-mono font-bold text-xs text-emerald-400 focus:outline-none"
              />
              <span className="text-xs font-mono font-semibold text-slate-400">%</span>
            </div>
          </div>

          {/* Smooth Continuous Slider from 1% to 100% */}
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={decrementCurrent}
              disabled={currentPercent <= 1}
              aria-label="Giảm 1%"
              className="w-7 h-7 rounded-lg bg-white/5 text-slate-400 hover:text-white flex items-center justify-center hover:bg-white/10 disabled:opacity-20 transition-colors"
            >
              <Minus className="w-3.5 h-3.5" />
            </button>

            <div className="flex-1 relative flex items-center">
              <input
                type="range"
                min={1}
                max={100}
                step={1}
                value={currentPercent}
                onChange={(e) => onCurrentChange(Number(e.target.value))}
                className="w-full h-2 bg-white/10 rounded-lg appearance-none cursor-pointer accent-emerald-400 focus:outline-none"
              />
            </div>

            <button
              type="button"
              onClick={incrementCurrent}
              disabled={currentPercent >= 100}
              aria-label="Tăng 1%"
              className="w-7 h-7 rounded-lg bg-white/5 text-slate-400 hover:text-white flex items-center justify-center hover:bg-white/10 disabled:opacity-20 transition-colors"
            >
              <Plus className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      )}

      {/* Header Info */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold uppercase tracking-widest text-emerald-500">Mục tiêu sạc</span>
            {targetPercent <= 80 && (
              <span className="inline-flex items-center gap-1 text-[11px] font-medium bg-emerald-500/15 text-emerald-400 px-2.5 py-0.5 rounded-full border border-emerald-500/30">
                <ShieldCheck className="w-3 h-3" />
                Chuẩn LFP
              </span>
            )}
          </div>
        </div>

        <div className="text-right">
          <div className="flex items-baseline justify-end gap-0.5">
            <span className="text-3xl font-bold font-mono-num text-emerald-400 tracking-tight">{targetPercent}</span>
            <span className="text-base font-semibold text-emerald-400/70">%</span>
          </div>
        </div>
      </div>

      {/* Circular Dial Radial Gauge */}
      <div className="flex flex-col items-center justify-center my-3 relative">
        <div className="relative w-40 h-40">
          <svg className="w-full h-full -rotate-90" viewBox="0 0 100 100">
            {/* Background Track */}
            <circle
              cx="50"
              cy="50"
              r={radius}
              fill="none"
              stroke="#1a1a1a"
              strokeWidth="5"
            />
            {/* Target Level Track */}
            <circle
              cx="50"
              cy="50"
              r={radius}
              fill="none"
              stroke="rgba(16, 185, 129, 0.2)"
              strokeWidth="5"
              strokeDasharray={`${(targetPercent / 100) * circumference} ${circumference}`}
              strokeLinecap="round"
            />
            {/* Current Level Solid Arc */}
            <circle
              cx="50"
              cy="50"
              r={radius}
              fill="none"
              stroke="#10b981"
              strokeWidth="5.5"
              strokeDasharray={circumference}
              strokeDashoffset={strokeOffset}
              strokeLinecap="round"
              className="transition-all duration-300 drop-shadow-[0_0_8px_rgba(16,185,129,0.6)]"
            />
          </svg>

          {/* Center Info Inside Ring */}
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span className="text-4xl font-extrabold tracking-tight text-white font-mono-num">
              {currentPercent}%
            </span>
            {isCharging && (
              <span className="text-[10px] uppercase tracking-widest text-slate-400 mt-0.5 font-medium flex items-center gap-1">
                <Zap className="w-2.5 h-2.5 text-emerald-400 fill-current animate-pulse" />
                Đang sạc
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Main Interactive Battery Slider Track */}
      <div className="relative py-1 select-none">
        <div className="flex items-center">
          {/* Battery Track */}
          <div
            ref={containerRef}
            id="interactive-battery-track"
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            onPointerCancel={handlePointerUp}
            className={`relative flex-1 h-12 bg-[#050505] rounded-2xl p-1 border ${
              isCharging ? 'border-emerald-500/50 shadow-[0_0_20px_rgba(16,185,129,0.25)]' : 'border-white/10'
            } cursor-pointer touch-none transition-all overflow-hidden`}
          >
            {/* Grid ticks inside battery */}
            <div className="absolute inset-0 flex justify-between px-4 py-2 pointer-events-none opacity-20 z-0">
              <div className="w-[1px] h-full bg-slate-500"></div>
              <div className="w-[1px] h-full bg-slate-500"></div>
              <div className="w-[1px] h-full bg-slate-500"></div>
              <div className="w-[1px] h-full bg-emerald-400"></div>
              <div className="w-[1px] h-full bg-slate-500"></div>
            </div>

            {/* Current Level Fill */}
            <div
              className="absolute top-1 bottom-1 left-1 rounded-xl bg-gradient-to-r from-emerald-600 via-emerald-500 to-emerald-400 z-10 transition-all duration-300 shadow-md"
              style={{ width: `calc(${Math.min(100, currentPercent)}% - 8px)` }}
            >
              {isCharging && (
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/30 to-transparent animate-energy-gradient rounded-xl" />
              )}
            </div>

            {/* Target Level Fill */}
            {targetPercent > currentPercent && (
              <div
                className="absolute top-1 bottom-1 left-1 rounded-xl bg-emerald-400/20 border-r border-dashed border-emerald-400/80 z-0 transition-all duration-150"
                style={{ width: `calc(${targetPercent}% - 8px)` }}
              />
            )}

            {/* 80% boundary indicator line */}
            <div
              className="absolute top-0 bottom-0 z-20 pointer-events-none flex flex-col items-center justify-between py-0.5"
              style={{ left: '80%' }}
            >
              <div className="w-0.5 h-1.5 bg-emerald-400/80 rounded-full"></div>
              <span className="text-[9px] font-bold text-emerald-400/90 font-mono">80%</span>
              <div className="w-0.5 h-1.5 bg-emerald-400/80 rounded-full"></div>
            </div>

            {/* Draggable Target Thumb */}
            <div
              className="absolute top-1/2 -translate-y-1/2 z-30 pointer-events-none -ml-2.5 transition-transform active:scale-110"
              style={{ left: `${targetPercent}%` }}
            >
              <div className="w-5 h-9 bg-white rounded-lg shadow-lg border-2 border-emerald-500 flex items-center justify-center">
                <div className="flex flex-col gap-0.5">
                  <div className="w-1.5 h-0.5 bg-slate-800 rounded-full"></div>
                  <div className="w-1.5 h-0.5 bg-slate-800 rounded-full"></div>
                  <div className="w-1.5 h-0.5 bg-slate-800 rounded-full"></div>
                </div>
              </div>
            </div>
          </div>

          {/* Battery Cathode */}
          <div className="w-2 h-6 bg-white/10 rounded-r-md border-y border-r border-white/10 ml-0.5"></div>
        </div>

        {/* Fine-tuning Stepper */}
        <div className="flex items-center justify-end mt-2.5 px-1">
          <div className="flex items-center gap-1 bg-white/5 p-0.5 rounded-xl border border-white/5">
            <button
              type="button"
              onClick={decrementTarget}
              disabled={targetPercent <= currentPercent}
              aria-label="Giảm 1%"
              className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 active:bg-white/20 disabled:opacity-30 disabled:pointer-events-none transition-colors"
            >
              <Minus className="w-3.5 h-3.5" />
            </button>
            <span className="text-xs font-mono-num font-semibold text-white px-2 min-w-8 text-center">
              {targetPercent}%
            </span>
            <button
              type="button"
              onClick={incrementTarget}
              disabled={targetPercent >= 100}
              aria-label="Tăng 1%"
              className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 active:bg-white/20 disabled:opacity-30 disabled:pointer-events-none transition-colors"
            >
              <Plus className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      </div>

      {/* Preset Target Buttons */}
      <div className="grid grid-cols-3 gap-2 mt-3 pt-3 border-t border-white/5">
        {presets.map((preset) => {
          const isActive = targetPercent === preset.value;
          return (
            <button
              key={preset.value}
              type="button"
              onClick={() => onTargetChange(preset.value)}
              className={`relative flex flex-col items-center justify-center py-2 px-2 rounded-2xl text-center border transition-all ${
                isActive
                  ? 'bg-emerald-500/20 border-emerald-500 text-white shadow-sm shadow-emerald-500/20'
                  : 'bg-white/5 border-white/5 text-slate-400 hover:border-white/20 hover:text-slate-200'
              }`}
            >
              <div className="flex items-center gap-1">
                <span className={`text-sm font-bold font-mono-num ${isActive ? 'text-emerald-400' : 'text-slate-200'}`}>
                  {preset.label}
                </span>
                {preset.recommended && (
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                )}
              </div>
              <span className="text-[10px] text-slate-400 mt-0.5 line-clamp-1">
                {preset.tag}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
};

