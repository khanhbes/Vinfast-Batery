import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { adminDataSnapshot } from '@/api';

export type DataRecord = Record<string, unknown>;

export interface SnapshotDataset<T extends DataRecord = DataRecord> {
  items: T[];
  loaded: number;
  truncated: boolean;
}

export interface AdminDataSnapshot {
  schemaVersion: string;
  generatedAt: string;
  limitPerDataset: number;
  datasets: Record<string, SnapshotDataset>;
  totals: Record<string, number>;
  partial: boolean;
  errors: Record<string, string>;
  requestId?: string;
  durationMs?: number;
  requestedDatasets?: string[];
}

interface AdminDataContextValue {
  snapshot: AdminDataSnapshot | null;
  loading: boolean;
  refreshing: boolean;
  error: string;
  refresh: () => Promise<void>;
  loadDataset: (dataset: string) => Promise<void>;
}

const AdminDataContext = createContext<AdminDataContextValue | null>(null);

function normalizeDataset(value: unknown): SnapshotDataset {
  if (!value || typeof value !== 'object') return { items: [], loaded: 0, truncated: false };
  const dataset = value as Partial<SnapshotDataset>;
  const items = Array.isArray(dataset.items) ? dataset.items.filter(item => item && typeof item === 'object') as DataRecord[] : [];
  return {
    items,
    loaded: typeof dataset.loaded === 'number' ? dataset.loaded : items.length,
    truncated: dataset.truncated === true,
  };
}

function normalizeSnapshot(value: unknown): AdminDataSnapshot {
  const raw = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const rawDatasets = raw.datasets && typeof raw.datasets === 'object'
    ? raw.datasets as Record<string, unknown>
    : {};
  const datasets = Object.fromEntries(
    Object.entries(rawDatasets).map(([key, dataset]) => [key, normalizeDataset(dataset)]),
  );
  return {
    schemaVersion: String(raw.schemaVersion || 'admin-data-snapshot-v1'),
    generatedAt: String(raw.generatedAt || ''),
    limitPerDataset: Number(raw.limitPerDataset || 500),
    datasets,
    totals: raw.totals && typeof raw.totals === 'object' ? raw.totals as Record<string, number> : {},
    partial: raw.partial === true,
    errors: raw.errors && typeof raw.errors === 'object' ? raw.errors as Record<string, string> : {},
    requestId: typeof raw.requestId === 'string' ? raw.requestId : undefined,
    durationMs: typeof raw.durationMs === 'number' ? raw.durationMs : undefined,
    requestedDatasets: Array.isArray(raw.requestedDatasets) ? raw.requestedDatasets.filter(value => typeof value === 'string') as string[] : undefined,
  };
}

const SNAPSHOT_CACHE_KEY = 'vinfast-admin-snapshot-v2';
const INITIAL_DATASETS = ['core', 'operations', 'ai'];

function readCachedSnapshot(): AdminDataSnapshot | null {
  try {
    const raw = window.sessionStorage.getItem(SNAPSHOT_CACHE_KEY);
    return raw ? normalizeSnapshot(JSON.parse(raw)) : null;
  } catch {
    return null;
  }
}

function cacheSnapshot(snapshot: AdminDataSnapshot) {
  try { window.sessionStorage.setItem(SNAPSHOT_CACHE_KEY, JSON.stringify(snapshot)); } catch { /* storage is optional */ }
}

function mergeSnapshot(previous: AdminDataSnapshot | null, incoming: AdminDataSnapshot): AdminDataSnapshot {
  if (!previous) return incoming;
  const datasets = { ...previous.datasets };
  for (const [key, dataset] of Object.entries(incoming.datasets)) {
    // A partial refresh must not erase a successful, still-relevant dataset.
    if (!incoming.errors[key] || !datasets[key]) datasets[key] = dataset;
  }
  const errors = { ...previous.errors, ...incoming.errors };
  for (const key of Object.keys(incoming.datasets)) if (!incoming.errors[key]) delete errors[key];
  return {
    ...previous,
    ...incoming,
    datasets,
    totals: { ...previous.totals, ...incoming.totals },
    partial: Object.keys(errors).length > 0,
    errors,
  };
}

export function AdminDataProvider({ children }: { children: ReactNode }) {
  const [snapshot, setSnapshot] = useState<AdminDataSnapshot | null>(() => readCachedSnapshot());
  const [loading, setLoading] = useState(() => !readCachedSnapshot());
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const requestInFlight = useRef(new Set<string>());

  const load = useCallback(async (datasets: string[], limit: number, key: string) => {
    if (requestInFlight.current.has(key)) return;
    requestInFlight.current.add(key);
    setError('');
    setRefreshing(true);
    try {
      const incoming = normalizeSnapshot((await adminDataSnapshot(limit, datasets))?.data);
      setSnapshot(previous => {
        const next = mergeSnapshot(previous, incoming);
        cacheSnapshot(next);
        return next;
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The synchronized data snapshot could not be loaded.');
    } finally {
      requestInFlight.current.delete(key);
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  const refresh = useCallback(() => load(INITIAL_DATASETS, 100, 'overview'), [load]);
  const loadDataset = useCallback((dataset: string) => load([dataset], 500, `dataset:${dataset}`), [load]);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    const refreshVisibleData = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    const timer = window.setInterval(refreshVisibleData, 60_000);
    window.addEventListener('focus', refreshVisibleData);
    document.addEventListener('visibilitychange', refreshVisibleData);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', refreshVisibleData);
      document.removeEventListener('visibilitychange', refreshVisibleData);
    };
  }, [refresh]);

  const value = useMemo(() => ({ snapshot, loading, refreshing, error, refresh, loadDataset }), [snapshot, loading, refreshing, error, refresh, loadDataset]);
  return <AdminDataContext.Provider value={value}>{children}</AdminDataContext.Provider>;
}

export function useAdminData() {
  const context = useContext(AdminDataContext);
  if (!context) throw new Error('useAdminData must be used inside AdminDataProvider.');
  return context;
}

export function datasetItems(snapshot: AdminDataSnapshot | null, key: string): DataRecord[] {
  return snapshot?.datasets[key]?.items ?? [];
}

export function recordId(record: DataRecord): string {
  const candidate = record.uid ?? record.vehicleId ?? record.sessionId ?? record.tripId ?? record.taskId ?? record.typeKey ?? record.id ?? record._id;
  return candidate == null ? '' : String(candidate);
}
