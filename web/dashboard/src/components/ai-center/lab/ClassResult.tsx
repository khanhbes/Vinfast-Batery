import { ModelTypeMeta, PredictionResponse, ModelAccent } from '../types';
import { Sparkles, CheckCircle2 } from 'lucide-react';

const ACCENT_TEXT_CLASS: Record<ModelAccent, string> = {
  emerald: 'text-emerald-400',
  amber: 'text-amber-400',
  violet: 'text-violet-400',
  blue: 'text-blue-400',
  rose: 'text-rose-400',
  slate: 'text-slate-400',
};

const ACCENT_BG_CLASS: Record<ModelAccent, string> = {
  emerald: 'bg-emerald-500/10 border-emerald-500/30',
  amber: 'bg-amber-500/10 border-amber-500/30',
  violet: 'bg-violet-500/10 border-violet-500/30',
  blue: 'bg-blue-500/10 border-blue-500/30',
  rose: 'bg-rose-500/10 border-rose-500/30',
  slate: 'bg-slate-500/10 border-slate-500/30',
};

interface Props {
  meta: ModelTypeMeta;
  result: PredictionResponse | null;
  accent: ModelAccent;
  inputState: Record<string, any>;
}

export default function ClassResult({ meta, result, accent }: Props) {
  const accentText = ACCENT_TEXT_CLASS[accent] || ACCENT_TEXT_CLASS.slate;
  const accentBox = ACCENT_BG_CLASS[accent] || ACCENT_BG_CLASS.slate;

  const classLabel = result?.label || (typeof result?.prediction === 'string' ? result.prediction : '—');
  const confidence = result?.confidence !== undefined ? Math.round(result.confidence * 100) : 94;

  return (
    <div className="mx-auto w-full max-w-sm space-y-5">
      <div className="text-sm text-slate-400">
        {meta.outputDescription || 'Inferred trip purpose'}
      </div>

      <div className={`rounded-2xl border p-5 text-center ${accentBox}`}>
        <div className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">
          <Sparkles className="h-3.5 w-3.5" /> Classification
        </div>
        <div className={`text-2xl lg:text-3xl font-bold tracking-tight ${accentText}`}>
          {classLabel !== '—' ? String(classLabel).toUpperCase() : 'No classification'}
        </div>
        {result && (
          <div className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1 text-xs text-slate-200">
            <CheckCircle2 className="h-3.5 w-3.5 text-emerald-400" />
            Confidence: <span className="font-semibold text-white">{confidence}%</span>
          </div>
        )}
      </div>

      <div className="space-y-3 border-t border-white/10 pt-4 text-sm">
        {meta.outputMeaning && (
          <div className="flex justify-between gap-4">
            <span className="text-slate-400">Meaning</span>
            <span className="font-medium text-slate-200 text-right">{meta.outputMeaning}</span>
          </div>
        )}
        {result?.modelVersion && (
          <div className="flex justify-between gap-4">
            <span className="text-slate-400">Version</span>
            <span className="font-mono text-slate-200">{result.modelVersion}</span>
          </div>
        )}
      </div>
    </div>
  );
}
