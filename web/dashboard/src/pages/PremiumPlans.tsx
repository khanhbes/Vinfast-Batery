import { useCallback, useEffect, useState, useMemo } from 'react';
import { toast } from 'sonner';
import {
  Ban,
  Crown,
  Gift,
  Plus,
  RefreshCw,
  Search,
  Sparkles,
  ShieldAlert,
} from 'lucide-react';
import {
  adminBillingGrant,
  adminBillingRevoke,
  adminBillingStats,
  adminBillingUser,
  adminCheckOrder,
  adminCreatePromo,
  adminPaymentOrders,
  adminPromos,
  adminRefundOrder,
  adminUpdatePromo,
} from '@/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { StatusBadge, PlanBadge } from '@/components/common/StatusBadge';
import { CopyChip } from '@/components/common/CopyChip';

type Found = {
  user: { uid: string; email: string | null };
  plan: {
    tier: 'free' | 'pro' | 'ultra';
    status: 'active' | 'trial' | 'expired';
    expiresAt: string | null;
  };
  pendingPromo: { code: string; percentOff: number } | null;
  history: { at: string; action: string; tier?: string; by?: string; note?: string }[];
};

type Promo = {
  code: string;
  percentOff: number;
  active: boolean;
  validFrom: string | null;
  validTo: string;
  tiers: ('pro' | 'ultra')[];
  periods: ('month' | 'year')[];
  uses: number;
  maxUses: number | null;
  checks: number;
  note: string;
  createdAt: string;
};

type Order = {
  orderId: string;
  uid: string;
  tier: 'pro' | 'ultra';
  period: 'month' | 'year';
  days: number;
  amount: number;
  promoCode: string | null;
  credit: number;
  status: 'pending' | 'paid' | 'failed' | 'review' | 'refunded';
  method: 'momo' | 'free';
  transId: number | null;
  needsReview: boolean;
  reviewReason: string | null;
  createdAt: string | null;
  paidAt: string | null;
};

const orderStatus: Record<Order['status'], { label: string; tone: 'success' | 'warning' | 'danger' | 'neutral' }> = {
  paid: { label: 'Đã thanh toán', tone: 'success' },
  pending: { label: 'Đang chờ', tone: 'warning' },
  review: { label: 'Cần kiểm tra', tone: 'danger' },
  failed: { label: 'Không thành công', tone: 'neutral' },
  refunded: { label: 'Đã hoàn tiền', tone: 'neutral' },
};

function vnd(value: number) {
  return value === 0 ? 'Miễn phí' : `${value.toLocaleString('vi-VN')}đ`;
}

type PromoDraft = {
  code: string;
  percentOff: string;
  validFrom: string;
  validTo: string;
  tiers: ('pro' | 'ultra')[];
  periods: ('month' | 'year')[];
  maxUses: string;
  note: string;
};

const tierName: Record<string, string> = { free: 'Miễn phí', pro: 'Pinova Pro', ultra: 'Pinova Ultra' };

function day(value: string | null) {
  return value
    ? new Date(value).toLocaleDateString('vi-VN', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      })
    : '—';
}

function message(error: unknown, fallback: string) {
  const data = (error as { data?: { userMessage?: unknown } })?.data;
  return typeof data?.userMessage === 'string' ? data.userMessage : fallback;
}

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
  const [orders, setOrders] = useState<Order[]>([]);
  const [orderFilter, setOrderFilter] = useState('');
  const [revenue, setRevenue] = useState<{ month: string; amount: number; momo: boolean; sandbox: boolean } | null>(
    null
  );
  const [draft, setDraft] = useState<PromoDraft | null>(null);

  const plansCatalog = useMemo(
    () => [
      {
        key: 'free',
        name: 'Miễn phí',
        price: '0đ/tháng',
        subscribers: counts?.free ?? 0,
        description: '1 xe liên kết · 10 lượt Pinova Bot/ngày · Giám sát cơ bản',
        tone: 'text-slate-400',
        isSystem: true,
      },
      {
        key: 'pro',
        name: 'Pinova Pro',
        price: '29.000đ/tháng · 249.000đ/năm',
        subscribers: counts?.pro ?? 0,
        description: '2 xe · 30 lượt Bot/ngày · Sạc đến % tự ngắt · Lộ trình · Sức khỏe pin đầy đủ',
        tone: 'text-sky-400',
        isSystem: false,
      },
      {
        key: 'ultra',
        name: 'Pinova Ultra',
        price: '49.000đ/tháng · 449.000đ/năm',
        subscribers: counts?.ultra ?? 0,
        description: 'Tối đa 10 xe · 100 lượt Bot/ngày · Sạc đêm · AI cá nhân · Giao diện Aurora',
        tone: 'text-[var(--accent-primary)]',
        isSystem: false,
      },
    ],
    [counts]
  );

  const loadStats = useCallback(async () => {
    try {
      const res = await adminBillingStats();
      setCounts(res?.data?.counts || null);
      setEnforced(res?.data?.enforced !== false);
    } catch {
      setCounts(null);
    }
  }, []);

  const loadPromos = useCallback(async () => {
    try {
      const res = await adminPromos();
      setPromos(res?.data?.items || []);
    } catch {
      toast.error('Chưa tải được mã khuyến mại.');
    }
  }, []);

  const loadOrders = useCallback(async (status: string) => {
    try {
      const res = await adminPaymentOrders(status);
      setOrders(res?.data?.items || []);
      setRevenue({
        month: res?.data?.month || '',
        amount: res?.data?.monthRevenue || 0,
        momo: res?.data?.channels?.momo === true,
        sandbox: res?.data?.channels?.sandbox === true,
      });
    } catch {
      toast.error('Chưa tải được giao dịch.');
    }
  }, []);

  useEffect(() => {
    void loadStats();
    void loadPromos();
  }, [loadStats, loadPromos]);

  useEffect(() => {
    void loadOrders(orderFilter);
  }, [loadOrders, orderFilter]);

  const refundOrder = async (order: Order) => {
    if (
      !window.confirm(
        `Hoàn ${vnd(order.amount)} qua MoMo cho đơn ${order.orderId}? Gói của đơn này sẽ kết thúc.`
      )
    )
      return;
    setBusy(true);
    try {
      await adminRefundOrder(order.orderId);
      toast.success(`Đã hoàn tiền đơn ${order.orderId}.`);
      await loadOrders(orderFilter);
      await loadStats();
    } catch (error) {
      toast.error(message(error, 'Chưa hoàn tiền được.'));
    } finally {
      setBusy(false);
    }
  };

  const checkOrder = async (order: Order) => {
    setBusy(true);
    try {
      const res = await adminCheckOrder(order.orderId);
      toast.success(`Đơn ${order.orderId}: ${orderStatus[res?.data?.status as Order['status']]?.label || 'đã kiểm tra'}.`);
      await loadOrders(orderFilter);
    } catch (error) {
      toast.error(message(error, 'Chưa hỏi lại được MoMo.'));
    } finally {
      setBusy(false);
    }
  };

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
    } finally {
      setBusy(false);
    }
  };

  const grant = async () => {
    if (!found) return;
    setBusy(true);
    try {
      const body =
        grantPeriod === 'days'
          ? { uid: found.user.uid, tier: grantTier, days: Number(grantDays) }
          : { uid: found.user.uid, tier: grantTier, period: grantPeriod };
      await adminBillingGrant(body);
      toast.success(`Đã cấp thành công gói ${tierName[grantTier]}.`);
      await search();
      await loadStats();
    } catch (error) {
      toast.error(message(error, 'Chưa cấp được gói dịch vụ.'));
    } finally {
      setBusy(false);
    }
  };

  const revoke = async () => {
    if (!found || !window.confirm(`Thu hồi gói dịch vụ của ${found.user.email || found.user.uid}?`))
      return;
    setBusy(true);
    try {
      await adminBillingRevoke(found.user.uid);
      toast.success('Đã thu hồi gói, tài khoản chuyển về Miễn phí.');
      await search();
      await loadStats();
    } catch (error) {
      toast.error(message(error, 'Chưa thu hồi được gói.'));
    } finally {
      setBusy(false);
    }
  };

  const savePromo = async () => {
    if (!draft) return;
    const percent = Number(draft.percentOff);
    if (!Number.isInteger(percent) || percent < 1 || percent > 100) {
      toast.error('Mức chiết khấu phải là số nguyên từ 1% đến 100%.');
      return;
    }
    if (!draft.validTo) {
      toast.error('Cần chọn ngày hết hạn hiệu lực.');
      return;
    }
    if (!draft.tiers.length || !draft.periods.length) {
      toast.error('Chọn ít nhất một gói cước và một kỳ hạn áp dụng.');
      return;
    }
    const maxUses = draft.maxUses.trim() ? Number(draft.maxUses) : null;
    if (maxUses !== null && (!Number.isInteger(maxUses) || maxUses < 1)) {
      toast.error('Số lượt tối đa phải là số nguyên từ 1 trở lên (để trống = không giới hạn).');
      return;
    }
    setBusy(true);
    try {
      const validTo = new Date(`${draft.validTo}T23:59:59+07:00`).toISOString();
      const validFrom = draft.validFrom
        ? new Date(`${draft.validFrom}T00:00:00+07:00`).toISOString()
        : undefined;
      const res = await adminCreatePromo({
        code: draft.code.trim().toUpperCase() || undefined,
        percentOff: percent,
        validTo,
        validFrom,
        tiers: draft.tiers,
        periods: draft.periods,
        maxUses,
        note: draft.note.trim(),
      });
      toast.success(`Đã tạo thành công mã khuyến mại ${res?.data?.code || draft.code}.`);
      setDraft(null);
      await loadPromos();
    } catch (error) {
      toast.error(message(error, 'Chưa tạo được mã khuyến mại.'));
    } finally {
      setBusy(false);
    }
  };

  const togglePromo = async (promo: Promo) => {
    try {
      await adminUpdatePromo(promo.code, { active: !promo.active });
      toast.success(
        promo.active
          ? `Đã tạm dừng mã ${promo.code}`
          : `Đã kích hoạt lại mã ${promo.code}`
      );
      await loadPromos();
    } catch (error) {
      toast.error(message(error, 'Chưa cập nhật được mã khuyến mại.'));
    }
  };

  const toggle = (list: string[], value: string) =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];

  return (
    <div className="space-y-5">
      {/* Page Header */}
      <div className="page-header flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-[22px] font-semibold tracking-tight text-[var(--text-primary)]">
          Gói & Khuyến mại
        </h1>
        <Button
          variant="outline"
          size="sm"
          onClick={() => void loadStats()}
          className="h-8 text-xs border-[var(--border-hairline)] bg-[var(--bg-surface)] hover:bg-[var(--bg-elevated)]"
        >
          <RefreshCw className="mr-1.5 h-3.5 w-3.5" />
          Làm mới
        </Button>
      </div>

      {!enforced && (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-300">
          Chế độ kiểm soát gói đang TẮT (`BILLING_ENFORCED=false`).
        </div>
      )}

      {/* SECTION: PLAN STATUS, SUBSCRIBERS COUNTER & ABNORMALITY LOCKDOWN */}
      <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
        <CardHeader className="pb-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
            <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)] flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 text-amber-400" />
              Các gói dịch vụ hiện hành
            </CardTitle>
            <span className="text-[11px] text-[var(--text-secondary)] self-start sm:self-auto">
              Đếm người dùng trực tiếp từ Firestore
            </span>
          </div>
        </CardHeader>
        <CardContent className="p-5">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {plansCatalog.map((plan) => {
              return (
                <div
                  key={plan.key}
                  className="relative rounded-2xl border p-4 flex flex-col justify-between transition-all border-[var(--border-hairline)] bg-[var(--bg-canvas)] hover:border-[var(--accent-primary)]/40"
                >
                  <div className="space-y-3">
                    {/* Top Row: Plan name & Status */}
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <h3 className={`font-bold text-sm ${plan.tone}`}>{plan.name}</h3>
                        <p className="text-xs font-semibold text-[var(--text-primary)] mt-0.5 tabular-nums whitespace-nowrap">
                          {plan.price}
                        </p>
                      </div>
                    </div>

                    {/* Active subscribers count */}
                    <div className="rounded-xl bg-[var(--bg-surface)] p-2.5 border border-[var(--border-hairline)]">
                      <div className="text-[10px] uppercase font-semibold text-[var(--text-muted)] tracking-wider">
                        Đang dùng
                      </div>
                      <div className="text-xl font-bold tabular-nums text-[var(--text-primary)] mt-0.5 flex items-baseline gap-1.5">
                        <span>{plan.subscribers.toLocaleString('vi-VN')}</span>
                        <span className="text-[11px] font-normal text-[var(--text-muted)]">tài khoản</span>
                      </div>
                    </div>

                    <details className="text-[11px] text-[var(--text-secondary)]">
                      <summary className="cursor-pointer text-[var(--accent-primary)] hover:underline list-none font-medium">
                        Xem chi tiết quyền lợi ▾
                      </summary>
                      <p className="mt-1.5 text-[var(--text-muted)] leading-relaxed">
                        {plan.description}
                      </p>
                    </details>
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
      <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
        <CardHeader className="pb-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]">
          <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)] flex items-center gap-2">
            <Crown className="w-4 h-4 text-[var(--accent-primary)]" />
            Cấp / điều chỉnh gói cho tài khoản
          </CardTitle>
        </CardHeader>
        <CardContent className="p-5 space-y-4">
          <div className="flex gap-2 max-w-xl">
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-muted)]" />
              <Input
                className="pl-9 h-9 text-xs bg-[var(--bg-canvas)] border-[var(--border-hairline)]"
                placeholder="Nhập email hoặc UID tài khoản..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') void search();
                }}
              />
            </div>
            <Button
              onClick={() => void search()}
              disabled={busy}
              size="sm"
              className="h-9 px-4 text-xs bg-[var(--accent-primary)] text-white font-semibold hover:bg-[var(--accent-hover)]"
            >
              Tìm kiếm
            </Button>
          </div>

          {found && (
            <div className="space-y-4 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-elevated)] p-4">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[var(--border-hairline)] pb-3">
                <div>
                  <p className="font-semibold text-xs text-[var(--text-primary)]">
                    {found.user.email || found.user.uid}
                  </p>
                  <p className="text-[11px] text-[var(--text-muted)] font-mono">{found.user.uid}</p>
                </div>
                <div className="flex items-center gap-2">
                  <PlanBadge planName={tierName[found.plan.tier]} />
                  {found.plan.status === 'trial' && (
                    <StatusBadge label="Dùng thử" tone="warning" dot={false} />
                  )}
                  {found.plan.expiresAt && (
                    <span className="text-xs text-[var(--text-muted)] tabular-nums">
                      Hết hạn: {day(found.plan.expiresAt)}
                    </span>
                  )}
                </div>
              </div>

              {found.pendingPromo && (
                <div className="text-xs text-[var(--text-muted)] flex items-center gap-2">
                  <span>Mã khuyến mại đã nhập:</span>
                  <CopyChip value={found.pendingPromo.code} head={6} tail={4} />
                  <span className="text-[var(--accent-primary)] font-semibold">
                    (−{found.pendingPromo.percentOff}%)
                  </span>
                </div>
              )}

              {/* Action Controls */}
              <div className="flex flex-wrap items-end gap-3 pt-1">
                <label className="text-xs font-medium text-[var(--text-primary)]">
                  Gói dịch vụ
                  <select
                    className="mt-1 block h-8 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2.5 text-xs text-[var(--text-primary)]"
                    value={grantTier}
                    onChange={(e) => setGrantTier(e.target.value as 'pro' | 'ultra')}
                  >
                    <option value="pro">Pinova Pro</option>
                    <option value="ultra">Pinova Ultra</option>
                  </select>
                </label>

                <label className="text-xs font-medium text-[var(--text-primary)]">
                  Thời hạn
                  <select
                    className="mt-1 block h-8 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2.5 text-xs text-[var(--text-primary)]"
                    value={grantPeriod}
                    onChange={(e) =>
                      setGrantPeriod(e.target.value as 'month' | 'year' | 'days')
                    }
                  >
                    <option value="month">1 tháng (30 ngày)</option>
                    <option value="year">1 năm (365 ngày)</option>
                    <option value="days">Số ngày tùy chọn…</option>
                  </select>
                </label>

                {grantPeriod === 'days' && (
                  <label className="text-xs font-medium text-[var(--text-primary)]">
                    Số ngày
                    <Input
                      className="mt-1 h-8 w-24 text-xs font-mono border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                      type="number"
                      min={1}
                      max={730}
                      value={grantDays}
                      onChange={(e) => setGrantDays(e.target.value)}
                    />
                  </label>
                )}

                <Button
                  onClick={() => void grant()}
                  disabled={busy}
                  size="sm"
                  className="h-8 text-xs bg-[var(--accent-primary)] text-slate-950 font-semibold hover:bg-[var(--accent-hover)]"
                >
                  <Sparkles className="mr-1.5 h-3.5 w-3.5" />
                  Cấp / Gia hạn gói
                </Button>

                {found.plan.tier !== 'free' && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => void revoke()}
                    disabled={busy}
                    className="h-8 text-xs border-rose-500/30 text-rose-400 hover:bg-rose-500/10"
                  >
                    <Ban className="mr-1.5 h-3.5 w-3.5" />
                    Thu hồi về Miễn phí
                  </Button>
                )}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* QA 145: MoMo payment orders */}
      <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
        <CardHeader className="pb-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
            <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)] flex items-center gap-2">
              <Crown className="w-4 h-4 text-[var(--accent-primary)]" />
              Giao dịch MoMo
            </CardTitle>
            <div className="flex flex-wrap items-center gap-2 text-[11px] text-[var(--text-secondary)]">
              {revenue && (
                <span className="tabular-nums">
                  Doanh thu {revenue.month}: <strong className="text-[var(--text-primary)]">{vnd(revenue.amount)}</strong>
                </span>
              )}
              {revenue && (
                <StatusBadge
                  label={!revenue.momo ? 'MoMo đang tắt' : revenue.sandbox ? 'MoMo thử nghiệm' : 'MoMo thật'}
                  tone={!revenue.momo ? 'neutral' : revenue.sandbox ? 'warning' : 'success'}
                />
              )}
              <select
                className="h-7 rounded border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2 text-xs"
                value={orderFilter}
                onChange={(e) => setOrderFilter(e.target.value)}
                aria-label="Lọc trạng thái"
              >
                <option value="">Tất cả</option>
                {Object.entries(orderStatus).map(([key, item]) => (
                  <option key={key} value={key}>
                    {item.label}
                  </option>
                ))}
              </select>
              <Button
                variant="outline"
                size="sm"
                onClick={() => void loadOrders(orderFilter)}
                className="h-7 text-xs border-[var(--border-hairline)]"
              >
                <RefreshCw className="mr-1 h-3 w-3" />
                Làm mới
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="text-[11px] text-[var(--text-muted)] text-left">
                <tr className="border-b border-[var(--border-hairline)]">
                  <th className="px-4 py-2 font-medium">Thời gian</th>
                  <th className="px-4 py-2 font-medium">Mã đơn</th>
                  <th className="px-4 py-2 font-medium">Tài khoản</th>
                  <th className="px-4 py-2 font-medium">Gói</th>
                  <th className="px-4 py-2 font-medium text-right">Số tiền</th>
                  <th className="px-4 py-2 font-medium">Trạng thái</th>
                  <th className="px-4 py-2 font-medium">Mã MoMo</th>
                  <th className="px-4 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-hairline)]">
                {orders.map((o) => (
                  <tr key={o.orderId} className="hover:bg-[var(--bg-hover)]">
                    <td className="px-4 py-2 tabular-nums whitespace-nowrap">{day(o.paidAt || o.createdAt)}</td>
                    <td className="px-4 py-2">
                      <CopyChip value={o.orderId} head={8} tail={6} />
                    </td>
                    <td className="px-4 py-2">
                      <CopyChip value={o.uid} head={6} tail={4} />
                    </td>
                    <td className="px-4 py-2 whitespace-nowrap">
                      {tierName[o.tier]} · {o.period === 'year' ? 'năm' : 'tháng'}
                      {o.promoCode ? ` · ${o.promoCode}` : ''}
                      {o.credit ? ` · quy đổi ${vnd(o.credit)}` : ''}
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums font-medium">{vnd(o.amount)}</td>
                    <td className="px-4 py-2">
                      <StatusBadge label={orderStatus[o.status]?.label || o.status} tone={orderStatus[o.status]?.tone || 'neutral'} />
                      {o.needsReview && <span className="ml-1 text-amber-400">(tài khoản đã ở gói cao hơn)</span>}
                      {o.reviewReason === 'amountMismatch' && <span className="ml-1 text-rose-400">(sai số tiền)</span>}
                    </td>
                    <td className="px-4 py-2 tabular-nums">{o.transId ?? '—'}</td>
                    <td className="px-4 py-2 text-right whitespace-nowrap">
                      {o.status === 'pending' && (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy}
                          onClick={() => void checkOrder(o)}
                          className="h-7 text-xs border-[var(--border-hairline)]"
                        >
                          Hỏi lại MoMo
                        </Button>
                      )}
                      {o.status === 'paid' && o.method === 'momo' && (
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy}
                          onClick={() => void refundOrder(o)}
                          className="h-7 text-xs border-rose-500/40 text-rose-300"
                        >
                          Hoàn tiền
                        </Button>
                      )}
                    </td>
                  </tr>
                ))}
                {orders.length === 0 && (
                  <tr>
                    <td colSpan={8} className="p-8 text-center text-[var(--text-muted)]">
                      Chưa có giao dịch.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {/* Promotion Campaigns Section */}
      <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
        <CardHeader className="flex flex-row items-center justify-between gap-4 pb-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]">
          <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)] flex items-center gap-2">
            <Gift className="w-4 h-4 text-[var(--accent-primary)]" />
            Mã khuyến mại ({promos.length})
          </CardTitle>
          {!draft && (
            <Button
              size="sm"
              onClick={() =>
                setDraft({
                  code: '',
                  percentOff: '20',
                  validFrom: '',
                  validTo: '',
                  tiers: ['pro', 'ultra'],
                  periods: ['month', 'year'],
                  maxUses: '',
                  note: '',
                })
              }
              className="text-xs h-8 bg-[var(--accent-primary)] text-white font-semibold hover:bg-[var(--accent-hover)]"
            >
              <Plus className="w-3.5 h-3.5 mr-1" />
              Tạo mã mới
            </Button>
          )}
        </CardHeader>

        <CardContent className="p-5 space-y-4">
          {/* Create Promo Form */}
          {draft && (
            <div className="p-4 rounded-xl border border-[var(--accent-primary)]/40 bg-[var(--bg-elevated)] space-y-4 animate-modal-enter">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-[var(--text-primary)]">
                  Thiết lập mã khuyến mại mới
                </span>
                <button
                  type="button"
                  onClick={() => setDraft(null)}
                  className="text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                >
                  Hủy bỏ
                </button>
              </div>

              <div className="grid gap-3 sm:grid-cols-5">
                <div>
                  <label className="block text-[11px] font-medium text-[var(--text-muted)] mb-1">
                    Mã code (Tự động in hoa)
                  </label>
                  <Input
                    className="h-8 text-xs font-mono uppercase border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                    placeholder="VD: PINOVA2026"
                    value={draft.code}
                    onChange={(e) =>
                      setDraft((d) => (d ? { ...d, code: e.target.value.toUpperCase() } : null))
                    }
                  />
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-[var(--text-muted)] mb-1">
                    Mức giảm giá (%)
                  </label>
                  <Input
                    className="h-8 text-xs tabular-nums border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                    type="number"
                    min={1}
                    max={100}
                    placeholder="20"
                    value={draft.percentOff}
                    onChange={(e) =>
                      setDraft((d) => (d ? { ...d, percentOff: e.target.value } : null))
                    }
                  />
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-[var(--text-muted)] mb-1">
                    Bắt đầu hiệu lực (Tùy chọn)
                  </label>
                  <Input
                    className="h-8 text-xs border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                    type="date"
                    value={draft.validFrom}
                    onChange={(e) =>
                      setDraft((d) => (d ? { ...d, validFrom: e.target.value } : null))
                    }
                  />
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-[var(--text-muted)] mb-1">
                    Số lượt tối đa (trống = không giới hạn)
                  </label>
                  <Input
                    className="h-8 text-xs tabular-nums border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                    type="number"
                    min={1}
                    placeholder="Không giới hạn"
                    value={draft.maxUses}
                    onChange={(e) =>
                      setDraft((d) => (d ? { ...d, maxUses: e.target.value } : null))
                    }
                  />
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-[var(--text-muted)] mb-1">
                    Ngày hết hạn (Bắt buộc)
                  </label>
                  <Input
                    className="h-8 text-xs border-[var(--border-hairline)] bg-[var(--bg-canvas)]"
                    type="date"
                    value={draft.validTo}
                    onChange={(e) =>
                      setDraft((d) => (d ? { ...d, validTo: e.target.value } : null))
                    }
                  />
                </div>
              </div>

              {/* Tiers & Periods selection */}
              <div className="flex flex-wrap items-center justify-between gap-4 border-t border-[var(--border-hairline)] pt-3">
                <div className="flex flex-wrap items-center gap-4 text-xs">
                  <div className="flex items-center gap-2">
                    <span className="text-[var(--text-muted)]">Gói:</span>
                    {(['pro', 'ultra'] as const).map((t) => (
                      <button
                        key={t}
                        type="button"
                        onClick={() =>
                          setDraft((d) =>
                            d ? { ...d, tiers: toggle(d.tiers, t) as ('pro' | 'ultra')[] } : null
                          )
                        }
                        className={`px-2 py-0.5 rounded border text-[11px] font-medium ${
                          draft.tiers.includes(t)
                            ? 'border-[var(--accent-primary)] bg-[var(--accent-tint)] text-[var(--accent-primary)]'
                            : 'border-[var(--border-hairline)] text-[var(--text-muted)]'
                        }`}
                      >
                        {tierName[t]}
                      </button>
                    ))}
                  </div>

                  <div className="flex items-center gap-2">
                    <span className="text-[var(--text-muted)]">Kỳ hạn:</span>
                    {(['month', 'year'] as const).map((p) => (
                      <button
                        key={p}
                        type="button"
                        onClick={() =>
                          setDraft((d) =>
                            d
                              ? {
                                  ...d,
                                  periods: toggle(d.periods, p) as ('month' | 'year')[],
                                }
                              : null
                          )
                        }
                        className={`px-2 py-0.5 rounded border text-[11px] font-medium ${
                          draft.periods.includes(p)
                            ? 'border-[var(--accent-primary)] bg-[var(--accent-tint)] text-[var(--accent-primary)]'
                            : 'border-[var(--border-hairline)] text-[var(--text-muted)]'
                        }`}
                      >
                        {p === 'month' ? 'Tháng' : 'Năm'}
                      </button>
                    ))}
                  </div>
                </div>

                <Button
                  size="sm"
                  onClick={() => void savePromo()}
                  disabled={busy}
                  className="h-8 text-xs bg-[var(--accent-primary)] text-slate-950 font-semibold hover:bg-[var(--accent-hover)]"
                >
                  Lưu & Kích hoạt mã
                </Button>
              </div>
            </div>
          )}

          {/* List Promos */}
          <div className="divide-y divide-[var(--border-hairline)] border border-[var(--border-hairline)] rounded-xl overflow-hidden">
            {promos.map((p) => (
              <div
                key={p.code}
                className="flex flex-wrap items-center justify-between gap-3 p-3.5 bg-[var(--bg-surface)] hover:bg-[var(--bg-hover)] transition-colors"
              >
                <div className="flex items-center gap-3">
                  <CopyChip value={p.code} head={10} tail={4} />
                  <span className="text-xs font-bold text-[var(--accent-primary)] tabular-nums">
                    Giảm {p.percentOff}%
                  </span>
                  <StatusBadge
                    label={p.active ? 'Đang hoạt động' : 'Tạm dừng'}
                    tone={p.active ? 'success' : 'neutral'}
                  />
                </div>

                <div className="flex items-center gap-4 text-xs text-[var(--text-muted)]">
                  <span className="tabular-nums">
                    Hiệu lực: {day(p.validFrom)} → {day(p.validTo)}
                  </span>
                  <span className="tabular-nums font-medium text-[var(--text-primary)]">
                    {p.uses ?? 0}
                    {p.maxUses ? `/${p.maxUses}` : ''} lượt dùng · 1 lần/tài khoản
                  </span>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => void togglePromo(p)}
                    className="h-7 text-xs border-[var(--border-hairline)]"
                  >
                    {p.active ? 'Tạm dừng' : 'Kích hoạt'}
                  </Button>
                </div>
              </div>
            ))}

            {promos.length === 0 && (
              <div className="p-8 text-center text-xs text-[var(--text-muted)]">
                Chưa có chiến dịch mã khuyến mại nào được tạo.
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
