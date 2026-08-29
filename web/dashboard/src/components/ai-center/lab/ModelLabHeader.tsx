import { getModelIcon } from '../modelIcons';
import { ModelTypeMeta, ModelAccent } from '../types';

const ACCENT_TEXT_CLASS: Record<ModelAccent, string> = {
  emerald: 'text-emerald-400',
  amber: 'text-amber-400',
  violet: 'text-violet-400',
  blue: 'text-blue-400',
  rose: 'text-rose-400',
  slate: 'text-slate-400',
};

interface Props {
  meta: ModelTypeMeta;
  accent: ModelAccent;
}

export default function ModelLabHeader({ meta, accent }: Props) {
  const Icon = getModelIcon(meta.icon);
  const accentText = ACCENT_TEXT_CLASS[accent] || ACCENT_TEXT_CLASS.emerald;

  return (
    <div>
      <div className={`flex items-center gap-2 text-xs font-semibold uppercase tracking-[.18em] ${accentText}`}>
        <Icon className="h-4 w-4" />
        {meta.shortName || meta.label} · {meta.phase}
      </div>
      <h2 className="mt-2 text-2xl font-semibold tracking-tight text-white">
        {meta.label}
      </h2>
      <p className="mt-1 text-sm text-slate-400">
        {meta.useCase || meta.description}
      </p>
    </div>
  );
}
