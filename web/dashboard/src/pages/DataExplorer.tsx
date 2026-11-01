import { useEffect, useMemo, useState, useCallback } from 'react';
import {
  Activity,
  BatteryCharging,
  BrainCircuit,
  Car,
  Copy,
  Database,
  Download,
  Eye,
  History,
  RefreshCw,
  Search,
  UserRound,
  Wrench,
} from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { StatusBadge } from '@/components/common/StatusBadge';
import { CopyChip } from '@/components/common/CopyChip';
import { EntityDrawer } from '@/components/common/EntityDrawer';
import { datasetItems, recordId, type DataRecord, useAdminData } from '@/data/AdminDataContext';

const datasetDefinitions = [
  { key: 'accounts', label: 'Tài khoản', group: 'users', icon: UserRound, description: 'Tài khoản Firebase Auth hợp nhất với hồ sơ ứng dụng.' },
  { key: 'vehicles', label: 'Phương tiện xe', group: 'users', icon: Car, description: 'Danh sách xe máy điện người dùng đã đăng ký vào app.' },
  { key: 'vehicleSpecs', label: 'Thông số catalog', group: 'users', icon: Car, description: 'Thông số định mức tiêu chuẩn từ danh mục xe VinFast.' },
  { key: 'chargeLogs', label: 'Lịch sử sạc', group: 'charging', icon: BatteryCharging, description: 'Các phiên sạc pin hoàn tất và đang hoạt động.' },
  { key: 'smartChargeTelemetry', label: 'Telemetry phiên sạc', group: 'charging', icon: Activity, description: 'Dữ liệu đo đạc chi tiết (W, Wh, V, SoC) từ cổng sạc Shelly.' },
  { key: 'tripLogs', label: 'Hành trình di chuyển', group: 'charging', icon: History, description: 'Quãng đường, tiêu thụ năng lượng và ODO theo chuyến đi.' },
  { key: 'legacyTripLogs', label: 'Hành trình cũ (Legacy)', group: 'charging', icon: History, description: 'Dữ liệu chuyến đi lịch sử duy trì tương thích ngược.' },
  { key: 'telemetry', label: 'Telemetry chuẩn hóa', group: 'charging', icon: Activity, description: 'Dữ liệu đo đạc chuẩn battery-telemetry/v1.' },
  { key: 'batteryStates', label: 'Trạng thái pin', group: 'charging', icon: BatteryCharging, description: 'Ảnh chụp trạng thái pin và SoH đồng bộ gần nhất.' },
  { key: 'maintenance', label: 'Lịch bảo dưỡng', group: 'ops', icon: Wrench, description: 'Kế hoạch và lịch sử bảo dưỡng theo định kỳ ODO.' },
  { key: 'aiInsights', label: 'Đánh giá AI (Insights)', group: 'ai', icon: BrainCircuit, description: 'Điểm sức khỏe pin và phân tích hành vi lái xe.' },
  { key: 'aiProfiles', label: 'Hồ sơ AI cá nhân', group: 'ai', icon: BrainCircuit, description: 'Điều kiện và trạng thái mô hình học máy cá nhân hóa.' },
  { key: 'aiDeployments', label: 'Triển khai mô hình AI', group: 'ai', icon: BrainCircuit, description: 'Trạng thái phiên bản mô hình và canary deployment.' },
  { key: 'tripPredictions', label: 'Dự đoán hành trình', group: 'ai', icon: BrainCircuit, description: 'Ước tính tiêu hao pin và tầm hoạt động cho lộ trình.' },
  { key: 'socPredictions', label: 'Dự đoán SoC pin', group: 'ai', icon: BrainCircuit, description: 'Lịch sử ước tính phần trăm pin theo thời gian thực.' },
  { key: 'smartChargingSessions', label: 'Phiên sạc Cloud', group: 'charging', icon: BatteryCharging, description: 'Phiên điều khiển sạc thông minh qua Azure Cloud.' },
  { key: 'chargingTrainingSamples', label: 'Mẫu huấn luyện sạc', group: 'ai', icon: Database, description: 'Quan sát sạc thực tế dùng cho fine-tune mô hình sạc.' },
  { key: 'chargeSamples', label: 'Mẫu đo đạc sạc', group: 'charging', icon: Database, description: 'Dữ liệu phân giải cao ghi nhận trong lúc sạc.' },
  { key: 'chargeFeedback', label: 'Phản hồi sạc thực tế', group: 'ai', icon: Database, description: 'Độ lệch thời gian và năng lượng dùng để đánh giá mô hình.' },
  { key: 'smartChargePreferences', label: 'Cấu hình sạc người dùng', group: 'ops', icon: BatteryCharging, description: 'Mục tiêu % pin và hẹn giờ tự ngắt theo từng xe.' },
  { key: 'vehicleChargerBindings', label: 'Liên kết thiết bị sạc', group: 'ops', icon: BatteryCharging, description: 'Ánh xạ giữa xe máy điện và cổng sạc Shelly.' },
  { key: 'notifications', label: 'Thông báo app', group: 'ops', icon: Activity, description: 'Lịch sử thông báo đẩy gửi về thiết bị di động.' },
  { key: 'auditLogs', label: 'Nhật ký bảo mật', group: 'ops', icon: History, description: 'Bản ghi kiểm toán thao tác quản trị từ backend.' },
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
  if (typeof value === 'boolean') return value ? 'Có' : 'Không';
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : value.toFixed(2);
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function labelFor(field: string): string {
  return field
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/_/g, ' ')
    .replace(/^./, (value) => value.toUpperCase());
}

export default function DataExplorer() {
  const { snapshot, loading, refreshing, refresh, loadDataset } = useAdminData();
  const [params, setParams] = useSearchParams();
  const requested = params.get('dataset');
  const activeKey = datasetDefinitions.some((item) => item.key === requested)
    ? requested!
    : 'vehicles';
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<DataRecord | null>(null);

  const accounts = datasetItems(snapshot, 'accounts');
  const ownerNames = useMemo(
    () =>
      new Map(
        accounts.map((account) => {
          const uid = String(account.uid || account.ownerUid || '');
          return [uid, String(account.displayName || account.email || uid)];
        })
      ),
    [accounts]
  );

  const definition = datasetDefinitions.find((item) => item.key === activeKey)!;
  const records = datasetItems(snapshot, activeKey);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return records;
    return records.filter((record) =>
      JSON.stringify(record).toLowerCase().includes(query)
    );
  }, [records, search]);

  const columns = useMemo(() => {
    const preferred = preferredColumns[activeKey] ?? [];
    const available = new Set(records.flatMap((record) => Object.keys(record)));
    const chosen = preferred.filter((column) => available.has(column));
    if (chosen.length >= 3) return chosen.slice(0, 6);
    return Array.from(available)
      .filter((key) => !['isDeleted', 'deletedAt', 'deletedBy'].includes(key))
      .slice(0, 6);
  }, [activeKey, records]);

  const currentDataset = snapshot?.datasets[activeKey];
  const datasetError = snapshot?.errorDetails?.[activeKey];
  const quotaExceeded = Object.values(snapshot?.errorDetails ?? {}).some(
    (item) => item.code === 'firestoreQuotaExceeded'
  );

  useEffect(() => {
    if (!loading && !currentDataset) void loadDataset(activeKey);
  }, [activeKey, currentDataset, loadDataset, loading]);

  const exportCurrentCsv = useCallback(() => {
    if (filtered.length === 0) return;
    const allKeys = Array.from(new Set(filtered.flatMap((r) => Object.keys(r))));
    const headers = allKeys.map(labelFor);
    const rows = filtered.map((record) =>
      allKeys.map((key) => {
        const val = record[key];
        if (val == null) return '""';
        return `"${String(typeof val === 'object' ? JSON.stringify(val) : val).replace(/"/g, '""')}"`;
      })
    );
    const csvContent = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${activeKey}-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }, [activeKey, filtered]);

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Database className="h-5 w-5 text-emerald-500" />
            <span className="text-xs font-semibold uppercase tracking-wider text-emerald-500">
              Không gian dữ liệu Firebase
            </span>
          </div>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Trình khám phá dữ liệu (Data Explorer)
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Khám phá 23 tập dữ liệu Firestore được đồng bộ toàn diện giữa ứng dụng di động Pinova và máy chủ backend.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={exportCurrentCsv}
            disabled={filtered.length === 0}
            className="h-9 gap-2 text-xs"
          >
            <Download className="h-4 w-4 text-emerald-500" />
            Xuất CSV
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => void refresh()}
            disabled={refreshing}
            className="h-9 gap-2 text-xs"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            Làm mới Snapshot
          </Button>
        </div>
      </div>

      {/* Quota warning */}
      {snapshot?.partial && (
        <div
          role="status"
          className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-4 text-xs text-amber-300"
        >
          <p className="font-semibold text-amber-200">
            {quotaExceeded
              ? 'Hạn mức đọc Firestore trong ngày đã chạm trần'
              : 'Một số tập dữ liệu chưa tải được đầy đủ'}
          </p>
          <p className="mt-1 text-muted-foreground">
            Dữ liệu đã nạp sẵn trong cache vẫn tiếp tục hiển thị bình thường.
          </p>
        </div>
      )}

      {/* Summary KPI Cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Tài khoản</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-foreground">
                {snapshot?.totals.accounts ?? 0}
              </p>
            </div>
            <div className="rounded-xl border border-border/60 bg-elevated/80 p-2.5 text-muted-foreground">
              <UserRound className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Phương tiện xe</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-500">
                {snapshot?.totals.vehicles ?? 0}
              </p>
            </div>
            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-2.5 text-emerald-500">
              <Car className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Bản ghi sạc</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-sky-400">
                {snapshot?.totals.chargeLogs ?? 0}
              </p>
            </div>
            <div className="rounded-xl border border-sky-400/20 bg-sky-400/10 p-2.5 text-sky-400">
              <BatteryCharging className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Bản ghi AI & Telemetry</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-violet-400">
                {(snapshot?.totals.aiInsights ?? 0) +
                  (snapshot?.totals.aiProfiles ?? 0) +
                  (snapshot?.totals.tripPredictions ?? 0) +
                  (snapshot?.totals.socPredictions ?? 0)}
              </p>
            </div>
            <div className="rounded-xl border border-violet-400/20 bg-violet-400/10 p-2.5 text-violet-400">
              <BrainCircuit className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Main 2-column Layout */}
      <div className="grid gap-6 lg:grid-cols-[16rem_minmax(0,1fr)]">
        {/* Left Navigation: Datasets list */}
        <nav
          aria-label="Tập dữ liệu"
          className="flex gap-1.5 overflow-x-auto pb-2 thin-scrollbar lg:block lg:space-y-1 lg:overflow-visible"
        >
          {datasetDefinitions.map(({ key, label, icon: Icon }) => {
            const active = key === activeKey;
            const total = snapshot?.totals[key] ?? 0;
            return (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setParams({ dataset: key });
                  setSelected(null);
                }}
                className={`flex w-full items-center justify-between gap-2.5 rounded-xl px-3 py-2.5 text-left text-xs transition-colors shrink-0 ${
                  active
                    ? 'bg-emerald-500/15 text-emerald-400 font-semibold border border-emerald-500/30'
                    : 'text-muted-foreground hover:bg-surface hover:text-foreground border border-transparent'
                }`}
              >
                <div className="flex items-center gap-2.5 truncate">
                  <Icon className={`h-4 w-4 shrink-0 ${active ? 'text-emerald-400' : 'opacity-70'}`} />
                  <span className="truncate">{label}</span>
                </div>
                <span className="font-mono text-[11px] tabular-nums opacity-75">{total}</span>
              </button>
            );
          })}
        </nav>

        {/* Right Content Area */}
        <div className="min-w-0 space-y-4">
          {/* Header & Search */}
          <div className="flex flex-col gap-3 rounded-xl border border-border/60 bg-surface/50 p-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-foreground">{definition.label}</h2>
                <StatusBadge label={`${records.length} bản ghi`} tone="primary" dot={false} />
              </div>
              <p className="mt-0.5 text-xs text-muted-foreground">{definition.description}</p>
            </div>
            <div className="relative w-full sm:w-64">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Tìm trong tập dữ liệu..."
                className="h-8 pl-8 pr-3 text-xs bg-canvas border-border/60"
              />
            </div>
          </div>

          {/* Table Container */}
          <div className="rounded-xl border border-border/60 bg-surface/50 overflow-hidden shadow-xs">
            {loading && !snapshot ? (
              <div className="py-16 text-center text-xs text-muted-foreground">
                <RefreshCw className="mx-auto mb-2 h-5 w-5 animate-spin text-emerald-500" />
                Đang nạp dữ liệu đồng bộ...
              </div>
            ) : datasetError && !currentDataset ? (
              <div className="py-16 text-center text-xs">
                <Database className="mx-auto mb-2 h-7 w-7 text-rose-500" />
                <p className="font-semibold text-foreground">Không thể tải tập dữ liệu này</p>
                <p className="mt-1 text-muted-foreground">{datasetError.message}</p>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => void loadDataset(activeKey)}
                  className="mt-3 h-8 text-xs"
                >
                  Thử lại
                </Button>
              </div>
            ) : filtered.length === 0 ? (
              <div className="py-16 text-center text-xs text-muted-foreground">
                <Database className="mx-auto mb-2 h-7 w-7 opacity-50" />
                <p className="font-semibold text-foreground">Không có bản ghi nào</p>
                <p className="mt-1 text-muted-foreground">
                  {records.length
                    ? 'Không tìm thấy kết quả phù hợp với từ khóa tìm kiếm.'
                    : 'Tập dữ liệu này hiện chưa có bản ghi.'}
                </p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[700px] text-xs">
                  <thead>
                    <tr className="border-b border-border/60 bg-canvas/40 text-left text-muted-foreground">
                      {columns.map((column) => (
                        <th key={column} className="px-3 py-2.5 font-medium">
                          {labelFor(column)}
                        </th>
                      ))}
                      <th className="px-3 py-2.5 text-right font-medium w-[70px]">Chi tiết</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border/40">
                    {filtered.map((record, index) => {
                      const id = recordId(record) || String(index);
                      return (
                        <tr
                          key={`${id}:${index}`}
                          onClick={() => setSelected(record)}
                          className="hover:bg-muted/30 cursor-pointer transition-colors"
                        >
                          {columns.map((column) => {
                            const val = record[column];
                            const isUid =
                              column === 'ownerUid' || column === 'uid' || column === 'actorUid';
                            const isId = column.endsWith('Id') || column === 'id';

                            return (
                              <td key={column} className="px-3 py-2.5 max-w-[200px] truncate">
                                {isUid && typeof val === 'string' && val ? (
                                  <div className="flex flex-col">
                                    <span className="font-medium text-foreground truncate">
                                      {ownerNames.get(val) || val}
                                    </span>
                                    <CopyChip value={val} head={8} tail={4} />
                                  </div>
                                ) : isId && typeof val === 'string' && val ? (
                                  <CopyChip value={val} head={8} tail={4} />
                                ) : typeof val === 'boolean' ? (
                                  <StatusBadge
                                    label={val ? 'Có' : 'Không'}
                                    tone={val ? 'success' : 'neutral'}
                                    dot={false}
                                  />
                                ) : (
                                  <span className="text-foreground/90 font-mono text-[11px]">
                                    {textValue(val)}
                                  </span>
                                )}
                              </td>
                            );
                          })}
                          <td className="px-3 py-2 text-right">
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={(e) => {
                                e.stopPropagation();
                                setSelected(record);
                              }}
                              className="h-7 w-7 p-0 text-muted-foreground hover:text-foreground"
                            >
                              <Eye className="h-3.5 w-3.5" />
                            </Button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {/* Table Footer */}
            <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border/60 bg-canvas/30 px-3 py-2 text-[11px] text-muted-foreground">
              <span>
                Hiển thị <span className="font-semibold text-foreground">{filtered.length}</span> / {records.length} bản ghi
              </span>
              <span>
                {snapshot?.generatedAt
                  ? `Snapshot: ${new Date(snapshot.generatedAt).toLocaleString('vi-VN')}`
                  : 'Chưa tải snapshot'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Record Details Drawer */}
      <EntityDrawer
        open={Boolean(selected)}
        onClose={() => setSelected(null)}
        title="Chi tiết bản ghi dữ liệu"
        subtitle={selected ? `Tập dữ liệu: ${definition.label}` : undefined}
        badge={
          selected ? (
            <StatusBadge label={recordId(selected) || 'Bản ghi'} tone="primary" dot={false} />
          ) : undefined
        }
        footer={
          <div className="flex items-center justify-between w-full">
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                if (selected) {
                  void navigator.clipboard.writeText(JSON.stringify(selected, null, 2));
                }
              }}
              className="h-9 gap-2 text-xs"
            >
              <Copy className="h-3.5 w-3.5" />
              Sao chép JSON
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setSelected(null)}
              className="h-9 text-xs"
            >
              Đóng
            </Button>
          </div>
        }
      >
        {selected && (
          <div className="space-y-4">
            {/* Owner account if known */}
            {Boolean(selected.ownerUid) && (
              <div className="rounded-xl border border-border/60 bg-surface/50 p-3.5 flex items-center justify-between">
                <span className="text-xs text-muted-foreground">Tài khoản sở hữu:</span>
                <span className="text-xs font-semibold text-foreground">
                  {ownerNames.get(String(selected.ownerUid)) || String(selected.ownerUid)}
                </span>
              </div>
            )}

            {/* Fields list */}
            <div className="rounded-xl border border-border/60 bg-surface/50 p-3.5 space-y-2.5">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                Danh sách trường dữ liệu
              </p>
              {Object.entries(selected)
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([key, value]) => (
                  <div
                    key={key}
                    className="grid grid-cols-[10rem_1fr] items-start gap-2 border-b border-border/30 pb-2 last:border-0 last:pb-0"
                  >
                    <span className="text-xs font-medium text-muted-foreground truncate">
                      {labelFor(key)}
                    </span>
                    <span className="break-all font-mono text-xs text-foreground/90 leading-relaxed">
                      {textValue(value)}
                    </span>
                  </div>
                ))}
            </div>

            {/* Raw JSON */}
            <div className="rounded-xl border border-border/60 bg-surface/50 p-3.5 space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Dữ liệu JSON gốc
              </p>
              <pre className="max-h-60 overflow-y-auto rounded-lg border border-border/60 bg-canvas p-3 font-mono text-xs text-foreground/90 thin-scrollbar leading-relaxed">
                {JSON.stringify(selected, null, 2)}
              </pre>
            </div>
          </div>
        )}
      </EntityDrawer>
    </div>
  );
}
