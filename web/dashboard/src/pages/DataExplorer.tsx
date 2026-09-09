import { useMemo, useState } from 'react';
import { Activity, BatteryCharging, BrainCircuit, Car, Database, History, RefreshCw, Search, UserRound, Wrench, X } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { motion } from 'motion/react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ModalSurface } from '@/components/ui/modal-surface';
import { datasetItems, recordId, type DataRecord, useAdminData } from '@/data/AdminDataContext';

const datasetDefinitions = [
  { key: 'accounts', label: 'Accounts', icon: UserRound, description: 'Firebase Auth accounts merged with app profiles.' },
  { key: 'vehicles', label: 'Vehicles', icon: Car, description: 'Vehicles registered by mobile app users.' },
  { key: 'vehicleSpecs', label: 'Vehicle specifications', icon: Car, description: 'Reference specifications used by registered vehicles.' },
  { key: 'chargeLogs', label: 'Charging history', icon: BatteryCharging, description: 'Completed and active charging records.' },
  { key: 'smartChargeTelemetry', label: 'Smart Charge telemetry', icon: Activity, description: 'Detailed measurements captured inside charging sessions.' },
  { key: 'tripLogs', label: 'Trip history', icon: History, description: 'Recorded journeys and energy consumption.' },
  { key: 'legacyTripLogs', label: 'Legacy trip history', icon: History, description: 'Older trip records retained for backward compatibility.' },
  { key: 'telemetry', label: 'Telemetry', icon: Activity, description: 'Normalized vehicle and battery measurements.' },
  { key: 'batteryStates', label: 'Battery states', icon: BatteryCharging, description: 'Battery snapshots synchronized by the app.' },
  { key: 'maintenance', label: 'Maintenance', icon: Wrench, description: 'Scheduled and completed maintenance work.' },
  { key: 'aiInsights', label: 'AI insights', icon: BrainCircuit, description: 'Per-vehicle AI summaries and confidence metadata.' },
  { key: 'aiProfiles', label: 'AI profiles', icon: BrainCircuit, description: 'Personal model eligibility and training state.' },
  { key: 'aiDeployments', label: 'AI deployments', icon: BrainCircuit, description: 'Active model versions and deployment state.' },
  { key: 'tripPredictions', label: 'Trip predictions', icon: BrainCircuit, description: 'Range and route predictions created by the app.' },
  { key: 'socPredictions', label: 'SOC predictions', icon: BrainCircuit, description: 'Battery SOC prediction history.' },
  { key: 'smartChargingSessions', label: 'Smart Charge sessions', icon: BatteryCharging, description: 'Cloud-managed charging sessions.' },
  { key: 'chargingTrainingSamples', label: 'Training samples', icon: Database, description: 'Immutable Personal AI training observations.' },
  { key: 'chargeSamples', label: 'Charge samples', icon: Database, description: 'Fine-grained samples collected during charging.' },
  { key: 'chargeFeedback', label: 'Charge feedback', icon: Database, description: 'Measured outcomes used to evaluate charging predictions.' },
  { key: 'smartChargePreferences', label: 'Charging preferences', icon: BatteryCharging, description: 'User Smart Charge preferences by vehicle.' },
  { key: 'vehicleChargerBindings', label: 'Charger bindings', icon: BatteryCharging, description: 'User-owned mappings between vehicles and charger profiles.' },
  { key: 'notifications', label: 'Notifications', icon: Activity, description: 'Notifications generated for mobile users.' },
  { key: 'auditLogs', label: 'Audit records', icon: History, description: 'Administrative and security-sensitive activity records.' },
] as const;

const preferredColumns: Record<string, string[]> = {
  accounts: ['displayName', 'email', 'role', 'disabled', 'uid', 'lastSignIn'],
  vehicles: ['vehicleName', 'vinfastModelName', 'currentBattery', 'stateOfHealth', 'currentOdo', 'ownerUid'],
  vehicleSpecs: ['modelName', 'batteryCapacity', 'rangeKm', 'motorPower', 'modelId'],
  chargeLogs: ['vehicleId', 'startBatteryPercent', 'endBatteryPercent', 'energyWh', 'startTime', 'endTime', 'ownerUid'],
  smartChargeTelemetry: ['sessionId', 'soc', 'voltageV', 'powerW', 'energyWh', 'measuredAt', 'source'],
  tripLogs: ['vehicleId', 'distance', 'batteryConsumed', 'startTime', 'endTime', 'ownerUid'],
  legacyTripLogs: ['vehicleId', 'distance', 'batteryConsumed', 'startTime', 'endTime', 'ownerUid'],
  telemetry: ['vehicleId', 'sessionId', 'soc', 'voltageV', 'powerW', 'energyWh', 'measuredAt', 'source'],
  batteryStates: ['vehicleId', 'percentage', 'soh', 'estimatedRange', 'temp', 'timestamp', 'source'],
  maintenance: ['vehicleId', 'taskType', 'status', 'priority', 'dueDate', 'ownerUid'],
  aiInsights: ['vehicleId', 'healthScore', 'modelVersion', 'confidence', 'updatedAt', 'ownerUid'],
  aiProfiles: ['vehicleId', 'dataPoints', 'eligible', 'version', 'trainedAt', 'ownerUid'],
  aiDeployments: ['typeKey', 'activeVersion', 'deploymentStatus', 'updatedAt'],
  tripPredictions: ['vehicleId', 'distance', 'consumption', 'startBattery', 'endBattery', 'isSafe', 'timestamp'],
  socPredictions: ['vehicleId', 'currentSoc', 'predictedSoc', 'confidence', 'modelVersion', 'timestamp'],
  smartChargingSessions: ['vehicleId', 'state', 'current_soc', 'target_soc', 'device_id', 'created_at', 'ownerUid'],
  chargingTrainingSamples: ['vehicleId', 'sessionId', 'actualDurationSec', 'predictedDurationSec', 'modelVersion', 'updatedAt'],
  chargeSamples: ['vehicleId', 'sessionId', 'batteryPercent', 'powerW', 'energyWh', 'timestamp'],
  chargeFeedback: ['vehicleId', 'predictedDurationMinutes', 'actualDurationMinutes', 'errorPercent', 'modelVersion', 'createdAt'],
  smartChargePreferences: ['vehicleId', 'targetSoc', 'scheduleEnabled', 'updatedAt', 'ownerUid'],
  vehicleChargerBindings: ['vehicleId', 'profileId', 'chargerId', 'updatedAt', 'ownerUid'],
  notifications: ['title', 'type', 'isRead', 'vehicleId', 'createdAt', 'ownerUid'],
  auditLogs: ['action', 'entity', 'entityId', 'actorEmail', 'createdAt'],
};

function textValue(value: unknown): string {
  if (value == null || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : value.toFixed(2);
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function labelFor(field: string): string {
  return field.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/_/g, ' ').replace(/^./, value => value.toUpperCase());
}

function RecordDrawer({ record, dataset, ownerName, onClose }: {
  record: DataRecord;
  dataset: string;
  ownerName: string;
  onClose: () => void;
}) {
  return <ModalSurface drawer label={`${dataset} record details`} onClose={onClose}>
    <div className="min-h-full bg-slate-950 p-6 text-slate-100 sm:p-8">
      <div className="flex items-start justify-between gap-4 border-b border-slate-800 pb-5">
        <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-emerald-400">{dataset}</p><h2 className="mt-2 text-2xl font-semibold">Record details</h2><p className="mt-1 break-all font-mono text-xs text-slate-400">{recordId(record) || 'No stable ID'}</p></div>
        <Button variant="ghost" size="icon" aria-label="Close details" onClick={onClose} className="text-slate-300 hover:bg-slate-800 hover:text-white"><X /></Button>
      </div>
      {ownerName && <div className="mt-5 flex items-center justify-between rounded-xl bg-slate-900 px-4 py-3"><span className="text-sm text-slate-400">Account</span><span className="text-sm font-medium">{ownerName}</span></div>}
      <dl className="mt-6 divide-y divide-slate-800">
        {Object.entries(record).sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => <div key={key} className="grid gap-1 py-3 sm:grid-cols-[10rem_1fr] sm:gap-4"><dt className="text-xs font-medium text-slate-400">{labelFor(key)}</dt><dd className="break-words font-mono text-xs leading-5 text-slate-100">{textValue(value)}</dd></div>)}
      </dl>
    </div>
  </ModalSurface>;
}

export default function DataExplorer() {
  const { snapshot, loading, refreshing, error, refresh } = useAdminData();
  const [params, setParams] = useSearchParams();
  const requested = params.get('dataset');
  const activeKey = datasetDefinitions.some(item => item.key === requested) ? requested! : 'vehicles';
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<DataRecord | null>(null);

  const accounts = datasetItems(snapshot, 'accounts');
  const ownerNames = useMemo(() => new Map(accounts.map(account => {
    const uid = String(account.uid || account.ownerUid || '');
    return [uid, String(account.displayName || account.email || uid)];
  })), [accounts]);
  const definition = datasetDefinitions.find(item => item.key === activeKey)!;
  const records = datasetItems(snapshot, activeKey);
  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return records;
    return records.filter(record => JSON.stringify(record).toLowerCase().includes(query));
  }, [records, search]);
  const columns = useMemo(() => {
    const preferred = preferredColumns[activeKey] ?? [];
    const available = new Set(records.flatMap(record => Object.keys(record)));
    const chosen = preferred.filter(column => available.has(column));
    if (chosen.length >= 3) return chosen.slice(0, 7);
    return Array.from(available).filter(key => !['isDeleted', 'deletedAt', 'deletedBy'].includes(key)).slice(0, 7);
  }, [activeKey, records]);
  const currentDataset = snapshot?.datasets[activeKey];

  return <div className="space-y-6">
    <div className="page-header">
      <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Shared Firebase workspace</p><h1 className="mt-2 text-3xl font-bold">App data explorer</h1><p className="mt-1 max-w-3xl text-muted-foreground">One synchronized, read-only view of account, vehicle, charging, trip, telemetry and AI data written by the mobile app and backend.</p></div>
      <Button variant="outline" onClick={() => void refresh()} disabled={refreshing} className="gap-2"><RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />Refresh snapshot</Button>
    </div>

    {error && <div role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">{error}</div>}
    {snapshot?.partial && <div role="status" className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-4 text-sm text-amber-700 dark:text-amber-300">Some datasets could not be read. Available data is still shown; check the dataset status and server logs.</div>}

    <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border bg-border sm:grid-cols-4">
      {[
        ['Accounts', snapshot?.totals.accounts ?? 0],
        ['Vehicles', snapshot?.totals.vehicles ?? 0],
        ['Charge records', snapshot?.totals.chargeLogs ?? 0],
        ['AI records', (snapshot?.totals.aiInsights ?? 0) + (snapshot?.totals.aiProfiles ?? 0) + (snapshot?.totals.tripPredictions ?? 0) + (snapshot?.totals.socPredictions ?? 0)],
      ].map(([label, value]) => <div key={String(label)} className="bg-card px-5 py-4"><p className="text-2xl font-semibold tabular-nums">{value}</p><p className="mt-1 text-xs text-muted-foreground">{label}</p></div>)}
    </div>

    <div className="grid gap-6 lg:grid-cols-[15rem_minmax(0,1fr)]">
      <nav aria-label="Data collections" className="flex gap-2 overflow-x-auto pb-2 lg:block lg:space-y-1 lg:overflow-visible">
        {datasetDefinitions.map(({ key, label, icon: Icon }) => {
          const active = key === activeKey;
          const total = snapshot?.totals[key] ?? 0;
          return <button key={key} type="button" onClick={() => { setParams({ dataset: key }); setSelected(null); }} className={`flex min-h-12 shrink-0 items-center gap-3 rounded-xl px-3 text-left text-sm transition-colors lg:w-full ${active ? 'bg-primary/10 font-semibold text-primary' : 'text-muted-foreground hover:bg-muted hover:text-foreground'}`}><Icon className="h-4 w-4 shrink-0" /><span className="flex-1 whitespace-nowrap">{label}</span><span className="tabular-nums opacity-70">{total}</span></button>;
        })}
      </nav>

      <motion.section key={activeKey} initial={{ opacity: .75, y: 6 }} animate={{ opacity: 1, y: 0 }} className="min-w-0">
        <div className="flex flex-col gap-4 border-b pb-5 sm:flex-row sm:items-end sm:justify-between">
          <div><div className="flex items-center gap-2"><h2 className="text-xl font-semibold">{definition.label}</h2>{currentDataset?.truncated && <Badge variant="outline">First {currentDataset.loaded}</Badge>}</div><p className="mt-1 text-sm text-muted-foreground">{definition.description}</p></div>
          <div className="relative w-full sm:w-72"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input value={search} onChange={event => setSearch(event.target.value)} aria-label={`Search ${definition.label}`} placeholder="Search current dataset" className="pl-10" /></div>
        </div>

        {loading && !snapshot ? <div className="grid min-h-64 place-items-center text-sm text-muted-foreground" role="status">Loading synchronized data...</div> : filtered.length === 0 ? <div className="grid min-h-64 place-items-center border-b text-center"><div><Database className="mx-auto h-8 w-8 text-muted-foreground" /><p className="mt-3 font-medium">{records.length ? 'No matching records' : 'No records in this dataset'}</p><p className="mt-1 text-sm text-muted-foreground">{records.length ? 'Try a different search term.' : 'New app data will appear after the next refresh.'}</p></div></div> : <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-sm"><thead><tr className="border-b text-left text-xs text-muted-foreground">{columns.map(column => <th key={column} className="px-3 py-3 font-medium">{labelFor(column)}</th>)}<th className="px-3 py-3 text-right font-medium">Details</th></tr></thead>
            <tbody>{filtered.map((record, index) => <tr key={`${recordId(record)}:${index}`} className="border-b border-border/60 transition-colors hover:bg-muted/45">{columns.map(column => <td key={column} className="max-w-56 truncate px-3 py-3" title={textValue(record[column])}>{column === 'ownerUid' ? ownerNames.get(String(record[column] || '')) || textValue(record[column]) : textValue(record[column])}</td>)}<td className="px-3 py-2 text-right"><Button variant="ghost" size="sm" onClick={() => setSelected(record)}>Open</Button></td></tr>)}</tbody>
          </table>
        </div>}
        <div className="flex flex-wrap items-center justify-between gap-2 pt-4 text-xs text-muted-foreground"><span>{filtered.length} of {records.length} loaded records</span><span>{snapshot?.generatedAt ? `Snapshot ${new Date(snapshot.generatedAt).toLocaleString('en-US')}` : 'Snapshot not loaded'}</span></div>
      </motion.section>
    </div>

    {selected && <RecordDrawer record={selected} dataset={definition.label} ownerName={ownerNames.get(String(selected.ownerUid || '')) || ''} onClose={() => setSelected(null)} />}
  </div>;
}
