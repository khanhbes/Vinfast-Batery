export type ModelAccent = 'emerald' | 'amber' | 'violet' | 'blue' | 'rose' | 'slate';
export type ModelGroup = 'survival' | 'assistant' | 'health';
export type ModelStatusLabel = 'ready' | 'in_progress' | 'planned';
export type ModelDeploymentStatus = 'planned' | 'not_deployed' | 'deployed';

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
  deploymentStatus?: ModelDeploymentStatus | string | null;
  deploymentVersion?: string | null;
  runtimeHealth?: string | null;
}

export interface InputSchema {
  type: 'string' | 'integer' | 'number';
  label?: string;
  desc?: string;
  unit?: string;
  min?: number;
  max?: number;
  step?: number;
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
  deploymentStatus?: ModelDeploymentStatus | string | null;
  deploymentVersion?: string | null;
  deployedAt?: string | null;
  deployedBy?: string | null;
  runtimeHealth?: string | null;
  latestUploadedVersion?: string | null;
  activeVersion?: string | null;
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
  prediction?: any;
  modelVersion?: string;
  input?: Record<string, any>;
  processedInput?: Record<string, any>;
  chartData?: ChartData;
  warnings?: string[];
  // Formatted output for charging_time & range prediction
  rawPrediction?: number;
  predictionSeconds?: number;
  predictionMinutes?: number;
  formattedPrediction?: string;
  estimatedRangeKm?: number;
  rangeLowKm?: number;
  rangeHighKm?: number;
  confidence?: number;
  adjustedEfficiencyKmPerPercent?: number;
  score?: number;
  label?: string;
  recommendation?: string;
  details?: Record<string, any>;
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
  smokeTestOk?: boolean;
}

export const ACCENT_CLASSES: Record<ModelAccent, { bg: string; text: string; ring: string; dot: string; border: string; glow: string }> = {
  emerald: { bg: 'bg-emerald-500/10', text: 'text-emerald-400', ring: 'ring-emerald-500/30', dot: 'bg-emerald-400', border: 'border-emerald-500/30', glow: 'shadow-emerald-500/20' },
  amber: { bg: 'bg-amber-500/10', text: 'text-amber-400', ring: 'ring-amber-500/30', dot: 'bg-amber-400', border: 'border-amber-500/30', glow: 'shadow-amber-500/20' },
  violet: { bg: 'bg-violet-500/10', text: 'text-violet-400', ring: 'ring-violet-500/30', dot: 'bg-violet-400', border: 'border-violet-500/30', glow: 'shadow-violet-500/20' },
  blue: { bg: 'bg-blue-500/10', text: 'text-blue-400', ring: 'ring-blue-500/30', dot: 'bg-blue-400', border: 'border-blue-500/30', glow: 'shadow-blue-500/20' },
  rose: { bg: 'bg-rose-500/10', text: 'text-rose-400', ring: 'ring-rose-500/30', dot: 'bg-rose-400', border: 'border-rose-500/30', glow: 'shadow-rose-500/20' },
  slate: { bg: 'bg-slate-500/10', text: 'text-slate-400', ring: 'ring-slate-500/30', dot: 'bg-slate-400', border: 'border-slate-500/30', glow: 'shadow-slate-500/20' },
};

export const LIGHT_ACCENT_CLASSES: Record<ModelAccent, { bg: string; text: string; ring: string; dot: string }> = {
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
