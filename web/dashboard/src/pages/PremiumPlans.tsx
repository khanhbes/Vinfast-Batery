import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Crown, Gift, Plus, RefreshCw, Search, Sparkles, Ban, Copy } from 'lucide-react';
import {
  adminBillingStats,
  adminBillingUser,
  adminBillingGrant,
  adminBillingRevoke,
  adminPromos,
  adminCreatePromo,
  adminUpdatePromo,
} from '@/api';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';

type Plan = { tier: 'free' | 'pro' | 'ultra'; status: string; expiresAt: string | null; source: string | null; trialAvailable: boolean };
type HistoryEntry = { at: string; action: string; tier?: string; days?: number; expiresAt?: string; by?: string };
type Found = { user: { uid: string; email: string | null; displayName?: string | null }; plan: Plan; history: HistoryEntry[]; pendingPromo: { code: string; percentOff: number } | null };
type Promo = { code: string; percentOff: number; validFrom: string | null; validTo: string; tiers: string[]; periods: string[]; active: boolean; note: string; checks: number; state: 'active' | 'inactive' | 'expired' | 'scheduled' };
type PromoDraft = { code: string; percentOff: string; validFrom: string; validTo: string; tiers: string[]; periods: string[]; note: string };

const tierName: Record<string, string> = { free: 'Free', pro: 'Pro', ultra: 'Ultra' };
const periodName: Record<string, string> = { month: 'Tháng', year: 'Năm' };
const stateName: Record<Promo['state'], string> = { active: 'Đang dùng', inactive: 'Đã tắt', expired: 'Hết hạn', scheduled: 'Chưa bắt đầu' };
const stateTone: Record<Promo['state'], string> = {
  active: 'bg-emerald-100 text-emerald-700', inactive: 'bg-slate-100 text-slate-700',
  expired: 'bg-rose-100 text-rose-700', scheduled: 'bg-amber-100 text-amber-700',
};

function message(error: unknown, fallback: string) {
  const data = (error as { data?: { userMessage?: unknown } })?.data;
  return typeof data?.userMessage === 'string' ? data.userMessage : fallback;
}

function day(value: string | null | undefined) {
  if (!value) return '—';
  return new Date(value).toLocaleString('vi-VN', { dateStyle: 'medium', timeStyle: 'short' });
}

function inDays(days: number) {
  const date = new Date(Date.now() + days * 86400000);
  return date.toISOString().slice(0, 10);
}

const emptyPromo = (): PromoDraft => ({ code: '', percentOff: '20', validFrom: '', validTo: inDays(30), tiers: ['pro', 'ultra'], periods: ['month', 'year'], note: '' });

/** Pinova Premium (QA 135): grant/revoke plans by hand (no payment yet) and
 *  create promo codes (% off, validity, plans/periods). */
export default function PremiumPlans() {
  const [counts, setCounts] = useState<Record<string, number> | null>(null);
  const [enforced, setEnforced] = useState(true);
  const [query, setQuery] = useState('');
  const [found, setFound] = useState<Found | null>(null);
  const [busy, setBusy] = useState(false);
  const [grantTier, setGrantTier] = useState<'pro' | 'ultra'>('pro');
  const [grantPeriod, setGrantPeriod] = useState<'month' | 'year' | 'days'>('month');
  const [grantDays, setGrantDays] = useState('14');
  const [promos, setPromos] = useState<Promo[]>([]);
  const [draft, setDraft] = useState<PromoDraft | null>(null);

  const loadStats = useCallback(async () => {
    try {
      const res = await adminBillingStats();
      setCounts(res?.data?.counts || null);
      setEnforced(res?.data?.enforced !== false);
    } catch { setCounts(null); }
  }, []);

  const loadPromos = useCallback(async () => {
    try {
      const res = await adminPromos();
      setPromos(res?.data?.items || []);
    } catch { toast.error('Chưa tải được mã khuyến mãi.'); }
  }, []);

  useEffect(() => { void loadStats(); void loadPromos(); }, [loadStats, loadPromos]);

  const search = async () => {
    const q = query.trim();
    if (!q) return;
    setBusy(true);
    try {
      const res = await adminBillingUser(q);
      setFound(res?.data || null);
    } catch (error) {
      setFound(null);
      toast.error(message(error, 'Không tìm thấy tài khoản.'));
    } finally { setBusy(false); }
  };

  const grant = async () => {
    if (!found) return;
    setBusy(true);
    try {
      const body = grantPeriod === 'days'
        ? { uid: found.user.uid, tier: grantTier, days: Number(grantDays) }
        : { uid: found.user.uid, tier: grantTier, period: grantPeriod };
      await adminBillingGrant(body);
      toast.success(`Đã cấp gói ${tierName[grantTier]}.`);
      await search();
      await loadStats();
    } catch (error) {
      toast.error(message(error, 'Chưa cấp được gói.'));
    } finally { setBusy(false); }
  };

  const revoke = async () => {
    if (!found || !window.confirm(`Thu hồi gói của ${found.user.email || found.user.uid}?`)) return;
    setBusy(true);
    try {
      await adminBillingRevoke(found.user.uid);
      toast.success('Đã thu hồi, tài khoản về Free.');
      await search();
      await loadStats();
    } catch (error) {
      toast.error(message(error, 'Chưa thu hồi được.'));
    } finally { setBusy(false); }
  };

  const savePromo = async () => {
    if (!draft) return;
    const percent = Number(draft.percentOff);
    if (!Number.isInteger(percent) || percent < 1 || percent > 90) { toast.error('% giảm từ 1 đến 90.'); return; }
    if (!draft.validTo) { toast.error('Cần ngày hết hạn.'); return; }
    if (!draft.tiers.length || !draft.periods.length) { toast.error('Chọn ít nhất một gói và một kỳ hạn.'); return; }
    setBusy(true);
    try {
      // End of the chosen day, Vietnam time.
      const validTo = new Date(`${draft.validTo}T23:59:59+07:00`).toISOString();
      const validFrom = draft.validFrom ? new Date(`${draft.validFrom}T00:00:00+07:00`).toISOString() : undefined;
      const res = await adminCreatePromo({
        code: draft.code.trim() || undefined, percentOff: percent, validTo, validFrom,
        tiers: draft.tiers, periods: draft.periods, note: draft.note.trim(),
      });
      toast.success(`Đã tạo mã ${res?.data?.code}.`);
      setDraft(null);
      await loadPromos();
    } catch (error) {
      toast.error(message(error, 'Chưa tạo được mã.'));
    } finally { setBusy(false); }
  };

  const togglePromo = async (promo: Promo) => {
    try {
      await adminUpdatePromo(promo.code, { active: !promo.active });
      await loadPromos();
    } catch (error) { toast.error(message(error, 'Chưa cập nhật được mã.')); }
  };

  const toggle = (list: string[], value: string) => list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2"><Crown className="h-5 w-5 text-primary" /> Gói Premium</CardTitle>
            <CardDescription>
              Pha 1 chưa thu tiền: cấp hoặc thu hồi gói Pro/Ultra bằng tay. Hết hạn tự về Free; phiên sạc đang chạy không bị ngắt.
            </CardDescription>
          </div>
          <Button variant="outline" onClick={() => void loadStats()}><RefreshCw className="mr-2 h-4 w-4" />Tải lại</Button>
        </CardHeader>
        <CardContent className="space-y-4">
          {!enforced && <p className="rounded-md bg-amber-50 p-3 text-sm text-amber-800">Máy chủ đang TẮT kiểm tra gói (BILLING_ENFORCED=false): mọi tài khoản dùng được tất cả tính năng.</p>}
          {counts && (
            <div className="grid gap-3 sm:grid-cols-4">
              {[['pro', 'Pro'], ['ultra', 'Ultra'], ['trial', 'Đang dùng thử'], ['expired', 'Đã hết hạn']].map(([key, label]) => (
                <div key={key} className="rounded-lg border p-3">
                  <p className="text-xs text-muted-foreground">{label}</p>
                  <p className="text-2xl font-semibold tabular-nums">{counts[key] ?? 0}</p>
                </div>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input className="pl-9" placeholder="Email hoặc UID tài khoản" value={query}
                onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void search(); }} />
            </div>
            <Button onClick={() => void search()} disabled={busy}>Tìm</Button>
          </div>
          {found && (
            <div className="space-y-4 rounded-lg border p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className="font-semibold">{found.user.email || found.user.uid}</p>
                  <p className="text-xs text-muted-foreground">{found.user.uid}</p>
                </div>
                <span className="rounded-full bg-slate-100 px-3 py-1 text-sm font-semibold">
                  {tierName[found.plan.tier]}{found.plan.status === 'trial' ? ' (dùng thử)' : ''}
                  {found.plan.expiresAt ? ` · đến ${day(found.plan.expiresAt)}` : ''}
                </span>
              </div>
              {found.pendingPromo && <p className="text-sm text-muted-foreground">Mã đã nhập: <b>{found.pendingPromo.code}</b> (−{found.pendingPromo.percentOff}%)</p>}
              <div className="flex flex-wrap items-end gap-2">
                <label className="text-sm font-medium">Gói
                  <select className="mt-1 block h-9 rounded-md border bg-background px-2" value={grantTier} onChange={(e) => setGrantTier(e.target.value as 'pro' | 'ultra')}>
                    <option value="pro">Pro</option><option value="ultra">Ultra</option>
                  </select>
                </label>
                <label className="text-sm font-medium">Kỳ hạn
                  <select className="mt-1 block h-9 rounded-md border bg-background px-2" value={grantPeriod} onChange={(e) => setGrantPeriod(e.target.value as 'month' | 'year' | 'days')}>
                    <option value="month">1 tháng</option><option value="year">1 năm</option><option value="days">Số ngày…</option>
                  </select>
                </label>
                {grantPeriod === 'days' && (
                  <label className="text-sm font-medium">Ngày
                    <Input className="mt-1 w-24" type="number" min={1} max={730} value={grantDays} onChange={(e) => setGrantDays(e.target.value)} />
                  </label>
                )}
                <Button onClick={() => void grant()} disabled={busy}><Sparkles className="mr-2 h-4 w-4" />Cấp / gia hạn</Button>
                {found.plan.tier !== 'free' && <Button variant="outline" onClick={() => void revoke()} disabled={busy}><Ban className="mr-2 h-4 w-4" />Thu hồi</Button>}
              </div>
              {found.history.length > 0 && (
                <div className="space-y-1">
                  <p className="text-sm font-medium">Lịch sử</p>
                  {[...found.history].reverse().map((entry, i) => (
                    <p key={i} className="text-xs text-muted-foreground">
                      {day(entry.at)} · {entry.action === 'trial' ? 'Dùng thử' : entry.action === 'grant' ? 'Cấp' : 'Thu hồi'}
                      {entry.tier ? ` ${tierName[entry.tier]}` : ''}{entry.days ? ` ${entry.days} ngày` : ''}
                      {entry.expiresAt ? ` → ${day(entry.expiresAt)}` : ''}{entry.by ? ` · ${entry.by}` : ''}
                    </p>
                  ))}
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2"><Gift className="h-5 w-5 text-primary" /> Mã khuyến mãi</CardTitle>
            <CardDescription>Người dùng nhập mã ở màn Pinova Premium để thấy giá đã giảm; mã được ghi nhớ và áp khi mở thanh toán.</CardDescription>
          </div>
          <Button onClick={() => setDraft(emptyPromo())}><Plus className="mr-2 h-4 w-4" />Tạo mã</Button>
        </CardHeader>
        <CardContent className="space-y-4">
          {draft && (
            <div className="grid gap-3 rounded-lg border p-4 md:grid-cols-2">
              <label className="text-sm font-medium">Mã (để trống = tạo ngẫu nhiên)
                <Input className="mt-1 uppercase" maxLength={16} value={draft.code} placeholder="vd: TET2027"
                  onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '') })} />
              </label>
              <label className="text-sm font-medium">% giảm (1–90)
                <Input className="mt-1" type="number" min={1} max={90} value={draft.percentOff} onChange={(e) => setDraft({ ...draft, percentOff: e.target.value })} />
              </label>
              <label className="text-sm font-medium">Bắt đầu (tùy chọn)
                <Input className="mt-1" type="date" value={draft.validFrom} onChange={(e) => setDraft({ ...draft, validFrom: e.target.value })} />
              </label>
              <label className="text-sm font-medium">Hết hạn (cuối ngày)
                <Input className="mt-1" type="date" value={draft.validTo} onChange={(e) => setDraft({ ...draft, validTo: e.target.value })} />
              </label>
              <fieldset className="text-sm font-medium">Áp cho gói
                <div className="mt-2 flex gap-4">
                  {['pro', 'ultra'].map((t) => (
                    <label key={t} className="flex items-center gap-2 font-normal">
                      <input type="checkbox" checked={draft.tiers.includes(t)} onChange={() => setDraft({ ...draft, tiers: toggle(draft.tiers, t) })} />{tierName[t]}
                    </label>
                  ))}
                </div>
              </fieldset>
              <fieldset className="text-sm font-medium">Kỳ hạn
                <div className="mt-2 flex gap-4">
                  {['month', 'year'].map((p) => (
                    <label key={p} className="flex items-center gap-2 font-normal">
                      <input type="checkbox" checked={draft.periods.includes(p)} onChange={() => setDraft({ ...draft, periods: toggle(draft.periods, p) })} />{periodName[p]}
                    </label>
                  ))}
                </div>
              </fieldset>
              <label className="text-sm font-medium md:col-span-2">Ghi chú nội bộ
                <Input className="mt-1" maxLength={120} value={draft.note} onChange={(e) => setDraft({ ...draft, note: e.target.value })} />
              </label>
              <div className="flex justify-end gap-2 md:col-span-2">
                <Button variant="outline" onClick={() => setDraft(null)}>Hủy</Button>
                <Button onClick={() => void savePromo()} disabled={busy}>Tạo mã</Button>
              </div>
            </div>
          )}
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs text-muted-foreground">
                <tr><th className="py-2">Mã</th><th>Giảm</th><th>Gói · kỳ hạn</th><th>Hiệu lực</th><th>Lượt nhập</th><th>Trạng thái</th><th /></tr>
              </thead>
              <tbody>
                {promos.map((p) => (
                  <tr key={p.code} className="border-t">
                    <td className="py-2 font-mono font-semibold">
                      {p.code}
                      <button className="ml-2 align-middle text-muted-foreground" title="Sao chép" aria-label={`Sao chép ${p.code}`}
                        onClick={() => { void navigator.clipboard?.writeText(p.code); toast.success('Đã sao chép mã.'); }}>
                        <Copy className="inline h-3.5 w-3.5" />
                      </button>
                      {p.note && <p className="font-sans text-xs font-normal text-muted-foreground">{p.note}</p>}
                    </td>
                    <td className="tabular-nums">−{p.percentOff}%</td>
                    <td>{p.tiers.map((t) => tierName[t]).join(', ')} · {p.periods.map((x) => periodName[x]).join(', ')}</td>
                    <td className="text-xs">{p.validFrom ? `${day(p.validFrom)} → ` : 'đến '}{day(p.validTo)}</td>
                    <td className="tabular-nums">{p.checks}</td>
                    <td><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${stateTone[p.state]}`}>{stateName[p.state]}</span></td>
                    <td className="text-right">
                      {p.state !== 'expired' && <Button size="sm" variant="outline" onClick={() => void togglePromo(p)}>{p.active ? 'Tắt' : 'Bật'}</Button>}
                    </td>
                  </tr>
                ))}
                {promos.length === 0 && <tr><td colSpan={7} className="py-4 text-muted-foreground">Chưa có mã nào.</td></tr>}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
