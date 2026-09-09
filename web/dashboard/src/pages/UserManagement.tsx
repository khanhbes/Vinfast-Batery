import { useMemo, useState } from 'react';
import { AlertCircle, BatteryCharging, BrainCircuit, Car, RefreshCw, Route, Search, ShieldCheck, UserRoundX, Users, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { ModalSurface } from '@/components/ui/modal-surface';
import { datasetItems, type DataRecord, useAdminData } from '@/data/AdminDataContext';

function userId(user: DataRecord) {
  return String(user.uid || user.ownerUid || '');
}

function initials(user: DataRecord) {
  const source = String(user.displayName || user.name || user.email || userId(user) || 'U');
  return source.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase();
}

function formatDate(value: unknown) {
  if (value == null || value === '') return 'No data';
  const date = new Date(typeof value === 'number' && value < 10_000_000_000 ? value * 1000 : value as string | number);
  return Number.isNaN(date.getTime()) ? 'Unknown' : date.toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
}

function AccountDrawer({ account, related, onClose }: {
  account: DataRecord;
  related: { vehicles: number; charges: number; trips: number; ai: number; notifications: number };
  onClose: () => void;
}) {
  return <ModalSurface drawer label="Account details" onClose={onClose}>
    <div className="min-h-full bg-slate-950 p-6 text-slate-100 sm:p-8">
      <div className="flex items-start justify-between gap-4 border-b border-slate-800 pb-6"><div className="flex min-w-0 items-center gap-4"><Avatar className="h-12 w-12 border border-slate-700"><AvatarFallback className="bg-emerald-400/10 text-emerald-300">{initials(account)}</AvatarFallback></Avatar><div className="min-w-0"><p className="truncate text-xl font-semibold">{String(account.displayName || account.name || 'Unnamed account')}</p><p className="truncate text-sm text-slate-400">{String(account.email || 'No email address')}</p></div></div><Button variant="ghost" size="icon" aria-label="Close account details" onClick={onClose} className="text-slate-300 hover:bg-slate-800 hover:text-white"><X /></Button></div>
      <div className="mt-6 grid grid-cols-2 gap-px overflow-hidden rounded-xl bg-slate-800">{[
        ['Vehicles', related.vehicles], ['Charges', related.charges], ['Trips', related.trips], ['AI records', related.ai],
      ].map(([label, value]) => <div key={String(label)} className="bg-slate-900 p-4"><p className="text-2xl font-semibold">{value}</p><p className="text-xs text-slate-400">{label}</p></div>)}</div>
      <dl className="mt-6 divide-y divide-slate-800">{Object.entries(account).sort(([a], [b]) => a.localeCompare(b)).map(([key, value]) => <div key={key} className="grid gap-1 py-3 sm:grid-cols-[9rem_1fr]"><dt className="text-xs font-medium text-slate-400">{key.replace(/([a-z])([A-Z])/g, '$1 $2')}</dt><dd className="break-words font-mono text-xs">{value == null || value === '' ? '—' : typeof value === 'object' ? JSON.stringify(value) : String(value)}</dd></div>)}</dl>
      <p className="mt-6 text-xs text-slate-500">{related.notifications} notification records are linked to this account. Sensitive credential fields are redacted by the API.</p>
    </div>
  </ModalSurface>;
}

export default function UserManagement() {
  const navigate = useNavigate();
  const { snapshot, loading, refreshing, error, refresh } = useAdminData();
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<DataRecord | null>(null);
  const accounts = datasetItems(snapshot, 'accounts');
  const vehicles = datasetItems(snapshot, 'vehicles');
  const chargeLogs = datasetItems(snapshot, 'chargeLogs');
  const tripLogs = datasetItems(snapshot, 'tripLogs');
  const aiRecords = [...datasetItems(snapshot, 'aiInsights'), ...datasetItems(snapshot, 'aiProfiles'), ...datasetItems(snapshot, 'tripPredictions'), ...datasetItems(snapshot, 'socPredictions')];
  const notifications = datasetItems(snapshot, 'notifications');

  const relatedFor = (uid: string) => ({
    vehicles: vehicles.filter(item => String(item.ownerUid || '') === uid).length,
    charges: chargeLogs.filter(item => String(item.ownerUid || '') === uid).length,
    trips: tripLogs.filter(item => String(item.ownerUid || '') === uid).length,
    ai: aiRecords.filter(item => String(item.ownerUid || '') === uid || vehicles.some(vehicle => String(vehicle.ownerUid || '') === uid && String(vehicle.vehicleId || '') === String(item.vehicleId || ''))).length,
    notifications: notifications.filter(item => String(item.ownerUid || '') === uid).length,
  });

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return accounts;
    return accounts.filter(user => [user.displayName, user.name, user.email, user.uid].some(value => String(value || '').toLowerCase().includes(query)));
  }, [accounts, search]);

  const directoryMetrics = [
    { label: 'Accounts', value: accounts.length, icon: Users },
    { label: 'Administrators', value: accounts.filter(user => user.isAdmin === true || user.role === 'admin').length, icon: ShieldCheck },
    { label: 'Linked vehicles', value: vehicles.length, icon: Car },
    { label: 'Disabled', value: accounts.filter(user => user.disabled === true).length, icon: UserRoundX },
  ];

  if (loading && !snapshot) return <div className="grid min-h-[50vh] place-items-center"><div className="text-center"><div className="mx-auto h-9 w-9 animate-spin rounded-full border-4 border-primary/20 border-t-primary" /><p className="mt-3 text-sm text-muted-foreground">Loading account directory...</p></div></div>;

  return <div className="space-y-6">
    <div className="page-header"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Firebase identity</p><h1 className="mt-2 text-3xl font-bold">Accounts</h1><p className="mt-1 text-muted-foreground">Authentication records merged with app profiles and linked operational data.</p></div><Button variant="outline" onClick={() => void refresh()} disabled={refreshing} className="gap-2"><RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />Refresh directory</Button></div>
    {error && <div role="alert" className="flex items-start gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive"><AlertCircle className="mt-0.5 h-4 w-4 shrink-0" /><span>{error}</span></div>}

    <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border bg-border md:grid-cols-4">{directoryMetrics.map(({ label, value, icon: Icon }) => <div key={label} className="bg-card p-5"><Icon className="h-5 w-5 text-primary" /><p className="mt-4 text-2xl font-semibold tabular-nums">{value}</p><p className="mt-1 text-xs text-muted-foreground">{label}</p></div>)}</div>

    <Card className="border-border/70"><CardContent className="p-0"><div className="flex flex-col gap-4 border-b p-5 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="font-semibold">Account directory</h2><p className="text-sm text-muted-foreground">Select an account to inspect its complete profile and linked record counts.</p></div><div className="relative w-full sm:w-80"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input aria-label="Search accounts" placeholder="Name, email or UID" value={search} onChange={event => setSearch(event.target.value)} className="pl-10" /></div></div>
      {filtered.length === 0 ? <div className="py-16 text-center"><Users className="mx-auto h-8 w-8 text-muted-foreground" /><p className="mt-3 font-medium">{accounts.length ? 'No matching accounts' : 'No accounts returned by Firebase Auth'}</p><p className="mt-1 text-sm text-muted-foreground">{accounts.length ? 'Try another name, email address or UID.' : 'Create or sign in with the mobile app, then refresh this page.'}</p></div> : <div className="overflow-x-auto"><table className="w-full min-w-[900px] text-sm"><thead><tr className="border-b text-left text-xs text-muted-foreground"><th className="p-3 font-medium">Account</th><th className="p-3 font-medium">Role</th><th className="p-3 font-medium">Status</th><th className="p-3 font-medium">Vehicles</th><th className="p-3 font-medium">Activity</th><th className="p-3 font-medium">Created</th><th className="p-3 text-right font-medium">Details</th></tr></thead><tbody>{filtered.map(user => { const uid = userId(user); const related = relatedFor(uid); return <tr key={uid} className="border-b border-border/60 hover:bg-muted/40"><td className="p-3"><div className="flex min-w-0 items-center gap-3"><Avatar className="h-9 w-9"><AvatarFallback>{initials(user)}</AvatarFallback></Avatar><div className="min-w-0"><p className="truncate font-medium">{String(user.displayName || user.name || 'Unnamed account')}</p><p className="truncate text-xs text-muted-foreground">{String(user.email || uid)}</p></div></div></td><td className="p-3"><Badge variant={user.isAdmin === true || user.role === 'admin' ? 'default' : 'outline'}>{user.isAdmin === true || user.role === 'admin' ? 'Administrator' : 'User'}</Badge></td><td className="p-3"><Badge variant={user.disabled === true ? 'destructive' : 'secondary'}>{user.disabled === true ? 'Disabled' : user.authRecordMissing === true ? 'Profile only' : 'Active'}</Badge></td><td className="p-3"><button className="inline-flex min-h-11 items-center gap-2" onClick={() => navigate('/data?dataset=vehicles')}><Car className="h-4 w-4 text-primary" />{related.vehicles}</button></td><td className="p-3"><div className="flex gap-3 text-xs text-muted-foreground"><span className="flex items-center gap-1"><BatteryCharging className="h-3.5 w-3.5" />{related.charges}</span><span className="flex items-center gap-1"><Route className="h-3.5 w-3.5" />{related.trips}</span><span className="flex items-center gap-1"><BrainCircuit className="h-3.5 w-3.5" />{related.ai}</span></div></td><td className="whitespace-nowrap p-3 text-xs text-muted-foreground">{formatDate(user.createdAt)}</td><td className="p-3 text-right"><Button variant="ghost" size="sm" onClick={() => setSelected(user)}>Open</Button></td></tr>; })}</tbody></table></div>}
    </CardContent></Card>
    {selected && <AccountDrawer account={selected} related={relatedFor(userId(selected))} onClose={() => setSelected(null)} />}
  </div>;
}
