import { useMemo } from 'react';
import { Activity, AlertTriangle, Battery, BrainCircuit, Car, Clock3, Database, RefreshCw, Route, Users, Zap } from 'lucide-react';
import { motion } from 'motion/react';
import { useNavigate } from 'react-router-dom';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { datasetItems, type DataRecord, useAdminData } from '@/data/AdminDataContext';

function numberValue(value: unknown): number | null {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function firstNumber(record: DataRecord, fields: string[]): number | null {
  for (const field of fields) {
    const value = numberValue(record[field]);
    if (value !== null) return value;
  }
  return null;
}

function firstText(record: DataRecord, fields: string[]): string {
  for (const field of fields) {
    const value = record[field];
    if (value != null && String(value).trim()) return String(value);
  }
  return '';
}

function timestamp(record: DataRecord): number {
  const value = firstText(record, ['updatedAt', 'createdAt', 'timestamp', 'measuredAt', 'startTime', 'trainedAt']);
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export default function Dashboard() {
  const navigate = useNavigate();
  const { snapshot, loading, refreshing, error, refresh } = useAdminData();
  const accounts = datasetItems(snapshot, 'accounts');
  const vehicles = datasetItems(snapshot, 'vehicles');
  const chargeLogs = datasetItems(snapshot, 'chargeLogs');
  const trips = datasetItems(snapshot, 'tripLogs');
  const telemetry = datasetItems(snapshot, 'telemetry');
  const maintenance = datasetItems(snapshot, 'maintenance');
  const aiInsights = datasetItems(snapshot, 'aiInsights');
  const aiProfiles = datasetItems(snapshot, 'aiProfiles');
  const predictions = [...datasetItems(snapshot, 'tripPredictions'), ...datasetItems(snapshot, 'socPredictions')];

  const summary = useMemo(() => {
    const sohValues = vehicles.map(vehicle => firstNumber(vehicle, ['stateOfHealth', 'soh'])).filter((value): value is number => value !== null && value >= 0 && value <= 100);
    const avgSoh = sohValues.length ? sohValues.reduce((sum, value) => sum + value, 0) / sohValues.length : null;
    const lowBattery = vehicles.filter(vehicle => {
      const soc = firstNumber(vehicle, ['currentBattery', 'lastBatteryPercent', 'soc']);
      return soc !== null && soc < 20;
    });
    const attentionMaintenance = maintenance.filter(task => ['overdue', 'pending'].includes(String(task.status || '').toLowerCase()));
    const energyWh = chargeLogs.reduce((sum, log) => sum + (firstNumber(log, ['energyWh', 'energyConsumedWh', 'energy', 'totalEnergyWh']) ?? 0), 0);
    return { avgSoh, lowBattery, attentionMaintenance, energyWh };
  }, [vehicles, chargeLogs, maintenance]);

  const recentActivity = useMemo(() => [
    ...chargeLogs.map(item => ({ kind: 'Charge', item, at: timestamp(item), label: firstText(item, ['vehicleId', 'sessionId', 'id']) })),
    ...trips.map(item => ({ kind: 'Trip', item, at: timestamp(item), label: firstText(item, ['vehicleId', 'tripId', 'id']) })),
    ...predictions.map(item => ({ kind: 'AI prediction', item, at: timestamp(item), label: firstText(item, ['vehicleId', 'modelVersion', 'id']) })),
  ].sort((a, b) => b.at - a.at).slice(0, 8), [chargeLogs, trips, predictions]);

  const metrics = [
    { label: 'User accounts', value: accounts.length, icon: Users, action: () => navigate('/users') },
    { label: 'Registered vehicles', value: vehicles.length, icon: Car, action: () => navigate('/data?dataset=vehicles') },
    { label: 'Charging sessions', value: chargeLogs.length, icon: Zap, action: () => navigate('/data?dataset=chargeLogs') },
    { label: 'Recorded trips', value: trips.length, icon: Route, action: () => navigate('/data?dataset=tripLogs') },
    { label: 'Telemetry points', value: telemetry.length, icon: Activity, action: () => navigate('/data?dataset=telemetry') },
    { label: 'AI records', value: aiInsights.length + aiProfiles.length + predictions.length, icon: BrainCircuit, action: () => navigate('/data?dataset=aiInsights') },
  ];

  if (loading && !snapshot) return <div className="grid min-h-[60vh] place-items-center"><div className="text-center"><div className="mx-auto h-10 w-10 animate-spin rounded-full border-4 border-primary/20 border-t-primary" /><p className="mt-4 text-sm font-medium text-muted-foreground">Loading synchronized app data...</p></div></div>;

  return <div className="space-y-7">
    <div className="page-header">
      <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Operations workspace</p><h1 className="mt-2 text-3xl font-bold">Fleet overview</h1><p className="mt-1 max-w-3xl text-muted-foreground">Live administrative view of the same Firebase data used by the mobile app.</p></div>
      <Button onClick={() => void refresh()} disabled={refreshing} className="gap-2"><RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />Refresh data</Button>
    </div>

    {error && <div role="alert" className="flex items-start gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /><span>{error}</span></div>}

    <section className="overflow-hidden rounded-2xl border bg-slate-950 text-slate-100 shadow-sm">
      <div className="grid gap-px bg-slate-800 lg:grid-cols-[1.35fr_.65fr]">
        <div className="bg-slate-950 p-6 sm:p-8"><div className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[.18em] text-emerald-400"><span className="h-2 w-2 rounded-full bg-emerald-400" />Synchronized snapshot</div><h2 className="mt-4 max-w-2xl text-2xl font-semibold tracking-tight sm:text-3xl">Mobile activity, vehicle state and AI lifecycle in one operational view.</h2><p className="mt-3 max-w-2xl text-sm leading-6 text-slate-400">Data is read through the authenticated admin API. No simulated telemetry is used.</p><div className="mt-6 flex flex-wrap gap-3"><Button onClick={() => navigate('/data')} className="bg-emerald-400 text-slate-950 hover:bg-emerald-300"><Database />Explore all data</Button><Button variant="outline" onClick={() => navigate('/ai')} className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"><BrainCircuit />Open AI Studio</Button></div></div>
        <div className="grid grid-cols-2 gap-px bg-slate-800"><div className="bg-slate-900 p-5"><p className="text-3xl font-semibold">{summary.avgSoh == null ? '—' : `${summary.avgSoh.toFixed(1)}%`}</p><p className="mt-1 text-xs text-slate-400">Average fleet SoH</p></div><div className="bg-slate-900 p-5"><p className="text-3xl font-semibold">{summary.energyWh >= 1000 ? `${(summary.energyWh / 1000).toFixed(1)} kWh` : `${summary.energyWh.toFixed(0)} Wh`}</p><p className="mt-1 text-xs text-slate-400">Recorded charge energy</p></div><div className="bg-slate-900 p-5"><p className="text-3xl font-semibold">{summary.lowBattery.length}</p><p className="mt-1 text-xs text-slate-400">Vehicles below 20% SOC</p></div><div className="bg-slate-900 p-5"><p className="text-3xl font-semibold">{summary.attentionMaintenance.length}</p><p className="mt-1 text-xs text-slate-400">Maintenance items open</p></div></div>
      </div>
    </section>

    <section aria-labelledby="coverage-title"><div className="mb-3 flex items-end justify-between"><div><h2 id="coverage-title" className="text-lg font-semibold">Data coverage</h2><p className="text-sm text-muted-foreground">Select a metric to open the synchronized records.</p></div><Badge variant={snapshot?.partial ? 'destructive' : 'secondary'}>{snapshot?.partial ? 'Partial snapshot' : 'All datasets available'}</Badge></div><div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border bg-border md:grid-cols-3 xl:grid-cols-6">{metrics.map((metric, index) => <motion.button key={metric.label} type="button" onClick={metric.action} initial={{ opacity: .7, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * .035 }} className="group min-h-32 bg-card p-4 text-left transition-colors hover:bg-muted"><metric.icon className="h-5 w-5 text-primary" /><p className="mt-5 text-2xl font-semibold tabular-nums">{metric.value}</p><p className="mt-1 text-xs text-muted-foreground group-hover:text-foreground">{metric.label}</p></motion.button>)}</div></section>

    <div className="grid gap-6 lg:grid-cols-[1.45fr_.55fr]">
      <Card className="border-border/70"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Clock3 className="h-5 w-5 text-primary" />Recent app activity</CardTitle><CardDescription>Newest charging, trip and prediction records in the shared database.</CardDescription></CardHeader><CardContent>{recentActivity.length === 0 ? <div className="py-12 text-center text-sm text-muted-foreground">No recent activity has been synchronized.</div> : <div className="divide-y">{recentActivity.map((activity, index) => <button key={`${activity.kind}:${activity.at}:${index}`} type="button" onClick={() => navigate(`/data?dataset=${activity.kind === 'Charge' ? 'chargeLogs' : activity.kind === 'Trip' ? 'tripLogs' : 'tripPredictions'}`)} className="flex min-h-16 w-full items-center gap-4 py-3 text-left"><span className={`h-2.5 w-2.5 shrink-0 rounded-full ${activity.kind === 'Charge' ? 'bg-emerald-500' : activity.kind === 'Trip' ? 'bg-sky-500' : 'bg-violet-500'}`} /><span className="min-w-0 flex-1"><span className="block text-sm font-medium">{activity.kind}</span><span className="block truncate font-mono text-xs text-muted-foreground">{activity.label || 'Unidentified record'}</span></span><span className="shrink-0 text-xs text-muted-foreground">{activity.at ? new Date(activity.at).toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' }) : 'No timestamp'}</span></button>)}</div>}</CardContent></Card>

      <Card className="border-border/70"><CardHeader><CardTitle className="flex items-center gap-2 text-lg"><Battery className="h-5 w-5 text-primary" />Fleet attention</CardTitle><CardDescription>Data-derived conditions that may need review.</CardDescription></CardHeader><CardContent className="space-y-3">{summary.lowBattery.slice(0, 4).map(vehicle => { const name = firstText(vehicle, ['vehicleName', 'vinfastModelName', 'vehicleId']) || 'Vehicle'; const soc = firstNumber(vehicle, ['currentBattery', 'lastBatteryPercent', 'soc']); return <button key={firstText(vehicle, ['vehicleId']) || name} type="button" onClick={() => navigate('/data?dataset=vehicles')} className="flex w-full items-center justify-between gap-3 rounded-xl bg-amber-500/8 p-3 text-left"><span className="min-w-0"><span className="block truncate text-sm font-medium">{name}</span><span className="text-xs text-muted-foreground">Low battery state</span></span><Badge variant="outline">{soc?.toFixed(0)}%</Badge></button>; })}{summary.lowBattery.length === 0 && summary.attentionMaintenance.length === 0 && <div className="py-10 text-center"><Car className="mx-auto h-8 w-8 text-emerald-500" /><p className="mt-3 text-sm font-medium">No data-derived warnings</p><p className="mt-1 text-xs text-muted-foreground">Device safety still requires local verification.</p></div>}</CardContent></Card>
    </div>
  </div>;
}
