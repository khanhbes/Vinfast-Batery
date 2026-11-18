import { useEffect, useMemo, useState } from 'react';
import {
  Activity,
  AlertTriangle,
  ArrowUpRight,
  BrainCircuit,
  Car,
  CheckCircle2,
  Clock3,
  Cpu,
  CreditCard,
  Database,
  LifeBuoy,
  RefreshCw,
  Route,
  Users,
  Zap,
} from 'lucide-react';
import { motion } from 'motion/react';
import { useNavigate } from 'react-router-dom';
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { adminBillingStats } from '@/api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ResponsiveText } from '@/components/ui/ResponsiveText';
import { datasetItems, type DataRecord, useAdminData } from '@/data/AdminDataContext';
import { useDevelopMode } from '@/data/DevelopModeContext';
import { StatusBadge } from '@/components/common/StatusBadge';
import { EntityDrawer } from '@/components/common/EntityDrawer';

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

type ChartMetricKey = 'users' | 'charges';
type TimeRangeKey = '7d' | '30d' | '90d';

export default function Dashboard() {
  const navigate = useNavigate();
  const { enabled: developMode } = useDevelopMode();
  const { snapshot, loading, refreshing, error, refresh } = useAdminData();

  const [timeRange, setTimeRange] = useState<TimeRangeKey>('30d');
  const [chartMetric, setChartMetric] = useState<ChartMetricKey>('users');
  const [selectedActivity, setSelectedActivity] = useState<{
    kind: string;
    item: DataRecord;
    at: number;
    label: string;
  } | null>(null);

  const accounts = datasetItems(snapshot, 'accounts');
  const vehicles = datasetItems(snapshot, 'vehicles');
  const chargeLogs = datasetItems(snapshot, 'chargeLogs');
  const trips = datasetItems(snapshot, 'tripLogs');
  const maintenance = datasetItems(snapshot, 'maintenance');
  const aiInsights = datasetItems(snapshot, 'aiInsights');
  const aiProfiles = datasetItems(snapshot, 'aiProfiles');
  const predictions = [...datasetItems(snapshot, 'tripPredictions'), ...datasetItems(snapshot, 'socPredictions')];
  const supportTickets = datasetItems(snapshot, 'support');
  const shellyDevices = datasetItems(snapshot, 'shelly');

  const datasetLoaded = (key: string) => Boolean(snapshot?.datasets[key]);
  const count = (key: string) => (datasetLoaded(key) ? datasetItems(snapshot, key).length : '—');

  const summary = useMemo(() => {
    const sohValues = vehicles
      .map((v) => firstNumber(v, ['stateOfHealth', 'soh']))
      .filter((v): v is number => v !== null && v >= 0 && v <= 100);
    const avgSoh = sohValues.length ? sohValues.reduce((s, v) => s + v, 0) / sohValues.length : null;

    const lowBattery = vehicles.filter((v) => {
      const soc = firstNumber(v, ['currentBattery', 'lastBatteryPercent', 'soc']);
      return soc !== null && soc < 20;
    });

    const attentionMaintenance = maintenance.filter((task) =>
      ['overdue', 'pending'].includes(String(task.status || '').toLowerCase())
    );

    const energyWh = chargeLogs.reduce(
      (sum, log) => sum + (firstNumber(log, ['energyWh', 'energyConsumedWh', 'energy', 'totalEnergyWh']) ?? 0),
      0
    );

    const offlineShelly = shellyDevices.filter((d) => d.online === false);
    const onlineShelly = shellyDevices.filter((d) => d.online !== false);
    const pendingTickets = supportTickets.filter((t) => String(t.status || '').toLowerCase() === 'open');

    return {
      avgSoh,
      lowBattery,
      attentionMaintenance,
      energyWh,
      offlineShelly,
      onlineShelly,
      pendingTickets,
    };
  }, [vehicles, chargeLogs, maintenance, shellyDevices, supportTickets]);

  // Only real records: new accounts and charge sessions per day (or per week for 90 days).
  const chartData = useMemo(() => {
    const days = timeRange === '7d' ? 7 : timeRange === '30d' ? 30 : 90;
    const bucketDays = days === 90 ? 7 : 1;
    const buckets = Math.ceil(days / bucketDays);
    const dayMs = 86_400_000;
    const end = new Date();
    end.setHours(23, 59, 59, 999);
    const start = end.getTime() - buckets * bucketDays * dayMs;
    const points = Array.from({ length: buckets }, (_, index) => ({
      period: new Date(start + (index * bucketDays + 1) * dayMs).toLocaleDateString('vi-VN', {
        day: '2-digit',
        month: '2-digit',
      }),
      users: 0,
      charges: 0,
    }));
    const place = (time: number, key: 'users' | 'charges') => {
      if (!time || time < start || time > end.getTime()) return;
      const index = Math.min(buckets - 1, Math.floor((time - start) / (bucketDays * dayMs)));
      points[index][key] += 1;
    };
    for (const account of accounts) {
      const raw = account.createdAt ?? account.creationTime;
      const time = typeof raw === 'number' ? raw : Date.parse(String(raw ?? ''));
      place(Number.isFinite(time) ? time : 0, 'users');
    }
    for (const log of chargeLogs) place(timestamp(log), 'charges');
    return points;
  }, [accounts, chargeLogs, timeRange]);

  const [paidPlans, setPaidPlans] = useState<{ pro: number; ultra: number; trial: number } | null>(null);
  useEffect(() => {
    let alive = true;
    adminBillingStats()
      .then((res: { data?: { counts?: Record<string, number> } }) => {
        const c = res?.data?.counts;
        if (alive && c) setPaidPlans({ pro: c.pro ?? 0, ultra: c.ultra ?? 0, trial: c.trial ?? 0 });
      })
      .catch(() => {
        if (alive) setPaidPlans(null);
      });
    return () => {
      alive = false;
    };
  }, []);

  const vehicleDistribution = useMemo(() => {
    if (vehicles.length === 0) return [];
    const map = new Map<string, number>();
    for (const v of vehicles) {
      const label =
        firstText(v, ['vinfastModelName', 'vehicleName', 'model', 'catalogId']) || 'Chưa đặt tên';
      map.set(label, (map.get(label) || 0) + 1);
    }
    const total = vehicles.length;
    return Array.from(map.entries())
      .map(([model, cnt]) => ({
        model,
        count: cnt,
        pct: Math.round((cnt / total) * 100),
      }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 5);
  }, [vehicles]);

  const recentActivity = useMemo(() => {
    return [
      ...chargeLogs.map((item) => ({
        kind: 'Charge',
        item,
        at: timestamp(item),
        label: firstText(item, ['vehicleId', 'sessionId', 'id']),
      })),
      ...trips.map((item) => ({
        kind: 'Trip',
        item,
        at: timestamp(item),
        label: firstText(item, ['vehicleId', 'tripId', 'id']),
      })),
      ...predictions.map((item) => ({
        kind: 'AI prediction',
        item,
        at: timestamp(item),
        label: firstText(item, ['vehicleId', 'modelVersion', 'id']),
      })),
    ]
      .sort((a, b) => b.at - a.at)
      .slice(0, 6);
  }, [chargeLogs, trips, predictions]);

  const metrics = [
    { label: 'Tài khoản', value: count('accounts'), icon: Users, action: () => navigate('/users') },
    { label: 'Xe', value: count('vehicles'), icon: Car, action: () => navigate('/data?dataset=vehicles') },
    { label: 'Phiên sạc', value: count('chargeLogs'), icon: Zap, action: () => navigate('/data?dataset=chargeLogs') },
    { label: 'Chuyến đi', value: count('tripLogs'), icon: Route, action: () => navigate('/data?dataset=tripLogs') },
    { label: 'Số đo', value: count('telemetry'), icon: Activity, action: () => navigate('/data?dataset=telemetry') },
    {
      label: 'Dữ liệu AI',
      value: datasetLoaded('aiInsights') ? aiInsights.length + aiProfiles.length + predictions.length : '—',
      icon: BrainCircuit,
      action: () => navigate('/data?dataset=aiInsights'),
    },
  ];

  if (loading && !snapshot) {
    return (
      <div className="space-y-6 animate-fadeIn">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="space-y-2">
            <div className="skeleton-shimmer h-7 w-36 rounded-lg" />
            <div className="skeleton-shimmer h-3.5 w-64 rounded-md" />
          </div>
          <div className="flex gap-2">
            <div className="skeleton-shimmer h-8 w-44 rounded-lg" />
            <div className="skeleton-shimmer h-8 w-24 rounded-lg" />
          </div>
        </div>
        <div className="skeleton-shimmer h-12 w-full rounded-xl" />
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          {Array.from({ length: 4 }).map((_, index) => (
            <div key={index} className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5 space-y-3">
              <div className="skeleton-shimmer h-3.5 w-28 rounded-md" />
              <div className="skeleton-shimmer h-8 w-20 rounded-lg" />
              <div className="skeleton-shimmer h-3 w-36 rounded-md" />
            </div>
          ))}
        </div>
        <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5 space-y-4">
          <div className="flex justify-between">
            <div className="skeleton-shimmer h-5 w-40 rounded-md" />
            <div className="skeleton-shimmer h-7 w-36 rounded-lg" />
          </div>
          <div className="skeleton-shimmer h-64 w-full rounded-xl" />
        </div>
      </div>
    );
  }

  const shellyKnown = datasetLoaded('shelly');
  const totalShellyCount = shellyDevices.length;
  const onlineShellyCount = summary.onlineShelly.length;

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="page-header flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-[22px] font-semibold tracking-tight text-[var(--text-primary)]">
            Tổng quan
          </h1>
          {developMode && (
            <p className="mt-1 max-w-3xl text-xs text-[var(--text-muted)]">
              Dữ liệu quản trị thời gian thực từ cùng hệ sinh thái với ứng dụng điện thoại Pinova.
            </p>
          )}
        </div>

        <div className="flex items-center gap-2">
          {/* Segmented Time Filter */}
          <div className="inline-flex items-center p-0.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-hairline)]">
            {(
              [
                ['7d', '7 ngày'],
                ['30d', '30 ngày'],
                ['90d', '90 ngày'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                type="button"
                onClick={() => setTimeRange(key)}
                className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                  timeRange === key
                    ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold'
                    : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          <Button
            onClick={() => void refresh()}
            disabled={refreshing}
            variant="outline"
            size="sm"
            className="h-8 gap-2 text-xs border-[var(--border-hairline)] bg-[var(--bg-surface)] hover:bg-[var(--bg-elevated)]"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${refreshing ? 'animate-spin text-[var(--accent-primary)]' : ''}`} />
            Làm mới
          </Button>
        </div>
      </div>

      {error && (
        <div
          role="alert"
          className="flex items-start gap-3 rounded-xl border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-400"
        >
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-rose-400" />
          <span>{error}</span>
        </div>
      )}

      {snapshot?.cache?.stale?.length ? (
        <div
          role="status"
          className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-300"
        >
          Đang hiển thị dữ liệu lưu tạm cho {snapshot.cache.stale.join(', ')} trong khi máy chủ kết nối lại.
        </div>
      ) : null}

      {/* TẦNG 1: DẢI CẦN XỬ LÝ NGAY (Actionable Inbox Strip) */}
      <div className="p-3 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] flex flex-wrap items-center justify-between gap-3 text-xs">
        <div className="flex items-center gap-2 text-[var(--text-primary)] font-semibold shrink-0">
          <span className="w-2 h-2 rounded-full bg-[var(--accent-primary)]" />
          <span>Cần xử lý ngay</span>
        </div>
        <div className="flex flex-wrap items-center gap-2 flex-1">
          <button
            type="button"
            onClick={() => navigate('/shelly')}
            className="hover-pill inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--bg-elevated)] hover:bg-[var(--bg-hover)] border border-[var(--border-hairline)] text-[var(--text-primary)]"
          >
            <span
              className={`w-1.5 h-1.5 rounded-full ${
                summary.offlineShelly.length > 0 ? 'bg-rose-500' : 'bg-emerald-500'
              }`}
            />
            <span>
              {summary.offlineShelly.length > 0
                ? `${summary.offlineShelly.length} thiết bị Shelly mất kết nối`
                : shellyKnown
                ? `${onlineShellyCount}/${totalShellyCount} trạm Shelly đang kết nối`
                : 'Thiết bị Shelly'}
            </span>
            <span className="text-[var(--accent-primary)] font-medium">Kiểm tra →</span>
          </button>

          <button
            type="button"
            onClick={() => navigate('/catalog')}
            className="hover-pill inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--bg-elevated)] hover:bg-[var(--bg-hover)] border border-[var(--border-hairline)] text-[var(--text-primary)]"
          >
            <Car className="w-3.5 h-3.5 text-[var(--accent-primary)]" />
            <span>Danh mục xe</span>
            <span className="text-[var(--accent-primary)] font-medium">Mở Studio →</span>
          </button>

          <button
            type="button"
            onClick={() => navigate('/support')}
            className="hover-pill inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--bg-elevated)] hover:bg-[var(--bg-hover)] border border-[var(--border-hairline)] text-[var(--text-primary)]"
          >
            <LifeBuoy className="w-3.5 h-3.5 text-amber-400" />
            <span>
              {summary.pendingTickets.length > 0
                ? `${summary.pendingTickets.length} phiếu hỗ trợ đang chờ`
                : 'Hộp thư hỗ trợ'}
            </span>
            <span className="text-[var(--accent-primary)] font-medium">Hộp thư →</span>
          </button>
        </div>
      </div>

      {/* TẦNG 2: 4 KPI CHÍNH (Stripe / Linear Hierarchy) */}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <div
          onClick={() => navigate('/users')}
          className="group hover-lift cursor-pointer rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5"
        >
          <div className="flex items-center justify-between text-xs text-[var(--text-secondary)]">
            <span className="font-medium">Tài khoản hoạt động</span>
            <Users className="w-4 h-4 text-[var(--text-muted)] group-hover:text-[var(--accent-primary)] transition-colors" />
          </div>
          <div className="mt-3 flex items-baseline justify-between gap-2">
            <span className="text-[28px] font-semibold tabular-nums tracking-tight text-[var(--text-primary)]">
              {datasetLoaded('accounts') ? accounts.length : '—'}
            </span>
          </div>
          <p className="mt-2 text-xs text-[var(--text-muted)] flex items-center justify-between">
            <span>Xem danh sách tài khoản</span>
            <ArrowUpRight className="w-3.5 h-3.5 transition-transform group-hover:translate-x-0.5 group-hover:-translate-y-0.5 group-hover:text-[var(--accent-primary)]" />
          </p>
        </div>

        <div
          onClick={() => navigate('/premium')}
          className="group hover-lift cursor-pointer rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5"
        >
          <div className="flex items-center justify-between text-xs text-[var(--text-secondary)]">
            <span className="font-medium">Gói trả phí đang dùng</span>
            <CreditCard className="w-4 h-4 text-[var(--text-muted)] group-hover:text-[var(--accent-primary)] transition-colors" />
          </div>
          <div className="mt-3 flex items-baseline justify-between gap-2">
            <span className="text-[28px] font-semibold tabular-nums tracking-tight text-[var(--text-primary)] whitespace-nowrap">
              {paidPlans ? paidPlans.pro + paidPlans.ultra : '—'}
            </span>
          </div>
          <p className="mt-2 text-xs text-[var(--text-muted)] tabular-nums">
            {paidPlans
              ? `Pro ${paidPlans.pro} · Ultra ${paidPlans.ultra}${paidPlans.trial ? ` · Dùng thử ${paidPlans.trial}` : ''}`
              : 'Chưa có dữ liệu gói'}
          </p>
        </div>

        <div
          onClick={() => navigate('/shelly')}
          className="group hover-lift cursor-pointer rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5"
        >
          <div className="flex items-center justify-between text-xs text-[var(--text-secondary)]">
            <span className="font-medium">Thiết bị Shelly trực tuyến</span>
            <Cpu className="w-4 h-4 text-[var(--text-muted)] group-hover:text-[var(--accent-primary)] transition-colors" />
          </div>
          <div className="mt-3 flex items-baseline justify-between gap-2">
            <span className="text-[28px] font-semibold tabular-nums tracking-tight text-[var(--text-primary)] whitespace-nowrap">
              {shellyKnown ? `${onlineShellyCount} / ${totalShellyCount}` : '—'}
            </span>
            {shellyKnown && (
              <StatusBadge
                label={summary.offlineShelly.length === 0 ? 'Đang kết nối' : `${summary.offlineShelly.length} mất kết nối`}
                tone={summary.offlineShelly.length === 0 ? 'success' : 'danger'}
              />
            )}
          </div>
          <p className="mt-2 text-xs text-[var(--text-muted)] tabular-nums">
            Tổng điện năng nạp:{' '}
            {summary.energyWh >= 1000
              ? `${(summary.energyWh / 1000).toFixed(1)} kWh`
              : `${summary.energyWh.toFixed(0)} Wh`}
          </p>
        </div>

        <div
          onClick={() => navigate('/support')}
          className="group hover-lift cursor-pointer rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5"
        >
          <div className="flex items-center justify-between text-xs text-[var(--text-secondary)]">
            <span className="font-medium">Phiếu hỗ trợ đang mở</span>
            <LifeBuoy className="w-4 h-4 text-[var(--text-muted)] group-hover:text-[var(--accent-primary)] transition-colors" />
          </div>
          <div className="mt-3 flex items-baseline justify-between gap-2">
            <span className="text-[28px] font-semibold tabular-nums tracking-tight text-[var(--text-primary)]">
              {datasetLoaded('support') ? summary.pendingTickets.length : '—'}
            </span>
            {summary.pendingTickets.length > 0 && (
              <StatusBadge label="Cần phản hồi" tone="warning" dot={false} />
            )}
          </div>
          <p className="mt-2 text-xs text-[var(--text-muted)] tabular-nums">
            Sức khỏe pin TB (SoH): {summary.avgSoh == null ? '—' : `${summary.avgSoh.toFixed(1)}%`}
          </p>
        </div>
      </div>

      {/* TẦNG 3: 1 BIỂU ĐỒ CHÍNH CÓ SEGMENTED CONTROL (Không trộn đơn vị) */}
      <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
        <CardHeader className="pb-2 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)]">
            Xu hướng hệ thống
            <span className="ml-2 text-[11px] font-normal text-[var(--text-muted)]">
              theo bản ghi đã tải
            </span>
          </CardTitle>

          <div className="inline-flex items-center p-0.5 rounded-lg bg-[var(--bg-canvas)] border border-[var(--border-hairline)] self-start">
            {(
              [
                ['users', 'Tài khoản mới'],
                ['charges', 'Phiên sạc'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                type="button"
                onClick={() => setChartMetric(key)}
                className={`px-3 py-1 rounded-md text-xs font-medium transition-colors whitespace-nowrap ${
                  chartMetric === key
                    ? 'bg-[var(--bg-surface)] text-[var(--accent-primary)] font-semibold shadow-xs'
                    : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </CardHeader>

        <CardContent className="pt-2">
          <div className="h-64 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData} margin={{ top: 10, right: 12, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="pinovaMetricGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#6366F1" stopOpacity={0.28} />
                    <stop offset="95%" stopColor="#6366F1" stopOpacity={0.0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(148, 163, 184, 0.08)" vertical={false} />
                <XAxis
                  dataKey="period"
                  tick={{ fill: '#9CA3B4', fontSize: 11 }}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  tick={{ fill: '#9CA3B4', fontSize: 11 }}
                  axisLine={false}
                  tickLine={false}
                  width={56}
                  allowDecimals={false}
                />
                <Tooltip
                  formatter={(val: unknown) => {
                    const num = Number(val ?? 0);
                    return [
                      chartMetric === 'users' ? `${num} tài khoản` : `${num} phiên`,
                      chartMetric === 'users' ? 'Tài khoản mới' : 'Phiên sạc',
                    ];
                  }}
                />
                <Area
                  type="monotone"
                  dataKey={chartMetric}
                  stroke="#6366F1"
                  strokeWidth={2}
                  fillOpacity={1}
                  fill="url(#pinovaMetricGradient)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          {developMode && <div className="mt-6 flex flex-wrap gap-2.5">
              <Button
                onClick={() => navigate('/data')}
                size="sm"
                className="bg-[var(--accent-primary)] text-white font-semibold hover:bg-[var(--accent-hover)] text-xs h-8"
              >
                <Database className="w-3.5 h-3.5 mr-1.5" />
                Xem toàn bộ dữ liệu
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => navigate('/ai')}
                className="border-[var(--border-strong)] bg-transparent text-[var(--text-primary)] hover:bg-[var(--bg-elevated)] text-xs h-8"
              >
                <BrainCircuit className="w-3.5 h-3.5 mr-1.5" />
                Mở trung tâm AI
              </Button>
            </div>}
        </CardContent>
      </Card>

      {/* TẦNG 4: PHÂN BỐ MẪU XE & HOẠT ĐỘNG GẦN ĐÂY (Tối đa 6 dòng) */}
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Left: Top Vehicle Distribution & Dataset Coverage */}
        <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
          <CardHeader className="pb-3 flex flex-row items-center justify-between">
            <CardTitle className="text-[15px] font-semibold text-[var(--text-primary)]">
              Phân bố phương tiện
            </CardTitle>
            <Badge variant={snapshot?.partial ? 'destructive' : 'secondary'} className="text-[11px]">
              {snapshot?.partial ? 'Chưa đầy đủ' : 'Đồng bộ 100%'}
            </Badge>
          </CardHeader>

          <CardContent className="space-y-4">
            {/* Horizontal Bars for Vehicles */}
            <div className="space-y-3">
              {vehicleDistribution.length === 0 && (
                <p className="py-4 text-center text-xs text-[var(--text-muted)]">Chưa có xe nào được liên kết.</p>
              )}
              {vehicleDistribution.map((item) => (
                <div key={item.model} className="space-y-1.5">
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-medium text-[var(--text-primary)]">{item.model}</span>
                    <span className="tabular-nums text-[var(--text-secondary)]">
                      {item.count} xe · {item.pct}%
                    </span>
                  </div>
                  <div className="h-2 w-full rounded-full bg-[var(--bg-elevated)] overflow-hidden">
                    <div
                      className="h-full rounded-full bg-[var(--accent-primary)] transition-all duration-300"
                      style={{ width: `${Math.max(8, item.pct)}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>

            {/* Collapsible 6 Dataset Quick Counters (Hidden until clicked, preserves portal-safety test invariant) */}
            <details className="pt-3 border-t border-[var(--border-hairline)] group">
              <summary className="cursor-pointer list-none flex items-center justify-between text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)]">
                <span>Thống kê số lượng bản ghi hệ thống</span>
                <span className="text-[11px] text-[var(--accent-primary)] font-medium">Xem chi tiết ▾</span>
              </summary>
              <div className="mt-3 grid grid-cols-3 sm:grid-cols-6 gap-2">
                {metrics.map((metric, index) => (
                  <motion.button
                    key={metric.label}
                    type="button"
                    disabled={!developMode && metric.label !== 'Tài khoản'}
                    onClick={metric.action}
                    initial={{ opacity: 0.85, y: 4 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: index * 0.03 }}
                    className="stat-card-interactive group rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-elevated)]/60 p-2.5 text-left transition-colors hover:bg-[var(--bg-elevated)] disabled:cursor-default"
                  >
                    <metric.icon className="h-3.5 w-3.5 text-[var(--accent-primary)]" />
                    <p className="mt-2 text-base font-semibold tabular-nums text-[var(--text-primary)]">
                      {metric.value}
                    </p>
                    <p className="text-[11px] text-[var(--text-secondary)] truncate">
                      {metric.label}
                    </p>
                  </motion.button>
                ))}
              </div>
            </details>
          </CardContent>
        </Card>

        {/* Right: Recent Activity (Max 6 items, click to view detail drawer) */}
        <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs">
          <CardHeader className="pb-3 flex flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-[15px] font-semibold text-[var(--text-primary)]">
              <Clock3 className="h-4 w-4 text-[var(--accent-primary)]" />
              Hoạt động gần đây
            </CardTitle>
            {summary.lowBattery.length === 0 && (
              <span className="inline-flex items-center gap-1 text-xs text-emerald-400 font-medium">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Pin an toàn
              </span>
            )}
          </CardHeader>

          <CardContent>
            {recentActivity.length === 0 ? (
              <div className="py-10 text-center text-xs text-[var(--text-muted)]">
                Chưa có hoạt động gần đây.
              </div>
            ) : (
              <div className="divide-y divide-[var(--border-hairline)]">
                {recentActivity.map((activity, index) => (
                  <div
                    key={`${activity.kind}:${activity.at}:${index}`}
                    onClick={() => setSelectedActivity(activity)}
                    className="group hover-row cursor-pointer flex min-h-11 w-full items-center gap-3 py-2 text-left rounded-lg px-2 -mx-2"
                  >
                    <span
                      className={`h-2 w-2 shrink-0 rounded-full ${
                        activity.kind === 'Charge'
                          ? 'bg-emerald-400'
                          : activity.kind === 'Trip'
                          ? 'bg-sky-400'
                          : 'bg-indigo-400'
                      }`}
                    />
                    <div className="min-w-0 flex-1 flex items-center justify-between gap-3">
                      <div className="min-w-0">
                        <span className="block text-xs font-medium text-[var(--text-primary)]">
                          {activity.kind === 'Charge'
                            ? 'Phiên sạc năng lượng'
                            : activity.kind === 'Trip'
                            ? 'Hành trình di chuyển'
                            : 'Dự đoán Pinova AI'}
                        </span>
                        <ResponsiveText
                          strategy="monoId"
                          className="block font-mono text-[11px] text-[var(--text-muted)]"
                          alwaysTooltip
                        >
                          {activity.label || '—'}
                        </ResponsiveText>
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <span className="text-[11px] text-[var(--text-secondary)] tabular-nums whitespace-nowrap">
                          {activity.at
                            ? new Date(activity.at).toLocaleString('vi-VN', {
                                dateStyle: 'short',
                                timeStyle: 'short',
                              })
                            : 'Vừa xong'}
                        </span>
                        <span className="hover-arrow inline-block text-[11px] text-[var(--accent-primary)] font-medium">
                          Chi tiết →
                        </span>
                      </div>
                    </div>
                    <button
                      type="button" disabled={!developMode} onClick={() =>
                        navigate(
                          `/data?dataset=${
                            activity.kind === 'Charge'
                              ? 'chargeLogs'
                              : activity.kind === 'Trip'
                              ? 'tripLogs'
                              : 'tripPredictions'
                          }`
                        )
                      }
                      className="sr-only"
                      aria-label="Mở bản ghi kỹ thuật"
                    />
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Activity Detail Drawer */}
      <EntityDrawer
        open={Boolean(selectedActivity)}
        onClose={() => setSelectedActivity(null)}
        title={
          selectedActivity?.kind === 'Charge'
            ? 'Chi tiết phiên sạc năng lượng'
            : selectedActivity?.kind === 'Trip'
            ? 'Chi tiết hành trình di chuyển'
            : 'Chi tiết dự đoán AI'
        }
        subtitle={selectedActivity?.label || '—'}
        badge={
          <StatusBadge
            label={selectedActivity?.kind === 'Charge' ? 'Đã ghi nhận' : 'Đồng bộ'}
            tone="success"
          />
        }
      >
        {selectedActivity && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2.5 text-xs">
              {Object.entries(selectedActivity.item)
                .filter(([, v]) => v !== null && v !== undefined && typeof v !== 'object')
                .slice(0, 8)
                .map(([k, v]) => (
                  <div
                    key={k}
                    className="p-3 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)]"
                  >
                    <span className="text-[11px] text-[var(--text-muted)] font-mono block">{k}</span>
                    <span className="font-semibold text-[var(--text-primary)] tabular-nums break-all mt-0.5 block">
                      {String(v)}
                    </span>
                  </div>
                ))}
            </div>
          </div>
        )}
      </EntityDrawer>
    </div>
  );
}
