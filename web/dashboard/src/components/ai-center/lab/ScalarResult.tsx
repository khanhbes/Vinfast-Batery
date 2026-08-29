import { ModelTypeMeta, PredictionResponse, ModelAccent } from '../types';
import { formatDurationSeconds } from './modelLabUtils';

const ACCENT_BG_CLASS: Record<ModelAccent, string> = {
  emerald: 'bg-emerald-400',
  amber: 'bg-amber-400',
  violet: 'bg-violet-400',
  blue: 'bg-blue-400',
  rose: 'bg-rose-400',
  slate: 'bg-slate-400',
};

interface Props {
  meta: ModelTypeMeta;
  result: PredictionResponse | null;
  accent: ModelAccent;
  inputState: Record<string, any>;
}

export default function ScalarResult({ meta, result, accent, inputState }: Props) {
  const accentBg = ACCENT_BG_CLASS[accent] || ACCENT_BG_CLASS.emerald;

  // Determine progress bar value based on model type
  let progressPercent = 0;
  if (meta.key === 'dte' || meta.key === 'soc') {
    progressPercent = Math.min(100, Math.max(0, Number(inputState.batteryPercent ?? inputState.distance_km ?? 50)));
  } else if (meta.key === 'charging_time') {
    progressPercent = Math.min(100, Math.max(0, Number(inputState.end_soc ?? 80)));
  } else if (result?.confidence !== undefined) {
    progressPercent = Math.round(result.confidence * 100);
  } else if (typeof result?.prediction === 'number') {
    progressPercent = Math.min(100, Math.max(0, result.prediction));
  }

  // Format main primary result
  let mainDisplay = '—';
  let unitDisplay = meta.outputUnit || '';

  if (result) {
    if (meta.displayUnit === 'time') {
      const secs = result.predictionSeconds ?? (typeof result.prediction === 'number' ? result.prediction : 0);
      mainDisplay = result.formattedPrediction || formatDurationSeconds(secs);
      unitDisplay = '';
    } else if (meta.key === 'dte') {
      const val = result.estimatedRangeKm ?? (typeof result.prediction === 'number' ? result.prediction : null);
      mainDisplay = val !== null ? val.toFixed(1) : '—';
      unitDisplay = 'km';
    } else if (typeof result.prediction === 'number') {
      mainDisplay = result.prediction.toFixed(1);
    } else if (result.prediction !== undefined && result.prediction !== null) {
      mainDisplay = String(result.prediction);
    }
  }

  return (
    <div className="mx-auto w-full max-w-sm">
      {/* Progress bar */}
      <div className="h-3 overflow-hidden rounded-full bg-white/10">
        <div
          className={`h-full rounded-full ${accentBg} transition-all duration-500`}
          style={{ width: `${progressPercent}%` }}
        />
      </div>

      {/* Result title & big value */}
      <div className="mt-8 text-sm text-slate-400">
        {meta.outputDescription || 'Kết quả dự đoán'}
      </div>
      <div className="mt-1 flex items-end gap-2">
        <span className="text-5xl lg:text-6xl font-semibold tracking-[-.06em] text-white">
          {mainDisplay}
        </span>
        {unitDisplay && (
          <span className="pb-2 text-lg text-slate-400">{unitDisplay}</span>
        )}
      </div>

      {/* Secondary metrics */}
      <div className="mt-6 space-y-3 border-t border-white/10 pt-5 text-sm">
        {meta.key === 'dte' && (
          <>
            <Line
              label="Khoảng an toàn"
              value={result ? `${result.rangeLowKm ?? '—'}–${result.rangeHighKm ?? '—'} km` : 'Chưa có dữ liệu'}
            />
            <Line
              label="Độ tin cậy"
              value={result?.confidence ? `${Math.round(result.confidence * 100)}%` : '—'}
            />
            <Line
              label="Hiệu suất đã chỉnh"
              value={result?.adjustedEfficiencyKmPerPercent ? `${result.adjustedEfficiencyKmPerPercent} km/%` : '—'}
            />
          </>
        )}

        {meta.key === 'charging_time' && (
          <>
            <Line
              label="Mức tăng pin"
              value={
                inputState.start_soc !== undefined && inputState.end_soc !== undefined
                  ? `+${Math.max(0, Number(inputState.end_soc) - Number(inputState.start_soc))}%`
                  : '—'
              }
            />
            <Line
              label="Model version"
              value={result?.modelVersion || '—'}
            />
          </>
        )}

        {meta.key !== 'dte' && meta.key !== 'charging_time' && (
          <>
            {result?.confidence !== undefined && (
              <Line
                label="Độ tin cậy"
                value={`${Math.round(result.confidence * 100)}%`}
              />
            )}
            {meta.outputMeaning && (
              <Line label="Ý nghĩa" value={meta.outputMeaning} />
            )}
            <Line
              label="Phiên bản model"
              value={result?.modelVersion || '—'}
            />
          </>
        )}
      </div>
    </div>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-4">
      <span className="text-slate-400">{label}</span>
      <span className="font-medium text-slate-200 text-right">{value}</span>
    </div>
  );
}
