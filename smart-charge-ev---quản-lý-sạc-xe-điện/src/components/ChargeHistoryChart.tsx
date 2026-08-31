import React, { useState } from 'react';
import { motion } from 'motion/react';
import { Battery, Zap, Gauge, Flame, Sparkles } from 'lucide-react';
import { ChargingSession } from '../types';

interface ChargeHistoryChartProps {
  session: ChargingSession;
}

type MetricType = 'soc' | 'power' | 'energy' | 'temperature';

export const ChargeHistoryChart: React.FC<ChargeHistoryChartProps> = ({ session }) => {
  const [activeMetric, setActiveMetric] = useState<MetricType>('soc');
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);

  // Generate synthetic points if chartSummary is missing
  const getPoints = (): Array<{ minute: number; value: number }> => {
    if (session.chartSummary && session.chartSummary[activeMetric]?.length > 0) {
      return session.chartSummary[activeMetric];
    }

    // Dynamic generation based on session properties
    const totalMinutes = Math.max(1, session.durationMinutes || 60);
    const steps = 7;
    const pts: Array<{ minute: number; value: number }> = [];

    for (let i = 0; i <= steps; i++) {
      const fraction = i / steps;
      const minute = Math.round(fraction * totalMinutes);

      if (activeMetric === 'soc') {
        const delta = session.endPercent - session.startPercent;
        const val = Math.round(session.startPercent + delta * Math.pow(fraction, 0.9));
        pts.push({ minute, value: Math.min(100, Math.max(0, val)) });
      } else if (activeMetric === 'power') {
        const basePower = session.averagePowerW || 960;
        const val = i === steps ? 0 : Math.round(basePower * (fraction > 0.8 ? 0.6 : 1.0));
        pts.push({ minute, value: val });
      } else if (activeMetric === 'energy') {
        const totalWh = session.energyWh || 1200;
        const val = Math.round(totalWh * fraction);
        pts.push({ minute, value: val });
      } else {
        // Temperature
        const baseTemp = 29;
        const maxTemp = session.maxPlugTemperatureC || 37;
        const tempDelta = maxTemp - baseTemp;
        const val = Math.round(baseTemp + tempDelta * Math.sin(fraction * Math.PI));
        pts.push({ minute, value: val });
      }
    }
    return pts;
  };

  const points = getPoints();

  // Metric metadata
  const metricConfig = {
    soc: {
      label: 'Pin',
      unit: '%',
      icon: Battery,
      color: '#10b981', // emerald-500
      yMin: 0,
      yMax: 100,
      formatVal: (v: number) => `${v}%`,
      subtitle: session.isSocEstimated ? 'Pin ước tính' : 'Pin đo lường',
    },
    power: {
      label: 'Công suất',
      unit: 'W',
      icon: Zap,
      color: '#38bdf8', // sky-400
      yMin: 0,
      yMax: Math.max(1000, ...(points.map(p => p.value) || [1000])),
      formatVal: (v: number) => `${v} W`,
      subtitle: 'Công suất tải thực tế',
    },
    energy: {
      label: 'Năng lượng',
      unit: 'Wh',
      icon: Gauge,
      color: '#a855f7', // purple-500
      yMin: 0,
      yMax: Math.max(100, ...(points.map(p => p.value) || [1000])),
      formatVal: (v: number) => v >= 1000 ? `${(v / 1000).toFixed(2)} kWh` : `${v} Wh`,
      subtitle: 'Bắt đầu từ 0 Wh',
    },
    temperature: {
      label: 'Nhiệt độ',
      unit: '°C',
      icon: Flame,
      color: '#f97316', // orange-500
      yMin: 20,
      yMax: Math.max(50, ...(points.map(p => p.value) || [50])),
      formatVal: (v: number) => `${v}°C`,
      subtitle: 'Nhiệt độ ổ sạc',
    },
  };

  const currentCfg = metricConfig[activeMetric];

  // SVG dimensions
  const width = 340;
  const height = 140;
  const padLeft = 32;
  const padRight = 16;
  const padTop = 18;
  const padBottom = 24;
  const chartW = width - padLeft - padRight;
  const chartH = height - padTop - padBottom;

  const yRange = (currentCfg.yMax - currentCfg.yMin) || 1;
  const maxMin = Math.max(1, Math.max(...points.map(p => p.minute)));

  const getX = (minute: number) => padLeft + (minute / maxMin) * chartW;
  const getY = (value: number) => padTop + chartH - ((value - currentCfg.yMin) / yRange) * chartH;

  // Build SVG Path
  const pathD = points.reduce((acc, pt, idx) => {
    const x = getX(pt.minute);
    const y = getY(pt.value);
    if (idx === 0) return `M ${x} ${y}`;
    // Simple smooth curve
    const prev = points[idx - 1];
    const prevX = getX(prev.minute);
    const prevY = getY(prev.value);
    const cx1 = prevX + (x - prevX) / 2;
    const cy1 = prevY;
    const cx2 = prevX + (x - prevX) / 2;
    const cy2 = y;
    return `${acc} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${x} ${y}`;
  }, '');

  const areaD = points.length > 0
    ? `${pathD} L ${getX(points[points.length - 1].minute)} ${padTop + chartH} L ${getX(points[0].minute)} ${padTop + chartH} Z`
    : '';

  const activePoint = hoveredIndex !== null && points[hoveredIndex] ? points[hoveredIndex] : points[points.length - 1];

  return (
    <div className="rounded-3xl bg-[#0c0c0c] border border-white/5 p-4 space-y-3.5 shadow-inner">
      {/* Header with Metric Selector Tabs */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1 bg-white/5 p-0.5 rounded-2xl border border-white/5">
          {(['soc', 'power', 'energy', 'temperature'] as MetricType[]).map((m) => {
            const cfg = metricConfig[m];
            const Icon = cfg.icon;
            const isSelected = activeMetric === m;
            return (
              <button
                key={m}
                type="button"
                onClick={() => {
                  setActiveMetric(m);
                  setHoveredIndex(null);
                }}
                className={`px-2.5 py-1 rounded-xl text-xs font-semibold flex items-center gap-1 transition-all ${
                  isSelected
                    ? 'bg-white/15 text-white shadow-sm font-bold scale-[1.02]'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                <Icon className="w-3 h-3" style={{ color: isSelected ? cfg.color : undefined }} />
                <span>{cfg.label}</span>
              </button>
            );
          })}
        </div>

        {/* Live point display */}
        {activePoint && (
          <div className="text-right">
            <span className="text-sm font-bold font-mono-num text-white">
              {currentCfg.formatVal(activePoint.value)}
            </span>
            <span className="text-[10px] text-slate-400 block font-mono">
              Phút {activePoint.minute}
            </span>
          </div>
        )}
      </div>

      {/* Responsive SVG Chart Viewport */}
      <div className="relative w-full overflow-hidden flex items-center justify-center">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-36 select-none overflow-visible"
        >
          <defs>
            <linearGradient id={`grad-${activeMetric}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={currentCfg.color} stopOpacity="0.35" />
              <stop offset="100%" stopColor={currentCfg.color} stopOpacity="0.0" />
            </linearGradient>
          </defs>

          {/* Grid lines */}
          <line
            x1={padLeft}
            y1={padTop}
            x2={width - padRight}
            y2={padTop}
            stroke="rgba(255,255,255,0.06)"
            strokeDasharray="3 3"
          />
          <line
            x1={padLeft}
            y1={padTop + chartH / 2}
            x2={width - padRight}
            y2={padTop + chartH / 2}
            stroke="rgba(255,255,255,0.06)"
            strokeDasharray="3 3"
          />
          <line
            x1={padLeft}
            y1={padTop + chartH}
            x2={width - padRight}
            y2={padTop + chartH}
            stroke="rgba(255,255,255,0.1)"
          />

          {/* Y-axis Labels */}
          <text
            x={padLeft - 6}
            y={padTop + 4}
            fill="#64748b"
            fontSize="9"
            fontFamily="monospace"
            textAnchor="end"
          >
            {Math.round(currentCfg.yMax)}
          </text>
          <text
            x={padLeft - 6}
            y={padTop + chartH + 3}
            fill="#64748b"
            fontSize="9"
            fontFamily="monospace"
            textAnchor="end"
          >
            {Math.round(currentCfg.yMin)}
          </text>

          {/* Area Fill */}
          <path d={areaD} fill={`url(#grad-${activeMetric})`} />

          {/* Line Stroke */}
          <path
            d={pathD}
            fill="none"
            stroke={currentCfg.color}
            strokeWidth="2.2"
            strokeLinecap="round"
          />

          {/* Interactive Data Dots */}
          {points.map((pt, idx) => {
            const cx = getX(pt.minute);
            const cy = getY(pt.value);
            const isHovered = hoveredIndex === idx;

            return (
              <g
                key={idx}
                className="cursor-pointer"
                onMouseEnter={() => setHoveredIndex(idx)}
                onClick={() => setHoveredIndex(idx)}
              >
                {/* Larger transparent touch area */}
                <circle cx={cx} cy={cy} r="14" fill="transparent" />

                {/* Visible dot */}
                <circle
                  cx={cx}
                  cy={cy}
                  r={isHovered ? 4.5 : 2.5}
                  fill={isHovered ? '#ffffff' : currentCfg.color}
                  stroke="#0c0c0c"
                  strokeWidth="1.5"
                  className="transition-all duration-150"
                />

                {/* X-axis time label for first and last point */}
                {(idx === 0 || idx === points.length - 1) && (
                  <text
                    x={cx}
                    y={padTop + chartH + 15}
                    fill="#64748b"
                    fontSize="9"
                    fontFamily="monospace"
                    textAnchor={idx === 0 ? 'start' : 'end'}
                  >
                    {pt.minute}m
                  </text>
                )}
              </g>
            );
          })}
        </svg>
      </div>

      <div className="flex items-center justify-between text-[10px] text-slate-500 pt-1 border-t border-white/5">
        <span>{currentCfg.subtitle}</span>
        <span className="font-mono">{points.length} điểm dữ liệu telemetry</span>
      </div>
    </div>
  );
};
