import { ModelTypeMeta, PredictionResponse, ModelAccent } from '../types';
import PredictionResultChart from '../PredictionResultChart';

interface Props {
  meta: ModelTypeMeta;
  result: PredictionResponse | null;
  accent: ModelAccent;
  inputState: Record<string, any>;
}

export default function VectorResult({ meta, result, accent }: Props) {
  // Build chart data fallback if result.chartData is not directly available
  const chartData = result?.chartData || (result?.prediction && Array.isArray(result.prediction) ? {
    type: 'vector' as const,
    unit: meta.outputUnit || '',
    data: (result.prediction as number[]).map((val, idx) => ({
      name: `T+${idx + 1}`,
      value: val,
    })),
  } : null);

  return (
    <div className="mx-auto w-full max-w-sm space-y-4">
      <div className="text-sm text-slate-400">
        {meta.outputDescription || 'Prediction chart'}
      </div>

      {chartData && chartData.data.length > 0 ? (
        <div className="rounded-xl border border-white/10 bg-slate-900/80 p-3">
          <PredictionResultChart
            chartData={chartData}
            height={190}
            accent={accent}
          />
        </div>
      ) : (
        <div className="flex h-44 items-center justify-center rounded-xl border border-dashed border-white/10 bg-white/[0.02] text-sm text-slate-400">
          No time-series data
        </div>
      )}

      {result?.modelVersion && (
        <div className="flex justify-between text-xs text-slate-400 border-t border-white/10 pt-3">
          <span>Model version</span>
          <span className="font-mono text-slate-200">{result.modelVersion}</span>
        </div>
      )}
    </div>
  );
}
