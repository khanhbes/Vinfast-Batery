import { InputSchema, ModelAccent } from '../types';

const ACCENT_SLIDER_CLASS: Record<ModelAccent, string> = {
  emerald: 'accent-emerald-400',
  amber: 'accent-amber-400',
  violet: 'accent-violet-400',
  blue: 'accent-blue-400',
  rose: 'accent-rose-400',
  slate: 'accent-slate-400',
};

interface Props {
  fieldName: string;
  schema?: InputSchema;
  value: any;
  onChange: (value: any) => void;
  accent: ModelAccent;
  disabled?: boolean;
}

export default function DynamicInput({
  fieldName,
  schema,
  value,
  onChange,
  accent,
  disabled = false,
}: Props) {
  const accentSlider = ACCENT_SLIDER_CLASS[accent] || ACCENT_SLIDER_CLASS.emerald;
  const label = schema?.label || schema?.desc || fieldName;
  const unit = schema?.unit ? ` ${schema.unit}` : '';
  const type = schema?.type || 'number';

  // 1. Enum / Categorical select or segmented
  if (schema?.enum && schema.enum.length > 0) {
    const enumList: (string | number)[] = schema.enum;
    return (
      <div className="flex flex-col gap-1.5">
        <div className="flex items-center justify-between text-sm">
          <span className="text-slate-300 font-medium">{label}</span>
          <span className="font-semibold text-slate-100">
            {schema.enumLabels
              ? schema.enumLabels[enumList.indexOf(value)] || value
              : value}
          </span>
        </div>
        <select
          aria-label={label}
          disabled={disabled}
          value={value ?? enumList[0]}
          onChange={(e) => {
            const raw = e.target.value;
            const parsed = type === 'integer' ? parseInt(raw, 10) : type === 'number' ? parseFloat(raw) : raw;
            onChange(parsed);
          }}
          className="mt-1 w-full rounded-lg border border-white/10 bg-slate-900 px-3 py-2 text-sm text-white focus:border-white/30 focus:outline-none disabled:opacity-50"
        >
          {enumList.map((opt, idx) => (
            <option key={String(opt)} value={opt} className="bg-slate-900 text-white">
              {schema.enumLabels?.[idx] || String(opt)}
            </option>
          ))}
        </select>
      </div>
    );
  }

  // 2. Numeric with slider if min & max are defined
  if ((type === 'number' || type === 'integer') && schema?.min !== undefined && schema?.max !== undefined) {
    const min = schema.min;
    const max = schema.max;
    const step = schema.step || (type === 'integer' ? 1 : 0.1);
    const numValue = Number(value ?? min);

    return (
      <label className="block">
        <span className="flex justify-between text-sm">
          <span className="text-slate-300 font-medium">{label}</span>
          <span className="font-semibold text-slate-100">
            {numValue}
            {unit}
          </span>
        </span>
        <input
          aria-label={label}
          disabled={disabled}
          className={`mt-3 w-full cursor-pointer ${accentSlider} disabled:opacity-50 disabled:cursor-not-allowed`}
          type="range"
          value={numValue}
          min={min}
          max={max}
          step={step}
          onChange={(e) => onChange(Number(e.target.value))}
        />
      </label>
    );
  }

  // 3. General text or numeric field without bounded slider
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between text-sm">
        <span className="text-slate-300 font-medium">{label}</span>
        {unit && <span className="text-xs text-slate-400">{unit.trim()}</span>}
      </div>
      <input
        aria-label={label}
        min={schema?.min}
        max={schema?.max}
        disabled={disabled}
        type={type === 'string' ? 'text' : 'number'}
        value={value ?? ''}
        step={schema?.step || (type === 'integer' ? '1' : 'any')}
        onChange={(e) => {
          const raw = e.target.value;
          if (type === 'integer') {
            onChange(raw);
          } else if (type === 'number') {
            onChange(raw);
          } else {
            onChange(raw);
          }
        }}
        className="mt-1 w-full rounded-lg border border-white/10 bg-slate-900 px-3 py-2 text-sm text-white focus:border-white/30 focus:outline-none disabled:opacity-50"
      />
    </div>
  );
}
