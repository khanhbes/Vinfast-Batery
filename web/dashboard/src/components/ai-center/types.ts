export type ModelAccent = 'emerald' | 'amber' | 'violet' | 'blue' | 'rose' | 'slate';
export type ModelGroup = 'survival' | 'assistant' | 'health';
export type ModelStatusLabel = 'ready' | 'in_progress' | 'planned';

export interface ModelTypeStatus {
  isLoaded: boolean;
  isPredictable?: boolean;
  activeVersion: string | null;
  lastLoadAt?: string | null;
  lastError?: string | null;
  validationError?: string | null;
  predictorKind?: string | null;
  featureCount?: number | null;
  versionsCount: number;
}

export interface InputSchema {
  type: 'string' | 'integer' | 'number';
  desc?: string;
  unit?: string;
  min?: number;
  max?: number;
  enum?: number[] | string[];
  enumLabels?: string[];
}

export interface DerivedField {
  from?: string[];
  formula?: string;
  default?: number;
}

export interface ModelTypeMeta {
  key: string;
  label: string;
  shortName?: string;
  description: string;
  useCase?: string;
  outputDescription?: string;
  outputUnit?: string;
  outputMeaning?: string;
  icon: string;
  accent: ModelAccent;
  group: ModelGroup;
  phase: string;          // 'v1.0' | 'v2.0' | 'v3.0'
  status: ModelStatusLabel;
  inputFields: string[];
  visibleInputFields?: string[];
  derivedFields?: Record<string, DerivedField>;
  displayUnit?: 'time' | 'percentage' | 'distance' | 'scalar';
  inputSchema?: Record<string, InputSchema>;
  outputKind: 'scalar' | 'vector' | 'class';
  chartHint?: 'bar' | 'line';
  sampleInput?: Record<string, any>;
  // Runtime status is nested under 'status' in API but conflicts with label;
  // we rename to runtimeStatus on the client:
  runtimeStatus: ModelTypeStatus;
}

// Prediction response types
export interface ChartDataPoint {
  name: string;
  value: number;
}

export interface ChartData {
  type: 'scalar' | 'vector' | 'class';
  data: ChartDataPoint[];
  unit?: string;
}

export interface PredictionResponse {
  prediction: number;
  modelVersion: string;
  input: Record<string, any>;
  processedInput: Record<string, any>;
  chartData: ChartData;
  warnings: string[];
  // Formatted output for charging_time
  rawPrediction?: number;
  predictionSeconds?: number;
  predictionMinutes?: number;
  formattedPrediction?: string;
}

export interface ModelGroupMeta {
  key: ModelGroup;
  label: string;
  subtitle: string;
  phase: string;
  order: number;
}

export interface ModelVersion {
  version: string;
  active: boolean;
  uploadedAt: string;
  note?: string;
  sizeBytes?: number;
  path?: string;
}

export const ACCENT_CLASSES: Record<ModelAccent, { bg: string; text: string; ring: string; dot: string }> = {
  emerald: { bg: 'bg-emerald-50', text: 'text-emerald-700', ring: 'ring-emerald-200', dot: 'bg-emerald-500' },
  amber: { bg: 'bg-amber-50', text: 'text-amber-700', ring: 'ring-amber-200', dot: 'bg-amber-500' },
  violet: { bg: 'bg-violet-50', text: 'text-violet-700', ring: 'ring-violet-200', dot: 'bg-violet-500' },
  blue: { bg: 'bg-blue-50', text: 'text-blue-700', ring: 'ring-blue-200', dot: 'bg-blue-500' },
  rose: { bg: 'bg-rose-50', text: 'text-rose-700', ring: 'ring-rose-200', dot: 'bg-rose-500' },
  slate: { bg: 'bg-slate-100', text: 'text-slate-700', ring: 'ring-slate-200', dot: 'bg-slate-500' },
};

export function formatBytes(n?: number): string {
  if (!n) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v.toFixed(v < 10 ? 2 : 1)} ${units[i]}`;
}

export function formatDate(iso?: string | null): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleString('vi-VN');
  } catch {
    return iso;
  }
}
