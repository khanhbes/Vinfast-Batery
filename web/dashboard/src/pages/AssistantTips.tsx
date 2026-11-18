import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import {
  AlertTriangle,
  ExternalLink,
  Eye,
  EyeOff,
  Lightbulb,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Save,
  Search,
} from 'lucide-react';
import { adminHideTip, adminSaveTip, adminTips } from '@/api';
import { PortalHttpError } from '@/lib/httpClient';
import appTipsData from '@/data/appTips.json';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { StatusBadge } from '@/components/common/StatusBadge';

/** QA 163: một mục "Mẹo nhỏ" dùng chung cho Tiện ích → Mẹo nhỏ trên app và Pinova Bot. */
interface Tip {
  id: string;
  category: string;
  title: string;
  body: string;
  appliesTo: string;
  when: string;
  tags: string[];
  action?: string;
  source: { name: string; url: string | null };
  origin?: 'builtin' | 'admin';
  enabled?: boolean;
}

const CATEGORIES: [string, string][] = [
  ['drive', 'Lái xe tiết kiệm'],
  ['charge', 'Sạc pin'],
  ['battery', 'Giữ pin bền'],
  ['weather', 'Trời mưa & nắng nóng'],
  ['storage', 'Để xe lâu ngày'],
  ['safety', 'An toàn'],
  ['app', 'Dùng app Pinova'],
];

const APPLIES: [string, string][] = [
  ['all', 'Mọi loại pin'],
  ['lithium', 'Pin lithium'],
  ['leadAcid', 'Ắc quy chì'],
];

const MOMENTS: [string, string][] = [
  ['any', 'Bất kỳ lúc nào'],
  ['morning', 'Buổi sáng'],
  ['afterCharge', 'Sau khi sạc'],
  ['lowBattery', 'Pin yếu'],
  ['rain', 'Mùa mưa'],
];

const ACTIONS: [string, string][] = [
  ['', 'Không gắn nút'],
  ['charge', 'Mở Sạc pin'],
  ['trip_planner', 'Mở Lộ trình'],
  ['night_charging', 'Mở Sạc đêm'],
  ['battery_health', 'Mở Sức khỏe pin'],
  ['maintenance', 'Mở Bảo dưỡng'],
];

const labelOf = (pairs: [string, string][], id?: string) =>
  pairs.find(([key]) => key === (id || ''))?.[1] ?? id ?? '';

const slugifyTipId = (value: string) =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'd')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

const tipErrorMessage = (error: unknown, fallback: string) => {
  const data = (error as { data?: { userMessage?: unknown } })?.data;
  if (typeof data?.userMessage === 'string' && data.userMessage.trim()) return data.userMessage;
  return error instanceof Error && error.message && !error.message.includes('The request is invalid')
    ? error.message
    : fallback;
};

const emptyTip: Tip = {
  id: '',
  category: 'drive',
  title: '',
  body: '',
  appliesTo: 'all',
  when: 'any',
  tags: [],
  source: { name: 'Pinova', url: null },
  enabled: true,
};

function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: [string, string][];
  onChange: (v: string) => void;
}) {
  return (
    <label className="space-y-1 text-xs">
      <span className="block font-medium text-[var(--text-secondary)]">{label}</span>
      <select
        className="h-9 w-full rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 text-xs text-[var(--text-primary)] focus:outline-none focus:border-[var(--accent-primary)]"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {options.map(([id, text]) => (
          <option key={id} value={id}>
            {text}
          </option>
        ))}
      </select>
    </label>
  );
}

export default function AssistantTips() {
  const [tips, setTips] = useState<Tip[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [cloudSynced, setCloudSynced] = useState(true);
  const [syncNotice, setSyncNotice] = useState('');
  const [query, setQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState<'all' | 'enabled' | 'admin' | 'hidden'>('all');
  const [editing, setEditing] = useState<{ tip: Tip; isNew: boolean } | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError('');
    try {
      const res = (await adminTips()) as Tip[] | { data?: Tip[] } | null;
      const list = Array.isArray(res) ? res : Array.isArray(res?.data) ? res.data : [];
      setTips(list);
      setCloudSynced(true);
      setSyncNotice('');
    } catch (error) {
      if (error instanceof PortalHttpError && error.status === 404) {
        const fallbackTips = (Array.isArray(appTipsData?.tips) ? appTipsData.tips : []).map(
          (item) =>
            ({
              ...(item as Tip),
              origin: 'builtin',
              enabled: true,
            }) satisfies Tip
        );
        setTips(fallbackTips);
        setCloudSynced(false);
        setSyncNotice(
          `Đang hiển thị ${fallbackTips.length} mẹo chuẩn đồng bộ trực tiếp từ app (tips_vi.json · phiên bản ${appTipsData?.version || '2026-11-16'}). Cloud vinfast-api chưa có endpoint /api/admin/tips nên tạm thời chỉ xem; cần deploy lại vinfast-api để lưu/ẩn mẹo lên Firestore.`
        );
        return;
      }
      const message = error instanceof Error ? error.message : 'Chưa tải được danh sách mẹo';
      setLoadError(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const counts = useMemo(
    () => ({
      all: tips.length,
      enabled: tips.filter((t) => t.enabled !== false).length,
      admin: tips.filter((t) => t.origin === 'admin').length,
      hidden: tips.filter((t) => t.enabled === false).length,
    }),
    [tips]
  );

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return tips.filter((t) => {
      if (categoryFilter !== 'all' && t.category !== categoryFilter) return false;
      if (statusFilter === 'enabled' && t.enabled === false) return false;
      if (statusFilter === 'admin' && t.origin !== 'admin') return false;
      if (statusFilter === 'hidden' && t.enabled !== false) return false;
      if (!q) return true;
      const haystack = `${t.title} ${t.body} ${t.id} ${(t.tags || []).join(' ')} ${t.source?.name || ''}`.toLowerCase();
      return haystack.includes(q);
    });
  }, [tips, query, categoryFilter, statusFilter]);

  const save = async () => {
    if (!editing) return;
    if (!cloudSynced) {
      toast.warning(
        'Backend cloud chưa cập nhật /api/admin/tips nên chưa thể lưu lên Firestore. Vui lòng deploy lại vinfast-api.'
      );
      return;
    }
    const { tip, isNew } = editing;
    const resolvedId = (tip.id.trim() || (isNew ? slugifyTipId(tip.title) : '')).toLowerCase();
    if (!/^[a-z0-9-]{3,60}$/.test(resolvedId)) {
      toast.error('Mã mẹo chỉ gồm chữ thường không dấu, số và dấu gạch (3–60 ký tự)');
      return;
    }
    if (!tip.title.trim() || !tip.body.trim()) {
      toast.error('Cần nhập tiêu đề và nội dung');
      return;
    }
    const rawUrl = tip.source?.url?.trim() || '';
    if (rawUrl && !rawUrl.startsWith('https://')) {
      toast.error('Link nguồn phải bắt đầu bằng https://');
      return;
    }
    setSaving(true);
    try {
      await adminSaveTip(resolvedId, {
        category: tip.category,
        title: tip.title.trim(),
        body: tip.body.trim(),
        appliesTo: tip.appliesTo,
        when: tip.when,
        tags: tip.tags,
        action: tip.action || null,
        enabled: true,
        source: {
          name: tip.source?.name?.trim() || 'Pinova',
          url: rawUrl || null,
        },
      });
      toast.success('Đã lưu và đồng bộ mẹo với app');
      setEditing(null);
      await load();
    } catch (error) {
      if (error instanceof PortalHttpError && error.status === 404) {
        toast.warning(
          'Backend cloud chưa cập nhật /api/admin/tips nên chưa thể lưu lên Firestore. Vui lòng deploy lại vinfast-api.'
        );
      } else {
        toast.error(tipErrorMessage(error, 'Chưa lưu được mẹo. Kiểm tra lại dữ liệu và kết nối máy chủ.'));
      }
    } finally {
      setSaving(false);
    }
  };

  const toggleVisible = async (tip: Tip) => {
    if (!cloudSynced) {
      toast.warning(
        'Backend cloud chưa cập nhật /api/admin/tips nên chưa thể ẩn/hiện mẹo trên Firestore. Vui lòng deploy lại vinfast-api.'
      );
      return;
    }
    const hiding = tip.enabled !== false;
    try {
      if (hiding) {
        await adminHideTip(tip.id);
        toast.success(`Đã ẩn mẹo "${tip.title}"`);
      } else {
        await adminSaveTip(tip.id, { ...tip, enabled: true, action: tip.action || null });
        toast.success(`Đã bật lại mẹo "${tip.title}"`);
      }
      await load();
    } catch (error) {
      if (error instanceof PortalHttpError && error.status === 404) {
        toast.warning(
          'Backend cloud chưa cập nhật /api/admin/tips nên chưa thể cập nhật trạng thái lên Firestore. Vui lòng deploy lại vinfast-api.'
        );
      } else {
        toast.error(tipErrorMessage(error, 'Chưa cập nhật được trạng thái mẹo'));
      }
    }
  };

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="page-header flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-[22px] font-semibold tracking-tight text-[var(--text-primary)]">
            <Lightbulb className="h-5 w-5 text-amber-400" />
            <span>Mẹo nhỏ</span>
          </h1>
          <p className="mt-1 text-xs text-[var(--text-muted)]">
            Đồng bộ trực tiếp với mục Tiện ích → Mẹo nhỏ trên app và câu trả lời của Pinova Bot.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => void load()}
            disabled={loading}
            className="hover-pill h-8 gap-1.5 text-xs border-[var(--border-hairline)] bg-[var(--bg-surface)] hover:bg-[var(--bg-elevated)]"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />
            Làm mới
          </Button>
          <Button
            size="sm"
            onClick={() => setEditing({ tip: { ...emptyTip, source: { ...emptyTip.source } }, isNew: true })}
            className="hover-pill h-8 gap-1.5 text-xs bg-[var(--accent-primary)] hover:bg-[var(--accent-hover)] text-white"
          >
            <Plus className="h-3.5 w-3.5" />
            Thêm mẹo
          </Button>
        </div>
      </div>

      {/* Editor Card */}
      {editing && (
        <Card className="border-[var(--accent-border)] bg-[var(--bg-surface)] shadow-xs">
          <CardHeader className="pb-3 border-b border-[var(--border-hairline)]">
            <CardTitle className="text-[15px]">
              {editing.isNew ? 'Thêm mẹo mới' : `Chỉnh sửa: ${editing.tip.title || editing.tip.id}`}
            </CardTitle>
            <CardDescription className="text-xs">
              Viết ngắn gọn 1–3 câu, không tự đặt con số khi chưa có nguồn xác thực; link nguồn dùng https://.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3 pt-4">
            <div className="grid gap-3 md:grid-cols-2">
              <label className="space-y-1 text-xs">
                <span className="block font-medium text-[var(--text-secondary)]">
                  Mã mẹo (tự tạo từ tiêu đề nếu để trống)
                </span>
                <Input
                  placeholder="vd: drive-eco-city"
                  value={editing.tip.id}
                  disabled={!editing.isNew}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      tip: { ...editing.tip, id: slugifyTipId(e.target.value) },
                    })
                  }
                  className="h-9 text-xs font-mono"
                />
              </label>
              <label className="space-y-1 text-xs">
                <span className="block font-medium text-[var(--text-secondary)]">Tiêu đề (tối đa 60 ký tự)</span>
                <Input
                  placeholder="Tiêu đề ngắn gọn"
                  maxLength={60}
                  value={editing.tip.title}
                  onChange={(e) =>
                    setEditing({ ...editing, tip: { ...editing.tip, title: e.target.value } })
                  }
                  className="h-9 text-xs"
                />
              </label>
            </div>

            <label className="space-y-1 text-xs">
              <span className="block font-medium text-[var(--text-secondary)]">Nội dung hiển thị trên app &amp; bot</span>
              <textarea
                className="min-h-24 w-full rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-3 text-xs text-[var(--text-primary)] focus:outline-none focus:border-[var(--accent-primary)]"
                placeholder="Nội dung mẹo (1–3 câu, không dùng ký tự ~)"
                maxLength={600}
                value={editing.tip.body}
                onChange={(e) =>
                  setEditing({ ...editing, tip: { ...editing.tip, body: e.target.value } })
                }
              />
            </label>

            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <SelectField
                label="Nhóm chủ đề"
                value={editing.tip.category}
                options={CATEGORIES}
                onChange={(v) => setEditing({ ...editing, tip: { ...editing.tip, category: v } })}
              />
              <SelectField
                label="Loại pin áp dụng"
                value={editing.tip.appliesTo}
                options={APPLIES}
                onChange={(v) => setEditing({ ...editing, tip: { ...editing.tip, appliesTo: v } })}
              />
              <SelectField
                label="Thời điểm gợi ý"
                value={editing.tip.when}
                options={MOMENTS}
                onChange={(v) => setEditing({ ...editing, tip: { ...editing.tip, when: v } })}
              />
              <SelectField
                label="Nút mở nhanh trên app"
                value={editing.tip.action ?? ''}
                options={ACTIONS}
                onChange={(v) =>
                  setEditing({ ...editing, tip: { ...editing.tip, action: v || undefined } })
                }
              />
            </div>

            <div className="grid gap-3 md:grid-cols-3">
              <label className="space-y-1 text-xs">
                <span className="block font-medium text-[var(--text-secondary)]">Từ khóa tìm kiếm</span>
                <Input
                  placeholder="eco, tiết kiệm, sạc ai..."
                  value={(editing.tip.tags || []).join(', ')}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      tip: {
                        ...editing.tip,
                        tags: e.target.value
                          .split(',')
                          .map((s) => s.trim())
                          .filter(Boolean),
                      },
                    })
                  }
                  className="h-9 text-xs"
                />
              </label>
              <label className="space-y-1 text-xs">
                <span className="block font-medium text-[var(--text-secondary)]">Tên nguồn</span>
                <Input
                  placeholder="Pinova / Sổ bảo hành..."
                  value={editing.tip.source?.name || ''}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      tip: {
                        ...editing.tip,
                        source: { ...(editing.tip.source || { url: null }), name: e.target.value },
                      },
                    })
                  }
                  className="h-9 text-xs"
                />
              </label>
              <label className="space-y-1 text-xs">
                <span className="block font-medium text-[var(--text-secondary)]">Link nguồn (https://)</span>
                <Input
                  placeholder="https://... (tùy chọn)"
                  value={editing.tip.source?.url ?? ''}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      tip: {
                        ...editing.tip,
                        source: {
                          ...(editing.tip.source || { name: 'Pinova' }),
                          url: e.target.value.trim() || null,
                        },
                      },
                    })
                  }
                  className="h-9 text-xs"
                />
              </label>
            </div>

            <div className="flex items-center gap-2 pt-2">
              <Button size="sm" onClick={() => void save()} disabled={saving} className="h-8 gap-1.5 text-xs">
                {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
                Lưu &amp; Đồng bộ
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setEditing(null)}
                className="h-8 text-xs border-[var(--border-hairline)]"
              >
                Hủy
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Filter & Search Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-2.5">
        <div className="flex flex-wrap items-center gap-2 flex-1 min-w-[240px]">
          <div className="relative flex-1 min-w-[200px] max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-[var(--text-muted)]" />
            <Input
              className="h-8 pl-9 text-xs bg-[var(--bg-canvas)] border-[var(--border-hairline)]"
              placeholder="Tìm tiêu đề, nội dung, từ khóa, nguồn..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>

          <div className="inline-flex items-center gap-1 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-0.5 text-xs">
            {(
              [
                ['all', 'Tất cả', counts.all],
                ['enabled', 'Đang hiện trên app', counts.enabled],
                ['admin', 'Đã chỉnh sửa', counts.admin],
                ['hidden', 'Đã ẩn', counts.hidden],
              ] as const
            ).map(([id, label, count]) => (
              <button
                key={id}
                type="button"
                onClick={() => setStatusFilter(id)}
                className={`hover-pill inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 font-medium ${
                  statusFilter === id
                    ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold'
                    : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                }`}
              >
                <span>{label}</span>
                <span className="font-mono text-[11px] opacity-75 tabular-nums">{count}</span>
              </button>
            ))}
          </div>
        </div>

        <select
          aria-label="Lọc theo nhóm"
          value={categoryFilter}
          onChange={(e) => setCategoryFilter(e.target.value)}
          className="h-8 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2.5 text-xs text-[var(--text-primary)]"
        >
          <option value="all">Tất cả nhóm ({CATEGORIES.length})</option>
          {CATEGORIES.map(([id, label]) => (
            <option key={id} value={id}>
              {label}
            </option>
          ))}
        </select>
      </div>

      {/* Cloud Sync Fallback Info */}
      {syncNotice && !loading && (
        <div
          role="status"
          className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-xs text-amber-200"
        >
          <div className="flex items-center gap-2">
            <Lightbulb className="h-4 w-4 shrink-0 text-amber-400" />
            <span>{syncNotice}</span>
          </div>
          <Button size="sm" variant="outline" onClick={() => void load()} className="hover-pill h-7 text-xs">
            Kiểm tra lại máy chủ
          </Button>
        </div>
      )}

      {/* Error State */}
      {loadError && !loading && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-xs text-rose-300"
        >
          <div className="flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 text-rose-400" />
            <span>{loadError}</span>
          </div>
          <Button size="sm" variant="outline" onClick={() => void load()} className="h-7 text-xs">
            Thử lại
          </Button>
        </div>
      )}

      {/* Loading */}
      {loading && tips.length === 0 ? (
        <div className="space-y-4 animate-fadeIn">
          {Array.from({ length: 2 }).map((_, cardIdx) => (
            <div key={cardIdx} className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] overflow-hidden">
              <div className="px-5 py-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]/60 flex justify-between">
                <div className="skeleton-shimmer h-4 w-36 rounded-md" />
                <div className="skeleton-shimmer h-4 w-14 rounded-md" />
              </div>
              <div className="p-3 space-y-2.5">
                {Array.from({ length: 3 }).map((_, rowIdx) => (
                  <div key={rowIdx} className="rounded-xl p-3 space-y-2">
                    <div className="skeleton-shimmer h-4 w-1/3 rounded-md" />
                    <div className="skeleton-shimmer h-3 w-5/6 rounded-md" />
                    <div className="skeleton-shimmer h-3 w-1/2 rounded-md" />
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : shown.length === 0 ? (
        <div className="py-12 text-center rounded-xl border border-dashed border-[var(--border-hairline)] bg-[var(--bg-surface)]/50 text-xs text-[var(--text-muted)]">
          Không có mẹo nào khớp với bộ lọc hiện tại.
        </div>
      ) : (
        <div className="space-y-4">
          {CATEGORIES.map(([id, label]) => {
            const group = shown.filter((t) => t.category === id);
            if (!group.length) return null;
            return (
              <Card key={id} className="hover-card border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs overflow-hidden">
                <CardHeader className="py-3 px-5 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]/60 flex flex-row items-center justify-between">
                  <CardTitle className="text-sm font-semibold text-[var(--text-primary)]">
                    {label}
                  </CardTitle>
                  <span className="font-mono text-xs text-[var(--text-secondary)] tabular-nums">
                    {group.length} mẹo
                  </span>
                </CardHeader>
                <CardContent className="p-3 divide-y divide-[var(--border-hairline)]">
                  {group.map((tip) => (
                    <div
                      key={tip.id}
                      className={`hover-lift flex flex-wrap items-start justify-between gap-3 rounded-xl px-3 py-3 transition-colors hover:bg-[var(--bg-hover)] ${
                        tip.enabled === false ? 'opacity-65' : ''
                      }`}
                    >
                      <div className="min-w-0 flex-1 space-y-1.5">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-sm font-semibold text-[var(--text-primary)]">{tip.title}</span>
                          {tip.enabled === false ? (
                            <StatusBadge label="Đã ẩn trên app" tone="neutral" dot={false} />
                          ) : (
                            <StatusBadge label="Đang hiện" tone="success" dot={false} />
                          )}
                          {tip.origin === 'admin' && <StatusBadge label="Admin đã sửa" tone="primary" dot={false} />}
                          {tip.appliesTo !== 'all' && (
                            <StatusBadge
                              label={labelOf(APPLIES, tip.appliesTo)}
                              tone={tip.appliesTo === 'lithium' ? 'info' : 'warning'}
                              dot={false}
                            />
                          )}
                          {tip.when && tip.when !== 'any' && (
                            <span className="rounded-md border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2 py-0.5 text-[11px] text-[var(--text-secondary)]">
                              {labelOf(MOMENTS, tip.when)}
                            </span>
                          )}
                          {tip.action && (
                            <span className="rounded-md border border-[var(--accent-border)] bg-[var(--accent-tint)] px-2 py-0.5 text-[11px] font-medium text-[var(--accent-primary)]">
                              {labelOf(ACTIONS, tip.action)}
                            </span>
                          )}
                        </div>

                        <p className="text-xs leading-relaxed text-[var(--text-secondary)]">{tip.body}</p>

                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-[var(--text-muted)]">
                          <span className="font-mono">{tip.id}</span>
                          <span>·</span>
                          <span className="inline-flex items-center gap-1">
                            <span>Nguồn: {tip.source?.name || 'Pinova'}</span>
                            {tip.source?.url && (
                              <a
                                href={tip.source.url}
                                target="_blank"
                                rel="noreferrer"
                                className="inline-flex items-center gap-0.5 text-[var(--accent-primary)] hover:underline"
                                title={tip.source.url}
                              >
                                <ExternalLink className="h-3 w-3" />
                              </a>
                            )}
                          </span>
                          {tip.tags?.length > 0 && (
                            <>
                              <span>·</span>
                              <span className="truncate max-w-md">{tip.tags.join(', ')}</span>
                            </>
                          )}
                        </div>
                      </div>

                      <div className="flex items-center gap-1.5 shrink-0">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() =>
                            setEditing({
                              tip: { ...emptyTip, ...tip, source: { ...(tip.source || { name: 'Pinova', url: null }) }, enabled: true },
                              isNew: false,
                            })
                          }
                          className="hover-pill h-7 gap-1 px-2.5 text-xs border-[var(--border-hairline)]"
                        >
                          <Pencil className="h-3 w-3" />
                          Sửa
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => void toggleVisible(tip)}
                          className="hover-pill h-7 gap-1 px-2.5 text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                        >
                          {tip.enabled === false ? (
                            <>
                              <Eye className="h-3.5 w-3.5 text-emerald-400" />
                              Hiện lại
                            </>
                          ) : (
                            <>
                              <EyeOff className="h-3.5 w-3.5" />
                              Ẩn
                            </>
                          )}
                        </Button>
                      </div>
                    </div>
                  ))}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
