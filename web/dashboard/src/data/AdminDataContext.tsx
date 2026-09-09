import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
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
}

interface AdminDataContextValue {
  snapshot: AdminDataSnapshot | null;
  loading: boolean;
  refreshing: boolean;
  error: string;
  refresh: () => Promise<void>;
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
  };
}

export function AdminDataProvider({ children }: { children: ReactNode }) {
  const [snapshot, setSnapshot] = useState<AdminDataSnapshot | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    setError('');
    setRefreshing(true);
    try {
      const response = await adminDataSnapshot(500);
      setSnapshot(normalizeSnapshot(response?.data));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The synchronized data snapshot could not be loaded.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const value = useMemo(() => ({ snapshot, loading, refreshing, error, refresh }), [snapshot, loading, refreshing, error, refresh]);
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
