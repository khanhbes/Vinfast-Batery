import { useState } from 'react';
import {
  Timer, BatteryCharging, Thermometer, Zap, TrendingUp,
  Loader2, AlertCircle, CheckCircle2, Clock, Battery, Info,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
// @ts-ignore
import { aiPredictChargingTime } from '@/api';

interface ChargingResult {
  estimatedMinutes: number;
  estimatedHours: number;
  formattedTime: string;
  chargeRatePercentPerHour: number;
  chargeGainPercent: number;
  energyNeededWh: number;
  chargePowerW: number;
  recommendations: string[];
  confidence: number;
  modelSource: string;
  chargingCurve: { soc: number; minutesElapsed: number; powerW: number }[];
  factors: {
    sohFactor: number;
    tempFactor: number;
    chargerType: string;
    effectivePowerW: number;
  };
}

export default function ChargingTimeEstimator() {
  const [currentBattery, setCurrentBattery] = useState(20);
  const [targetBattery, setTargetBattery] = useState(80);
  const [batteryHealth, setBatteryHealth] = useState(95);
  const [temperature, setTemperature] = useState(30);
  const [chargerType, setChargerType] = useState('standard');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<ChargingResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const chargerOptions = [
    { value: 'slow', label: 'Sạc chậm', icon: '🔌', desc: '~150W' },
    { value: 'standard', label: 'Sạc chuẩn', icon: '⚡', desc: '~600W' },
    { value: 'fast', label: 'Sạc nhanh', icon: '🚀', desc: '~1200W' },
  ];

  const predict = async () => {
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const res = await aiPredictChargingTime({
        currentBattery,
        targetBattery,
        batteryHealth,
        temperature,
        chargerType,
        batteryCapacityWh: 2400,
      });
      setResult(res?.data ?? null);
    } catch (e: any) {
      setError(e?.message || 'Dự đoán thất bại');
    } finally {
      setLoading(false);
    }
  };

  // Battery visual bar
  const BatteryBar = ({ from, to }: { from: number; to: number }) => (
    <div className="relative h-10 bg-muted/30 rounded-xl overflow-hidden border border-border/50">
      {/* Current level */}
      <div
        className="absolute top-0 left-0 h-full bg-amber-500/30 transition-all"
        style={{ width: `${from}%` }}
      />
      {/* Target fill */}
      <div
        className="absolute top-0 h-full bg-emerald-500/50 transition-all"
        style={{ left: `${from}%`, width: `${Math.max(0, to - from)}%` }}
      />
      {/* Labels */}
      <div className="absolute inset-0 flex items-center justify-between px-3 text-xs font-bold">
        <span className="text-amber-300">{from}%</span>
        <span className="text-emerald-300 flex items-center gap-1">
          <TrendingUp className="w-3 h-3" />
          {to}%
        </span>
      </div>
    </div>
  );

  return (
    <Card className="border-blue-500/20 bg-gradient-to-br from-blue-950/30 to-surface/50 backdrop-blur-sm">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-lg">
          <div className="p-2 rounded-lg bg-blue-500/10">
            <Timer className="w-5 h-5 text-blue-400" />
          </div>
          Dự đoán thời gian sạc pin
          <Badge variant="secondary" className="text-[10px] font-mono ml-auto">
            AI Charge Time ETA
          </Badge>
        </CardTitle>
        <CardDescription>
          AI dự đoán thời gian sạc dựa trên mô phỏng đường cong CC-CV, SoH và điều kiện môi trường
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* ── Input Section ── */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {/* Left: Battery Range */}
          <div className="space-y-4">
            <div className="text-sm font-semibold text-foreground flex items-center gap-2">
              <BatteryCharging className="w-4 h-4 text-blue-400" />
              Mức pin
            </div>

            <BatteryBar from={currentBattery} to={targetBattery} />

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Pin hiện tại (%)</label>
                <input
                  type="range"
                  min={0}
                  max={99}
                  value={currentBattery}
                  onChange={(e) => {
                    const v = Number(e.target.value);
                    setCurrentBattery(v);
                    if (v >= targetBattery) setTargetBattery(Math.min(100, v + 10));
                  }}
                  className="w-full accent-amber-500"
                />
                <div className="text-center text-lg font-bold text-amber-400">{currentBattery}%</div>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Pin mong muốn (%)</label>
                <input
                  type="range"
                  min={currentBattery + 1}
                  max={100}
                  value={targetBattery}
                  onChange={(e) => setTargetBattery(Number(e.target.value))}
                  className="w-full accent-emerald-500"
                />
                <div className="text-center text-lg font-bold text-emerald-400">{targetBattery}%</div>
              </div>
            </div>

            {/* Quick presets */}
            <div className="flex gap-2 flex-wrap">
              {[
                { from: 10, to: 80, label: '10→80%' },
                { from: 20, to: 80, label: '20→80%' },
                { from: 0, to: 100, label: '0→100%' },
                { from: 30, to: 90, label: '30→90%' },
              ].map((p) => (
                <button
                  key={p.label}
                  onClick={() => { setCurrentBattery(p.from); setTargetBattery(p.to); }}
                  className="px-2.5 py-1 rounded-full text-[11px] font-medium border border-border/50 
                    hover:border-blue-400/50 hover:bg-blue-400/10 text-muted-foreground 
                    hover:text-blue-400 transition-all"
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          {/* Right: Conditions */}
          <div className="space-y-4">
            <div className="text-sm font-semibold text-foreground flex items-center gap-2">
              <Zap className="w-4 h-4 text-yellow-400" />
              Điều kiện sạc
            </div>

            {/* Charger Type */}
            <div>
              <label className="text-xs text-muted-foreground mb-2 block">Loại sạc</label>
              <div className="grid grid-cols-3 gap-2">
                {chargerOptions.map((opt) => (
                  <button
                    key={opt.value}
                    onClick={() => setChargerType(opt.value)}
                    className={`p-2.5 rounded-xl border text-center transition-all ${
                      chargerType === opt.value
                        ? 'border-blue-500 bg-blue-500/10 ring-1 ring-blue-500/30'
                        : 'border-border/50 hover:border-blue-400/30 hover:bg-blue-400/5'
                    }`}
                  >
                    <div className="text-lg">{opt.icon}</div>
                    <div className={`text-xs font-medium ${chargerType === opt.value ? 'text-blue-400' : 'text-muted-foreground'}`}>
                      {opt.label}
                    </div>
                    <div className="text-[10px] text-muted-foreground/70">{opt.desc}</div>
                  </button>
                ))}
              </div>
            </div>

            {/* Temperature */}
            <div>
              <label className="text-xs text-muted-foreground mb-1 flex items-center gap-1">
                <Thermometer className="w-3 h-3" /> Nhiệt độ ({temperature}°C)
              </label>
              <input
                type="range"
                min={0}
                max={45}
                value={temperature}
                onChange={(e) => setTemperature(Number(e.target.value))}
                className="w-full accent-orange-500"
              />
              <div className="flex justify-between text-[10px] text-muted-foreground">
                <span>0°C</span>
                <span className={temperature >= 20 && temperature <= 35 ? 'text-emerald-400' : 'text-amber-400'}>
                  {temperature < 10 ? '❄️ Lạnh' : temperature <= 35 ? '✅ Tốt' : '🔥 Nóng'}
                </span>
                <span>45°C</span>
              </div>
            </div>

            {/* Battery Health */}
            <div>
              <label className="text-xs text-muted-foreground mb-1 flex items-center gap-1">
                <Battery className="w-3 h-3" /> Sức khỏe pin — SoH ({batteryHealth}%)
              </label>
              <input
                type="range"
                min={50}
                max={100}
                value={batteryHealth}
                onChange={(e) => setBatteryHealth(Number(e.target.value))}
                className="w-full accent-emerald-500"
              />
            </div>
          </div>
        </div>

        {/* ── Predict Button ── */}
        <Button
          onClick={predict}
          disabled={loading || currentBattery >= targetBattery}
          className="w-full h-12 text-base font-semibold bg-blue-600 hover:bg-blue-700 gap-2"
        >
          {loading ? (
            <Loader2 className="w-5 h-5 animate-spin" />
          ) : (
            <Timer className="w-5 h-5" />
          )}
          {loading ? 'Đang tính toán...' : 'Dự đoán thời gian sạc'}
        </Button>

        {/* ── Error ── */}
        {error && (
          <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 flex items-start gap-2 text-sm">
            <AlertCircle className="w-4 h-4 text-red-400 mt-0.5 shrink-0" />
            <span className="text-red-300">{error}</span>
          </div>
        )}

        {/* ── Result ── */}
        {result && (
          <div className="space-y-4 animate-in fade-in slide-in-from-bottom-4 duration-500">
            {/* Hero result */}
            <div className="rounded-2xl bg-gradient-to-r from-blue-600/20 via-blue-500/10 to-emerald-500/10 
              border border-blue-500/30 p-6 text-center">
              <div className="text-sm text-blue-300/80 mb-1 flex items-center justify-center gap-1">
                <Clock className="w-4 h-4" />
                Thời gian sạc dự kiến
              </div>
              <div className="text-4xl font-black text-white tracking-tight">
                {result.formattedTime}
              </div>
              <div className="text-sm text-muted-foreground mt-2">
                {result.chargeGainPercent}% pin · {result.chargeRatePercentPerHour}%/giờ · {result.chargePowerW}W
              </div>
              <div className="flex items-center justify-center gap-2 mt-2">
                <Badge variant="outline" className="text-[10px]">
                  {result.modelSource}
                </Badge>
                <Badge variant="outline" className="text-[10px]">
                  Độ tin cậy: {result.confidence}%
                </Badge>
              </div>
            </div>

            {/* Stats grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <StatBox icon={<Clock className="w-4 h-4" />} label="Thời gian" value={result.formattedTime} accent="blue" />
              <StatBox icon={<Zap className="w-4 h-4" />} label="Công suất" value={`${result.chargePowerW}W`} accent="yellow" />
              <StatBox icon={<TrendingUp className="w-4 h-4" />} label="Tốc độ sạc" value={`${result.chargeRatePercentPerHour}%/h`} accent="emerald" />
              <StatBox icon={<Battery className="w-4 h-4" />} label="Năng lượng" value={`${result.energyNeededWh} Wh`} accent="purple" />
            </div>

            {/* Charging Curve */}
            {result.chargingCurve.length > 0 && (
              <div className="rounded-xl border border-border/50 p-4 bg-card/50">
                <div className="text-sm font-semibold mb-3 flex items-center gap-2 text-foreground">
                  <TrendingUp className="w-4 h-4 text-blue-400" />
                  Đường cong sạc (CC-CV)
                </div>
                <div className="space-y-1.5">
                  {result.chargingCurve.map((point, i) => {
                    const maxMin = result.chargingCurve[result.chargingCurve.length - 1]?.minutesElapsed || 1;
                    const width = (point.minutesElapsed / maxMin) * 100;
                    return (
                      <div key={i} className="flex items-center gap-2 text-xs">
                        <span className="w-10 text-right font-mono text-muted-foreground">{point.soc}%</span>
                        <div className="flex-1 h-4 bg-muted/20 rounded-full overflow-hidden relative">
                          <div
                            className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-500 transition-all"
                            style={{ width: `${width}%` }}
                          />
                        </div>
                        <span className="w-16 text-right font-mono text-muted-foreground">
                          {point.minutesElapsed >= 60
                            ? `${Math.floor(point.minutesElapsed / 60)}h${Math.round(point.minutesElapsed % 60)}m`
                            : `${Math.round(point.minutesElapsed)}m`}
                        </span>
                        <span className="w-12 text-right font-mono text-blue-400/70">{point.powerW}W</span>
                      </div>
                    );
                  })}
                </div>
                <div className="mt-2 flex justify-between text-[10px] text-muted-foreground px-12">
                  <span>⚡ CC (dòng không đổi)</span>
                  <span>📉 CV (áp không đổi, dòng giảm dần)</span>
                </div>
              </div>
            )}

            {/* Recommendations */}
            {result.recommendations.length > 0 && (
              <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 p-4">
                <div className="text-sm font-semibold mb-2 flex items-center gap-2 text-blue-400">
                  <Info className="w-4 h-4" />
                  Khuyến nghị
                </div>
                <ul className="space-y-1.5">
                  {result.recommendations.map((rec, i) => (
                    <li key={i} className="flex items-start gap-2 text-sm text-muted-foreground">
                      <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 shrink-0 text-blue-400/60" />
                      {rec}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ── Stat box helper ──
function StatBox({ icon, label, value, accent }: {
  icon: React.ReactNode; label: string; value: string; accent: string;
}) {
  const colors: Record<string, string> = {
    blue: 'text-blue-400 bg-blue-500/10',
    yellow: 'text-yellow-400 bg-yellow-500/10',
    emerald: 'text-emerald-400 bg-emerald-500/10',
    purple: 'text-purple-400 bg-purple-500/10',
  };
  const c = colors[accent] || colors.blue;
  return (
    <div className="rounded-xl border border-border/50 bg-card/50 p-3">
      <div className={`inline-flex items-center justify-center w-7 h-7 rounded-lg mb-1.5 ${c}`}>
        {icon}
      </div>
      <div className="text-[10px] text-muted-foreground uppercase tracking-wider">{label}</div>
      <div className="text-sm font-bold text-foreground mt-0.5">{value}</div>
    </div>
  );
}
