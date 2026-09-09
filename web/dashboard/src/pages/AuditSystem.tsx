import { useCallback, useEffect, useMemo, useState } from 'react';
import { Activity, AlertCircle, RefreshCw, Search, Shield, User } from 'lucide-react';
import { adminAuditLogs } from '@/api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

interface AuditLog {
  id: string;
  action: string;
  entity: string;
  entityId: string;
  actorUid: string;
  actorEmail: string;
  timestamp: unknown;
  details: Record<string, unknown>;
}

function timestampValue(value: unknown): Date | null {
  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    const seconds = Number(record.seconds ?? record._seconds);
    if (Number.isFinite(seconds)) return new Date(seconds * 1000);
  }
  return null;
}

function formatTimestamp(value: unknown) {
  const date = timestampValue(value);
  return date
    ? new Intl.DateTimeFormat('en-US', { dateStyle: 'short', timeStyle: 'medium' }).format(date)
    : 'Unknown';
}

function actionKind(action: string): 'critical' | 'model' | 'data' {
  const normalized = action.toLowerCase();
  if (/delete|reset|revoke|disable/.test(normalized)) return 'critical';
  if (/model|train|deploy|rollback|upload|predict/.test(normalized)) return 'model';
  return 'data';
}

function detailsText(details: Record<string, unknown>) {
  const entries = Object.entries(details ?? {});
  if (entries.length === 0) return 'No additional details';
  return entries.slice(0, 4).map(([key, value]) => `${key}: ${typeof value === 'object' ? JSON.stringify(value) : String(value)}`).join(' · ');
}

export default function AuditSystem() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [kind, setKind] = useState<'all' | 'critical' | 'model' | 'data'>('all');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const loadAuditLogs = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await adminAuditLogs();
      const data = Array.isArray(response?.data) ? response.data : [];
      setLogs(data.map((item: any, index: number): AuditLog => ({
        id: String(item.id ?? item._id ?? `audit-${index}`),
        action: String(item.action ?? 'unknown'),
        entity: String(item.entity ?? item.type ?? 'system'),
        entityId: String(item.entityId ?? item.version ?? '—'),
        actorUid: String(item.actorUid ?? item.actor ?? 'system'),
        actorEmail: String(item.actorEmail ?? ''),
        timestamp: item.timestamp ?? item.createdAt ?? null,
        details: item.details && typeof item.details === 'object' ? item.details : {},
      })));
    } catch {
      setLogs([]);
      setError('The audit log could not be loaded. Check the API and Firebase permissions, then try again.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void loadAuditLogs(); }, [loadAuditLogs]);

  const filteredLogs = useMemo(() => {
    const query = searchTerm.trim().toLowerCase();
    return logs.filter(log => {
      if (kind !== 'all' && actionKind(log.action) !== kind) return false;
      if (!query) return true;
      return [log.action, log.entity, log.entityId, log.actorUid, log.actorEmail, detailsText(log.details)]
        .some(value => value.toLowerCase().includes(query));
    });
  }, [kind, logs, searchTerm]);

  if (loading && logs.length === 0) {
    return <div className="flex min-h-[50vh] items-center justify-center" role="status"><div className="text-center">
      <RefreshCw className="mx-auto mb-3 h-7 w-7 animate-spin text-primary" />
      <p className="text-sm text-muted-foreground">Loading audit log...</p>
    </div></div>;
  }

  const counts = {
    all: logs.length,
    critical: logs.filter(log => actionKind(log.action) === 'critical').length,
    model: logs.filter(log => actionKind(log.action) === 'model').length,
    data: logs.filter(log => actionKind(log.action) === 'data').length,
  };

  return <div className="page-enter space-y-6">
    <div className="page-header gap-4">
      <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Security trail</p><h1 className="mt-2 text-3xl font-bold">Audit log</h1><p className="mt-1 text-muted-foreground">Administrative events recorded by the backend; no simulated entries are shown.</p></div>
      <Button variant="outline" onClick={() => void loadAuditLogs()} disabled={loading} className="gap-2"><RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />Refresh</Button>
    </div>

    {error && <div role="alert" className="flex items-start gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm">
      <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
      <div className="flex-1"><p className="font-medium">Audit log unavailable</p><p className="mt-1 text-muted-foreground">{error}</p></div>
      <Button variant="outline" size="sm" onClick={() => void loadAuditLogs()}>Try again</Button>
    </div>}

    <div className="flex flex-wrap gap-2" aria-label="Filter audit events by category">
      {([
        ['all', 'All events'], ['critical', 'Sensitive'], ['model', 'AI & models'], ['data', 'Data'],
      ] as const).map(([value, label]) => <Button key={value} variant={kind === value ? 'default' : 'outline'} size="sm" onClick={() => setKind(value)}>
        {label}<span className="ml-2 tabular-nums opacity-70">{counts[value]}</span>
      </Button>)}
    </div>

    <Card className="border-border/60">
      <CardHeader className="gap-4 sm:flex-row sm:items-center sm:justify-between">
        <CardTitle className="flex items-center gap-2 text-lg"><Shield className="h-5 w-5 text-primary" />Recent events</CardTitle>
        <div className="relative w-full sm:w-80"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><Input aria-label="Search audit log" value={searchTerm} onChange={event => setSearchTerm(event.target.value)} placeholder="Action, account or entity" className="pl-10" /></div>
      </CardHeader>
      <CardContent>
        {filteredLogs.length === 0 ? <div className="py-12 text-center"><Activity className="mx-auto mb-3 h-8 w-8 text-muted-foreground" /><p className="font-medium">{logs.length ? 'No matching events' : 'No administrative events yet'}</p><p className="mt-1 text-sm text-muted-foreground">{logs.length ? 'Change the filter or search term.' : 'Events appear after the backend records an administrative action.'}</p></div> : <div className="overflow-x-auto">
          <table className="w-full min-w-[860px] text-sm"><thead><tr className="border-b text-left text-muted-foreground"><th className="p-3 font-medium">Time</th><th className="p-3 font-medium">Action</th><th className="p-3 font-medium">Actor</th><th className="p-3 font-medium">Entity</th><th className="p-3 font-medium">Details</th></tr></thead>
            <tbody>{filteredLogs.map(log => { const category = actionKind(log.action); return <tr key={log.id} className="border-b border-border/50 align-top last:border-0"><td className="whitespace-nowrap p-3 text-muted-foreground">{formatTimestamp(log.timestamp)}</td><td className="p-3"><Badge variant={category === 'critical' ? 'destructive' : category === 'model' ? 'default' : 'secondary'}>{log.action}</Badge></td><td className="p-3"><div className="flex gap-2"><User className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" /><div><p>{log.actorEmail || 'System'}</p><p className="max-w-48 truncate font-mono text-xs text-muted-foreground" title={log.actorUid}>{log.actorUid}</p></div></div></td><td className="p-3"><p>{log.entity}</p><p className="max-w-48 truncate font-mono text-xs text-muted-foreground" title={log.entityId}>{log.entityId}</p></td><td className="max-w-md p-3 text-muted-foreground"><p className="line-clamp-3" title={detailsText(log.details)}>{detailsText(log.details)}</p></td></tr>; })}</tbody>
          </table>
        </div>}
      </CardContent>
    </Card>
  </div>;
}
