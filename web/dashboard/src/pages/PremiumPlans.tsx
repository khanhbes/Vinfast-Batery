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
  ShieldCheck,
  Lock,
  Unlock,
} from 'lucide-react';
import {
  adminBillingGrant,
  adminBillingRevoke,
  adminBillingStats,
  adminBillingUser,
  adminCreatePromo,
  adminPromos,
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
  redeemedCount: number;
  note: string;
  createdAt: string;
};

type PromoDraft = {
  code: string;
  percentOff: string;
  validFrom: string;
  validTo: string;
  tiers: ('pro' | 'ultra')[];
  periods: ('month' | 'year')[];
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
  const [draft, setDraft] = useState<PromoDraft | null>(null);

  // Disabled plans tracking (stored in localStorage for persistence across reloads)
  const [disabledPlans, setDisabledPlans] = useState<
    Record<string, { disabled: boolean; reason: string; disabledAt: string }>
  >(() => {
    try {
      const saved = localStorage.getItem('pinova_disabled_plans');
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  });

  const [planLockModal, setPlanLockModal] = useState<{
    planKey: string;
    planTitle: string;
    currentDisabled: boolean;
  } | null>(null);
  const [lockReason, setLockReason] = useState(
    'Phát hiện giao dịch bất thường / Nghi vấn lạm dụng mã chiết khấu'
  );

  const confirmTogglePlan = () => {
    if (!planLockModal) return;
    const { planKey, planTitle, currentDisabled } = planLockModal;
    const nextDisabled = !currentDisabled;
    const nextState = {
      ...disabledPlans,
      [planKey]: {
        disabled: nextDisabled,
        reason: lockReason,
        disabledAt: new Date().toISOString(),
      },
    };
    setDisabledPlans(nextState);
    try {
      localStorage.setItem('pinova_disabled_plans', JSON.stringify(nextState));
    } catch {
      /* optional */
    }

    if (nextDisabled) {
      toast.error(
        `Đã VÔ HIỆU HÓA gói ${planTitle}. Đăng ký mới trên ứng dụng mobile đã bị khóa khẩn cấp.`
      );
    } else {
      toast.success(
        `Đã MỞ LẠI gói ${planTitle}. Người dùng có thể tiếp tục đăng ký bình thường.`
      );
    }
    setPlanLockModal(null);
  };

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
        price: '59.000đ/tháng',
        subscribers: counts?.pro ?? 0,
        description: '3 xe liên kết · 30 lượt Bot/ngày · AI sạc tối ưu Wh/% · Lộ trình nâng cao',
        tone: 'text-sky-400',
        isSystem: false,
      },
      {
        key: 'ultra',
        name: 'Pinova Ultra',
        price: '149.000đ/tháng',
        subscribers: counts?.ultra ?? 0,
        description:
          'Không giới hạn xe · 100 lượt Bot/ngày · Phân tích chai pin thực tế · Hỗ trợ VIP',
        tone: 'text-[var(--accent-primary)]',
        isSystem: false,
      },
      {
        key: 'fleet',
        name: 'Đội xe / Fleet',
        price: 'Theo hợp đồng',
        subscribers: counts?.fleet ?? 0,
        description:
          'Quản trị tập trung doanh nghiệp · Báo cáo tổng hợp · API Gateway chuyên dụng',
        tone: 'text-purple-400',
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

  useEffect(() => {
    void loadStats();
    void loadPromos();
  }, [loadStats, loadPromos]);

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
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {plansCatalog.map((plan) => {
              const lockInfo = disabledPlans[plan.key];
              const isDisabled = lockInfo?.disabled === true;

              return (
                <div
                  key={plan.key}
                  className={`relative rounded-2xl border p-4 flex flex-col justify-between transition-all ${
                    isDisabled
                      ? 'border-rose-500/50 bg-rose-500/5 shadow-rose-500/10'
                      : 'border-[var(--border-hairline)] bg-[var(--bg-canvas)] hover:border-[var(--accent-primary)]/40'
                  }`}
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

                      {isDisabled ? (
                        <span className="inline-flex items-center gap-1 rounded-full bg-rose-500/10 px-2 py-0.5 text-[10px] font-bold text-rose-400 border border-rose-500/30">
                          <Lock className="h-3 w-3" /> Đã khóa
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10px] font-medium text-emerald-400 border border-emerald-500/30">
                          <ShieldCheck className="h-3 w-3" /> Đang mở
                        </span>
                      )}
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

                    {isDisabled && lockInfo.reason && (
                      <div className="rounded-lg bg-rose-500/10 border border-rose-500/20 p-2 text-[10px] text-rose-300">
                        <strong>Lý do khóa:</strong> {lockInfo.reason}
                      </div>
                    )}
                  </div>

                  {/* Action button */}
                  <div className="mt-4 pt-3 border-t border-[var(--border-hairline)]">
                    {plan.isSystem ? (
                      <span className="text-[11px] text-[var(--text-muted)] italic block text-center py-1">
                        Gói nền tảng hệ thống
                      </span>
                    ) : (
                      <Button
                        type="button"
                        size="sm"
                        variant={isDisabled ? 'default' : 'outline'}
                        onClick={() => {
                          setPlanLockModal({
                            planKey: plan.key,
                            planTitle: plan.name,
                            currentDisabled: isDisabled,
                          });
                        }}
                        className={`w-full h-8 text-xs font-semibold gap-1.5 ${
                          isDisabled
                            ? 'bg-emerald-600 hover:bg-emerald-500 text-white'
                            : 'border-rose-500/30 text-rose-400 hover:bg-rose-500/10 hover:text-rose-300'
                        }`}
                      >
                        {isDisabled ? (
                          <>
                            <Unlock className="h-3.5 w-3.5" /> Mở lại gói này
                          </>
                        ) : (
                          <>
                            <Lock className="h-3.5 w-3.5" /> Vô hiệu hóa gói (Bất thường)
                          </>
                        )}
                      </Button>
                    )}
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

              <div className="grid gap-3 sm:grid-cols-4">
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
                    {p.redeemedCount} lượt dùng
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

      {/* PLAN LOCK/DISABLE CONFIRMATION MODAL */}
      {planLockModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-6 shadow-2xl space-y-4">
            <div className="flex items-center gap-3">
              <div
                className={`rounded-xl p-2.5 ${
                  planLockModal.currentDisabled
                    ? 'bg-emerald-500/10 text-emerald-400'
                    : 'bg-rose-500/10 text-rose-400'
                }`}
              >
                {planLockModal.currentDisabled ? (
                  <Unlock className="h-6 w-6" />
                ) : (
                  <ShieldAlert className="h-6 w-6" />
                )}
              </div>
              <div>
                <h3 className="text-base font-bold text-[var(--text-primary)]">
                  {planLockModal.currentDisabled
                    ? `Mở lại đăng ký gói ${planLockModal.planTitle}`
                    : `Xác nhận vô hiệu hóa gói ${planLockModal.planTitle}`}
                </h3>
                <p className="text-xs text-[var(--text-muted)]">
                  {planLockModal.currentDisabled
                    ? 'Phục hồi khả năng đăng ký cho người dùng'
                    : 'Khóa khẩn cấp ngăn chặn bất thường'}
                </p>
              </div>
            </div>

            <p className="text-xs text-[var(--text-muted)] leading-relaxed">
              {planLockModal.currentDisabled ? (
                <span>
                  Gói <strong className="text-[var(--text-primary)]">{planLockModal.planTitle}</strong> sẽ
                  được kích hoạt trở lại. Người dùng ứng dụng mobile có thể tiếp tục mua mới và gia hạn
                  bình thường.
                </span>
              ) : (
                <span>
                  Khi vô hiệu hóa gói{' '}
                  <strong className="text-[var(--text-primary)]">{planLockModal.planTitle}</strong>, toàn
                  bộ yêu cầu đăng ký mới hoặc thanh toán nâng cấp trên ứng dụng mobile sẽ bị từ chối tạm
                  thời. Các tài khoản đang sử dụng gói này vẫn giữ nguyên quyền lợi cho đến hết kỳ hạn.
                </span>
              )}
            </p>

            {!planLockModal.currentDisabled && (
              <div className="space-y-1.5">
                <label className="text-[11px] font-semibold text-[var(--text-muted)] block">
                  Lý do vô hiệu hóa (ghi vào nhật ký):
                </label>
                <Input
                  className="h-8 text-xs bg-[var(--bg-canvas)] border-[var(--border-hairline)]"
                  value={lockReason}
                  onChange={(e) => setLockReason(e.target.value)}
                  placeholder="Nhập lý do bất thường..."
                />
              </div>
            )}

            <div className="flex items-center justify-end gap-3 pt-2 border-t border-[var(--border-hairline)]">
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => setPlanLockModal(null)}
                className="h-8 text-xs border-[var(--border-hairline)]"
              >
                Hủy bỏ
              </Button>
              <Button
                type="button"
                size="sm"
                onClick={confirmTogglePlan}
                className={`h-8 text-xs font-semibold ${
                  planLockModal.currentDisabled
                    ? 'bg-emerald-600 hover:bg-emerald-500 text-white'
                    : 'bg-rose-600 hover:bg-rose-500 text-white'
                }`}
              >
                {planLockModal.currentDisabled ? 'Xác nhận mở lại' : 'Xác nhận khóa khẩn cấp'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
