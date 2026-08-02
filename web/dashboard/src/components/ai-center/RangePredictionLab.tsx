import { useState } from 'react';
import { BatteryCharging, Gauge, Loader2, Route, ShieldCheck, Thermometer } from 'lucide-react';
import { Button } from '@/components/ui/button';
// @ts-ignore
import { aiPredictRange } from '@/api';

type Result = { estimatedRangeKm: number; rangeLowKm: number; rangeHighKm: number; confidence: number; adjustedEfficiencyKmPerPercent: number };

export default function RangePredictionLab() {
  const [battery, setBattery] = useState(70), [health, setHealth] = useState(95);
  const [temperature, setTemperature] = useState(30), [speed, setSpeed] = useState(35);
  const [payload, setPayload] = useState(75), [efficiency, setEfficiency] = useState(1.2);
  const [result, setResult] = useState<Result | null>(null), [loading, setLoading] = useState(false), [error, setError] = useState('');
  const predict = async () => {
    setLoading(true); setError('');
    try { const r = await aiPredictRange({ batteryPercent: battery, stateOfHealth: health, temperatureC: temperature, averageSpeedKmh: speed, payloadKg: payload, baseEfficiencyKmPerPercent: efficiency, reservePercent: 5 }); setResult(r.data ?? r); }
    catch (e: any) { setError(e?.message || 'Không thể chạy dự đoán'); }
    finally { setLoading(false); }
  };
  return <section className="overflow-hidden rounded-2xl border bg-slate-950 text-white shadow-sm">
    <div className="grid lg:grid-cols-[1.1fr_.9fr]">
      <div className="p-6 lg:p-8">
        <div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[.18em] text-emerald-400"><Route className="h-4 w-4" /> Range prediction · v1</div>
        <h2 className="mt-3 text-2xl font-semibold tracking-tight">Test quãng đường còn lại</h2>
        <p className="mt-1 text-sm text-slate-400">Hiệu chỉnh phạm vi theo sức khỏe pin, nhiệt độ, tốc độ và tải trọng.</p>
        <div className="mt-7 grid gap-x-6 gap-y-5 sm:grid-cols-2">
          <Slider label="Pin hiện tại" value={battery} min={0} max={100} unit="%" set={setBattery} icon={<BatteryCharging />} />
          <Slider label="Sức khỏe pin" value={health} min={50} max={100} unit="%" set={setHealth} icon={<ShieldCheck />} />
          <Slider label="Nhiệt độ" value={temperature} min={-10} max={50} unit="°C" set={setTemperature} icon={<Thermometer />} />
          <Slider label="Tốc độ trung bình" value={speed} min={10} max={100} unit=" km/h" set={setSpeed} icon={<Gauge />} />
          <Slider label="Tải trọng" value={payload} min={40} max={250} unit=" kg" set={setPayload} icon={<Route />} />
          <Slider label="Hiệu suất cơ sở" value={efficiency} min={0.4} max={3} step={0.1} unit=" km/%" set={setEfficiency} icon={<BatteryCharging />} />
        </div>
        <Button onClick={predict} disabled={loading} className="mt-7 bg-emerald-400 text-slate-950 hover:bg-emerald-300">{loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Route className="mr-2 h-4 w-4" />}Chạy dự đoán</Button>
        {error && <p className="mt-3 text-sm text-red-400">{error}</p>}
      </div>
      <div className="flex min-h-[340px] flex-col justify-center border-t border-white/10 bg-white/[.04] p-6 lg:border-l lg:border-t-0 lg:p-8">
        <div className="mx-auto w-full max-w-sm">
          <div className="h-3 overflow-hidden rounded-full bg-white/10"><div className="h-full rounded-full bg-emerald-400 transition-all duration-500" style={{ width: `${battery}%` }} /></div>
          <div className="mt-8 text-sm text-slate-400">Quãng đường dự kiến</div>
          <div className="mt-1 flex items-end gap-2"><span className="text-6xl font-semibold tracking-[-.06em]">{result?.estimatedRangeKm?.toFixed(1) ?? '—'}</span><span className="pb-2 text-lg text-slate-400">km</span></div>
          <div className="mt-6 space-y-3 border-t border-white/10 pt-5 text-sm">
            <Line label="Khoảng an toàn" value={result ? `${result.rangeLowKm}–${result.rangeHighKm} km` : 'Chưa có dữ liệu'} />
            <Line label="Độ tin cậy" value={result ? `${Math.round(result.confidence * 100)}%` : '—'} />
            <Line label="Hiệu suất đã chỉnh" value={result ? `${result.adjustedEfficiencyKmPerPercent} km/%` : '—'} />
          </div>
        </div>
      </div>
    </div>
  </section>;
}

function Slider({ label, value, min, max, step = 1, unit, set, icon }: any) { return <label><span className="flex justify-between text-sm"><span className="flex items-center gap-2 text-slate-300 [&_svg]:h-4 [&_svg]:w-4">{icon}{label}</span><b>{value}{unit}</b></span><input className="mt-3 w-full accent-emerald-400" type="range" value={value} min={min} max={max} step={step} onChange={e => set(Number(e.target.value))} /></label>; }
function Line({ label, value }: { label: string; value: string }) { return <div className="flex justify-between gap-4"><span className="text-slate-400">{label}</span><span>{value}</span></div>; }
