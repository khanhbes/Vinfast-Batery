import { Loader2 } from 'lucide-react';
import { ModelTypeMeta, PredictionResponse, ModelAccent } from '../types';
import ScalarResult from './ScalarResult';
import VectorResult from './VectorResult';
import ClassResult from './ClassResult';

interface Props {
  meta: ModelTypeMeta;
  result: PredictionResponse | null;
  loading: boolean;
  accent: ModelAccent;
  inputState: Record<string, any>;
}

export default function ModelResultPanel({
  meta,
  result,
  loading,
  accent,
  inputState,
}: Props) {
  return (
    <div className="relative flex min-h-[360px] flex-col justify-center border-t border-white/10 bg-white/[.04] p-6 lg:border-l lg:border-t-0 lg:p-8">
      {loading && (
        <div className="absolute inset-0 z-10 flex flex-col items-center justify-center bg-slate-950/70 backdrop-blur-xs">
          <Loader2 className="h-8 w-8 animate-spin text-emerald-400 opacity-90" />
          <span className="mt-2 text-xs text-slate-300 font-medium">Đang tính toán dự đoán...</span>
        </div>
      )}

      {meta.outputKind === 'vector' ? (
        <VectorResult
          meta={meta}
          result={result}
          accent={accent}
          inputState={inputState}
        />
      ) : meta.outputKind === 'class' ? (
        <ClassResult
          meta={meta}
          result={result}
          accent={accent}
          inputState={inputState}
        />
      ) : (
        <ScalarResult
          meta={meta}
          result={result}
          accent={accent}
          inputState={inputState}
        />
      )}
    </div>
  );
}
