import { useCallback, useEffect, useState } from 'react';
import { AlertCircle, CheckCircle2, Cpu, ExternalLink, KeyRound, Loader2, PlugZap, RefreshCw, ShieldCheck, Trash2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { revokeShellyProfile, saveShellyProfile, shellyProfiles } from '@/api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

type Notice = { kind: 'success' | 'error'; text: string } | null;
type Profile = { deviceId: string; displayName?: string; vehicleId?: string; revision?: number; cloudVerified?: boolean; noLoadTestVerified?: boolean };

const fields = [
  ['vehicleId', 'Vehicle ID', 'Vehicle linked to this account'],
  ['deviceId', 'Shelly device ID', 'Example: shellyplusplugs-...'],
  ['cloudHost', 'Shelly Cloud host', 'https://shelly-xx-eu.shelly.cloud'],
  ['lanAddress', 'LAN address', '192.168.x.x or a .local hostname'],
  ['localUsername', 'LAN username', 'admin'],
] as const;

function SmartChargerVault() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [busy, setBusy] = useState<'load' | 'save' | string | null>('load');
  const [notice, setNotice] = useState<Notice>(null);
  const [form, setForm] = useState({ vehicleId: '', deviceId: '', cloudHost: '', cloudAuthKey: '', lanAddress: '', localUsername: 'admin', localPassword: '' });

  const refresh = useCallback(async (vehicleId = '') => {
    setBusy('load');
    setNotice(null);
    try {
      const result = await shellyProfiles(vehicleId);
      setProfiles(Array.isArray(result?.data?.items) ? result.data.items : []);
    } catch {
      setProfiles([]);
      setNotice({ kind: 'error', text: 'Smart Charger profiles could not be loaded. Check the server vault and account permissions.' });
    } finally {
      setBusy(null);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  const update = (key: keyof typeof form, value: string) => setForm(current => ({ ...current, [key]: value }));

  const save = async () => {
    if (!form.deviceId.trim() || !form.cloudHost.trim() || !form.cloudAuthKey.trim()) {
      setNotice({ kind: 'error', text: 'Device ID, Cloud host and Cloud authorization key are required.' });
      return;
    }
    if (!/^https:\/\/[^/]+\.shelly\.cloud\/?$/i.test(form.cloudHost.trim())) {
      setNotice({ kind: 'error', text: 'Cloud host must use HTTPS and belong to shelly.cloud.' });
      return;
    }
    setBusy('save');
    setNotice(null);
    try {
      await saveShellyProfile(form.deviceId.trim(), { ...form, source: 'web' });
      setForm(current => ({ ...current, cloudAuthKey: '', localPassword: '' }));
      await refresh(form.vehicleId.trim());
      setNotice({ kind: 'success', text: 'Shelly Cloud was verified and the credentials were stored in the encrypted vault.' });
    } catch {
      setNotice({ kind: 'error', text: 'The profile could not be saved. Check the Cloud key, host and vehicle ownership.' });
      setBusy(null);
    }
  };

  const revoke = async (profile: Profile) => {
    if (!window.confirm(`Revoke ${profile.displayName || profile.deviceId}? Its credentials will be removed from the vault.`)) return;
    setBusy(`revoke:${profile.deviceId}`);
    setNotice(null);
    try {
      await revokeShellyProfile(profile.deviceId);
      await refresh(form.vehicleId.trim());
      setNotice({ kind: 'success', text: `${profile.displayName || profile.deviceId} was revoked.` });
    } catch {
      setNotice({ kind: 'error', text: 'The profile could not be revoked. Refresh its state and try again.' });
      setBusy(null);
    }
  };

  return <section aria-labelledby="smart-charger-title" className="space-y-5">
    <div className="flex flex-col gap-3 border-b border-border/60 pb-5 sm:flex-row sm:items-start sm:justify-between"><div className="flex gap-3"><div className="rounded-xl bg-emerald-500/10 p-3 text-emerald-600"><PlugZap className="h-5 w-5" /></div><div><h2 id="smart-charger-title" className="text-xl font-semibold">Smart Charger</h2><p className="mt-1 max-w-2xl text-sm text-muted-foreground">Verify Shelly Cloud and store credentials per account. The Android app still performs LAN and no-load safety checks before relay control is enabled.</p></div></div><Button variant="outline" onClick={() => void refresh(form.vehicleId.trim())} disabled={busy !== null} className="gap-2"><RefreshCw className={`h-4 w-4 ${busy === 'load' ? 'animate-spin' : ''}`} />Refresh</Button></div>
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">{fields.map(([key, label, placeholder]) => <label key={key} className="space-y-2 text-sm font-medium"><span>{label}</span><Input value={form[key]} onChange={event => update(key, event.target.value)} placeholder={placeholder} autoComplete="off" /></label>)}<label className="space-y-2 text-sm font-medium"><span>Cloud authorization key <span className="text-destructive">*</span></span><Input value={form.cloudAuthKey} onChange={event => update('cloudAuthKey', event.target.value)} placeholder="Used only for this save operation" type="password" autoComplete="new-password" /></label><label className="space-y-2 text-sm font-medium"><span>LAN password</span><Input value={form.localPassword} onChange={event => update('localPassword', event.target.value)} placeholder="Optional" type="password" autoComplete="new-password" /></label></div>
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center"><Button onClick={() => void save()} disabled={busy !== null} className="gap-2">{busy === 'save' ? <Loader2 className="animate-spin" /> : <KeyRound />}Verify and save securely</Button><p className="text-xs text-muted-foreground">Secrets are never displayed again or written to Firestore metadata.</p></div>
    {notice && <div role={notice.kind === 'error' ? 'alert' : 'status'} className={`flex items-start gap-2 rounded-xl border p-3 text-sm ${notice.kind === 'error' ? 'border-destructive/30 bg-destructive/5 text-destructive' : 'border-emerald-500/30 bg-emerald-500/5 text-emerald-700'}`}>{notice.kind === 'error' ? <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" /> : <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />}<span>{notice.text}</span></div>}
    <div className="space-y-2"><h3 className="text-sm font-semibold">Stored profiles <span className="ml-1 text-muted-foreground">({profiles.length})</span></h3>{busy === 'load' ? <div className="flex items-center gap-2 py-4 text-sm text-muted-foreground" role="status"><Loader2 className="h-4 w-4 animate-spin" />Loading profiles...</div> : profiles.length === 0 ? <p className="rounded-xl border border-dashed p-5 text-sm text-muted-foreground">No Shelly profiles match the current account or vehicle filter.</p> : profiles.map(profile => <div key={profile.deviceId} className="flex flex-col gap-3 rounded-xl border border-border/60 p-4 sm:flex-row sm:items-center sm:justify-between"><div className="min-w-0"><p className="truncate font-medium">{profile.displayName || 'Shelly Charger'}</p><p className="truncate font-mono text-xs text-muted-foreground" title={profile.deviceId}>{profile.deviceId}</p><p className="mt-1 text-xs text-muted-foreground">{profile.vehicleId ? `Vehicle ${profile.vehicleId}` : 'No vehicle linked'} · revision {profile.revision ?? '—'}</p></div><div className="flex flex-wrap items-center gap-2"><Badge variant={profile.cloudVerified ? 'secondary' : 'outline'}>{profile.cloudVerified ? 'Cloud verified' : 'Cloud not verified'}</Badge><Badge variant={profile.noLoadTestVerified ? 'secondary' : 'outline'}>{profile.noLoadTestVerified ? 'No-load passed' : 'No-load pending'}</Badge><Button variant="outline" size="icon" aria-label={`Revoke ${profile.displayName || profile.deviceId}`} title="Revoke profile" disabled={busy !== null} onClick={() => void revoke(profile)}>{busy === `revoke:${profile.deviceId}` ? <Loader2 className="animate-spin" /> : <Trash2 />}</Button></div></div>)}</div>
  </section>;
}

export default function Settings() {
  const navigate = useNavigate();
  return <div className="page-enter space-y-8"><div className="page-header"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">System configuration</p><h1 className="mt-2 text-3xl font-bold">Settings</h1><p className="mt-1 text-muted-foreground">Manage device connections and open server-backed administrative tools.</p></div></div><Card className="border-border/60"><CardContent className="p-5 sm:p-6"><SmartChargerVault /></CardContent></Card><Card className="border-border/60"><CardHeader><div className="flex gap-3"><div className="rounded-xl bg-indigo-500/10 p-3 text-indigo-500"><Cpu className="h-5 w-5" /></div><div><CardTitle>Developer AI Studio</CardTitle><CardDescription className="mt-1">Upload candidates, run smoke tests, deploy and roll back versioned models in AI Studio. Runtime status always comes from the API.</CardDescription></div></div></CardHeader><CardContent className="flex flex-col gap-4 border-t border-border/60 pt-5 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-2 text-sm text-muted-foreground"><ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /><span>Settings never displays fabricated versions, metrics or deployment states.</span></div><Button onClick={() => navigate('/ai')} className="gap-2">Open AI Studio<ExternalLink className="h-4 w-4" /></Button></CardContent></Card></div>;
}
