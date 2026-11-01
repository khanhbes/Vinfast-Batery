import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  AlertCircle,
  Clock,
  Code,
  Copy,
  Eye,
  FileSpreadsheet,
  RefreshCw,
  Shield,
  ShieldAlert,
  Sparkles,
  User,
} from 'lucide-react';
import { adminAuditLogs } from '@/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { StatusBadge, type BadgeTone } from '@/components/common/StatusBadge';
import { CopyChip } from '@/components/common/CopyChip';
import { FilterBar, type FilterTabOption } from '@/components/common/FilterBar';
import { DataTableSurface, type ColumnDef } from '@/components/common/DataTableSurface';
import { EntityDrawer } from '@/components/common/EntityDrawer';

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

function formatTimestamp(value: unknown): string {
  const date = timestampValue(value);
  if (!date) return 'Không rõ';
  return new Intl.DateTimeFormat('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(date);
}

function actionKind(action: string): 'critical' | 'model' | 'data' {
  const normalized = action.toLowerCase();
  if (/delete|reset|revoke|disable|cancel|danger|purge/.test(normalized)) return 'critical';
  if (/model|train|deploy|rollback|upload|predict|canary/.test(normalized)) return 'model';
  return 'data';
}

function getActionTone(kind: 'critical' | 'model' | 'data'): BadgeTone {
  if (kind === 'critical') return 'danger';
  if (kind === 'model') return 'success';
  return 'neutral';
}

function detailsSummary(details: Record<string, unknown>): string {
  const entries = Object.entries(details ?? {});
  if (entries.length === 0) return 'Không có chi tiết bổ sung';
  return entries
    .slice(0, 3)
    .map(([key, value]) => `${key}: ${typeof value === 'object' ? JSON.stringify(value) : String(value)}`)
    .join(' · ');
}

export default function AuditSystem() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [density, setDensity] = useState<'comfortable' | 'compact'>('comfortable');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selectedLog, setSelectedLog] = useState<AuditLog | null>(null);
  const [copiedJson, setCopiedJson] = useState(false);

  const loadAuditLogs = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await adminAuditLogs();
      const data = Array.isArray(response?.data) ? response.data : [];
      setLogs(
        data.map((item: any, index: number): AuditLog => ({
          id: String(item.id ?? item._id ?? `audit-${index}`),
          action: String(item.action ?? 'unknown'),
          entity: String(item.entity ?? item.type ?? 'system'),
          entityId: String(item.entityId ?? item.version ?? '—'),
          actorUid: String(item.actorUid ?? item.actor ?? 'system'),
          actorEmail: String(item.actorEmail ?? ''),
          timestamp: item.timestamp ?? item.createdAt ?? null,
          details: item.details && typeof item.details === 'object' ? item.details : {},
        }))
      );
    } catch {
      setLogs([]);
      setError('Không thể tải nhật ký kiểm toán. Vui lòng kiểm tra quyền API và thử lại.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadAuditLogs();
  }, [loadAuditLogs]);

  const filteredLogs = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    return logs.filter((log) => {
      if (statusFilter !== 'all' && actionKind(log.action) !== statusFilter) return false;
      if (!query) return true;
      return [
        log.id,
        log.action,
        log.entity,
        log.entityId,
        log.actorUid,
        log.actorEmail,
        detailsSummary(log.details),
      ].some((value) => value.toLowerCase().includes(query));
    });
  }, [statusFilter, logs, searchQuery]);

  const counts = useMemo(
    () => ({
      all: logs.length,
      critical: logs.filter((l) => actionKind(l.action) === 'critical').length,
      model: logs.filter((l) => actionKind(l.action) === 'model').length,
      data: logs.filter((l) => actionKind(l.action) === 'data').length,
    }),
    [logs]
  );

  const filterTabs: FilterTabOption[] = useMemo(
    () => [
      { id: 'all', label: 'Tất cả', count: counts.all },
      { id: 'critical', label: 'Nhạy cảm', count: counts.critical },
      { id: 'model', label: 'AI & Mô hình', count: counts.model },
      { id: 'data', label: 'Dữ liệu', count: counts.data },
    ],
    [counts]
  );

  const exportCsv = useCallback(() => {
    const headers = ['Thời gian', 'Hành động', 'Phân loại', 'Người thực hiện', 'UID', 'Thực thể', 'Mã thực thể', 'Chi tiết'];
    const rows = filteredLogs.map((log) => [
      formatTimestamp(log.timestamp),
      log.action,
      actionKind(log.action),
      log.actorEmail || 'System',
      log.actorUid,
      log.entity,
      log.entityId,
      JSON.stringify(log.details).replace(/"/g, '""'),
    ]);
    const csvContent = [headers.join(','), ...rows.map((row) => row.map((cell) => `"${cell}"`).join(','))].join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `audit-logs-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }, [filteredLogs]);

  const copyDetailsJson = useCallback(() => {
    if (!selectedLog) return;
    void navigator.clipboard.writeText(JSON.stringify(selectedLog, null, 2));
    setCopiedJson(true);
    setTimeout(() => setCopiedJson(false), 2000);
  }, [selectedLog]);

  const columns: ColumnDef<AuditLog>[] = useMemo(
    () => [
      {
        key: 'timestamp',
        header: 'Thời gian',
        width: '180px',
        render: (log) => (
          <div className="flex items-center gap-2">
            <Clock className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
            <span className="font-mono text-xs tabular-nums text-foreground/90">
              {formatTimestamp(log.timestamp)}
            </span>
          </div>
        ),
      },
      {
        key: 'action',
        header: 'Hành động',
        width: '180px',
        render: (log) => {
          const cat = actionKind(log.action);
          return (
            <StatusBadge
              label={log.action}
              tone={getActionTone(cat)}
              dot={cat === 'critical'}
            />
          );
        },
      },
      {
        key: 'actor',
        header: 'Người thực hiện',
        render: (log) => (
          <div className="flex flex-col gap-1">
            <div className="flex items-center gap-1.5 text-sm font-medium text-foreground">
              <User className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
              <span>{log.actorEmail || 'Hệ thống (System)'}</span>
            </div>
            <CopyChip value={log.actorUid} head={8} tail={4} />
          </div>
        ),
      },
      {
        key: 'entity',
        header: 'Thực thể tác động',
        render: (log) => (
          <div className="flex flex-col gap-1">
            <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {log.entity}
            </span>
            <CopyChip value={log.entityId} head={10} tail={6} />
          </div>
        ),
      },
      {
        key: 'details',
        header: 'Nội dung chi tiết',
        render: (log) => (
          <p
            className="text-xs text-muted-foreground line-clamp-2 max-w-sm"
            title={detailsSummary(log.details)}
          >
            {detailsSummary(log.details)}
          </p>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-[22px] font-semibold tracking-tight text-foreground flex items-center gap-2">
          <Shield className="h-5 w-5 text-[var(--accent-primary)]" />
          <span>Nhật ký & Bảo mật</span>
        </h1>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={exportCsv}
            disabled={filteredLogs.length === 0}
            className="h-8 gap-1.5 text-xs"
          >
            <FileSpreadsheet className="h-3.5 w-3.5 text-[var(--accent-primary)]" />
            Xuất CSV
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => void loadAuditLogs()}
            disabled={loading}
            className="h-8 gap-1.5 text-xs"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />
            Làm mới
          </Button>
        </div>
      </div>

      {/* KPI Stat Cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Tổng số sự kiện</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-foreground">{counts.all}</p>
            </div>
            <div className="rounded-xl border border-border/60 bg-elevated/80 p-2.5 text-muted-foreground">
              <Activity className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Thao tác nhạy cảm</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-rose-500">{counts.critical}</p>
            </div>
            <div className="rounded-xl border border-rose-500/20 bg-rose-500/10 p-2.5 text-rose-500">
              <ShieldAlert className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">AI & Mô hình</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-500">{counts.model}</p>
            </div>
            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-2.5 text-emerald-500">
              <Sparkles className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Thay đổi dữ liệu</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-sky-400">{counts.data}</p>
            </div>
            <div className="rounded-xl border border-sky-400/20 bg-sky-400/10 p-2.5 text-sky-400">
              <Code className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Error state */}
      {error && (
        <div
          role="alert"
          className="flex items-start gap-3 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm"
        >
          <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
          <div className="flex-1">
            <p className="font-semibold text-foreground">Không thể tải nhật ký</p>
            <p className="mt-1 text-muted-foreground">{error}</p>
          </div>
          <Button variant="outline" size="sm" onClick={() => void loadAuditLogs()}>
            Thử lại
          </Button>
        </div>
      )}

      {/* FilterBar */}
      <FilterBar
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
        searchPlaceholder="Tìm kiếm hành động, tài khoản, thực thể, mã ID..."
        statusTabs={filterTabs}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        density={density}
        onDensityChange={setDensity}
        onRefresh={() => void loadAuditLogs()}
        onExportCsv={exportCsv}
      />

      {/* DataTableSurface */}
      <DataTableSurface
        data={filteredLogs}
        columns={columns}
        keyExtractor={(log) => log.id}
        loading={loading}
        density={density}
        emptyMessage={
          logs.length
            ? 'Không tìm thấy sự kiện phù hợp với bộ lọc hiện tại.'
            : 'Hệ thống chưa ghi nhận thao tác quản trị nào từ backend.'
        }
        onRowClick={(log) => setSelectedLog(log)}
        rowActions={(log) => (
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setSelectedLog(log)}
            className="h-8 gap-1.5 px-2.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <Eye className="h-3.5 w-3.5" />
            Xem
          </Button>
        )}
      />

      {/* EntityDrawer for Event Details */}
      <EntityDrawer
        open={Boolean(selectedLog)}
        onClose={() => setSelectedLog(null)}
        title="Chi tiết sự kiện kiểm toán"
        subtitle={selectedLog ? `Mã sự kiện: ${selectedLog.id}` : undefined}
        badge={
          selectedLog ? (
            <StatusBadge
              label={selectedLog.action}
              tone={getActionTone(actionKind(selectedLog.action))}
              dot={actionKind(selectedLog.action) === 'critical'}
            />
          ) : undefined
        }
        footer={
          <div className="flex items-center justify-between w-full">
            <Button
              variant="outline"
              size="sm"
              onClick={copyDetailsJson}
              className="h-9 gap-2 text-xs"
            >
              <Copy className="h-3.5 w-3.5" />
              {copiedJson ? 'Đã sao chép!' : 'Sao chép JSON'}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setSelectedLog(null)}
              className="h-9 text-xs"
            >
              Đóng
            </Button>
          </div>
        }
      >
        {selectedLog && (
          <div className="space-y-6">
            {/* Meta Card */}
            <div className="rounded-xl border border-border/60 bg-surface/50 p-4 space-y-3">
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground font-medium">Thời điểm diễn ra</span>
                <span className="font-mono tabular-nums text-foreground">
                  {formatTimestamp(selectedLog.timestamp)}
                </span>
              </div>
              <div className="h-px bg-border/40" />
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground font-medium">Hành động</span>
                <span className="font-semibold text-foreground">{selectedLog.action}</span>
              </div>
              <div className="h-px bg-border/40" />
              <div className="flex items-center justify-between text-xs">
                <span className="text-muted-foreground font-medium">Phân loại</span>
                <span className="capitalize text-foreground font-medium">
                  {actionKind(selectedLog.action)}
                </span>
              </div>
            </div>

            {/* Actor Information */}
            <div className="rounded-xl border border-border/60 bg-surface/50 p-4 space-y-3">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Người thực hiện (Actor)
              </p>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">Email:</span>
                  <span className="text-xs font-medium text-foreground">
                    {selectedLog.actorEmail || 'Hệ thống (System)'}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">Actor UID:</span>
                  <CopyChip value={selectedLog.actorUid} head={10} tail={6} />
                </div>
              </div>
            </div>

            {/* Target Entity */}
            <div className="rounded-xl border border-border/60 bg-surface/50 p-4 space-y-3">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Đối tượng chịu tác động (Entity)
              </p>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">Loại thực thể:</span>
                  <span className="text-xs font-semibold uppercase tracking-wider text-foreground">
                    {selectedLog.entity}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">Mã thực thể (ID):</span>
                  <CopyChip value={selectedLog.entityId} head={10} tail={6} />
                </div>
              </div>
            </div>

            {/* Visual Diff / Key-Value Changes */}
            {Object.keys(selectedLog.details || {}).length > 0 && (
              <div className="rounded-xl border border-border/60 bg-surface/50 p-4 space-y-2.5">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Tóm tắt trường thay đổi (Diff View)
                </p>
                <div className="divide-y divide-border/40 text-xs">
                  {Object.entries(selectedLog.details).map(([key, value]) => (
                    <div key={key} className="py-2 flex items-start justify-between gap-3">
                      <span className="font-mono text-[11px] text-muted-foreground">{key}</span>
                      <span className="font-mono text-[11px] text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded break-all text-right">
                        {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Payload JSON view */}
            <details className="rounded-xl border border-border/60 bg-surface/50 p-4 group">
              <summary className="flex items-center justify-between cursor-pointer list-none">
                <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Dữ liệu JSON gốc (Payload)
                </p>
                <span className="text-[10px] font-mono text-muted-foreground">Mở rộng ▾</span>
              </summary>
              <pre className="mt-3 max-h-72 overflow-y-auto rounded-lg border border-border/60 bg-canvas p-3 font-mono text-xs text-foreground/90 thin-scrollbar leading-relaxed">
                {JSON.stringify(selectedLog.details, null, 2)}
              </pre>
            </details>
          </div>
        )}
      </EntityDrawer>
    </div>
  );
}
