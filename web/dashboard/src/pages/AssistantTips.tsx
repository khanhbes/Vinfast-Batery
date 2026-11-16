import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Lightbulb, Plus, Save, EyeOff, Search } from 'lucide-react';
import { apiFetch as rawApiFetch } from '@/api';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';

const apiFetch = rawApiFetch as <T = unknown>(path: string, options?: Record<string, unknown>) => Promise<T>;

/** QA 163: one tip of "Mẹo nhỏ" (the app's screen and Pinova Bot). */
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
  ['', 'Không có'],
  ['charge', 'Mở Sạc pin'],
  ['trip_planner', 'Mở Lộ trình'],
  ['night_charging', 'Mở Sạc đêm'],
  ['battery_health', 'Mở Sức khỏe pin'],
  ['maintenance', 'Mở Bảo dưỡng'],
];

const empty: Tip = {
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

function Select({ value, options, onChange }: { value: string; options: [string, string][]; onChange: (v: string) => void }) {
  return (
    <select
      className="h-10 rounded-md border border-border bg-background px-3 text-sm"
      value={value}
      onChange={(e) => onChange(e.target.value)}
    >
      {options.map(([id, label]) => (
        <option key={id} value={id}>
          {label}
        </option>
      ))}
    </select>
  );
}

/**
 * Mẹo nhỏ (QA 163): the tips the app lists in Tiện ích → Mẹo nhỏ and Pinova
 * Bot tells one of each day. Built-in tips come with the server
 * (tips_vi.json); a save here changes or adds one, "Ẩn" hides one.
 */
export default function AssistantTips() {
  const [tips, setTips] = useState<Tip[]>([]);
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<Tip | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await apiFetch<Tip[]>('/api/admin/tips', { silent: true });
      setTips(Array.isArray(data) ? data : []);
    } catch {
      toast.error('Chưa tải được danh sách mẹo');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return tips.filter((t) => !q || `${t.title} ${t.body} ${t.id}`.toLowerCase().includes(q));
  }, [tips, query]);

  const save = async () => {
    if (!editing) return;
    if (!/^[a-z0-9-]{3,60}$/.test(editing.id)) {
      toast.error('Mã mẹo chỉ gồm chữ thường, số và dấu gạch (3–60 ký tự)');
      return;
    }
    if (!editing.title.trim() || !editing.body.trim()) {
      toast.error('Cần tiêu đề và nội dung');
      return;
    }
    setSaving(true);
    try {
      await apiFetch('/api/admin/tips/' + encodeURIComponent(editing.id), {
        method: 'PUT',
        body: JSON.stringify({ ...editing, action: editing.action || null }),
      });
      toast.success('Đã lưu mẹo');
      setEditing(null);
      await load();
    } catch {
      toast.error('Chưa lưu được mẹo');
    } finally {
      setSaving(false);
    }
  };

  const hide = async (tip: Tip) => {
    try {
      await apiFetch('/api/admin/tips/' + encodeURIComponent(tip.id), { method: 'DELETE' });
      toast.success('Đã ẩn mẹo');
      await load();
    } catch {
      toast.error('Chưa ẩn được mẹo');
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold">
            <Lightbulb className="h-6 w-6" /> Mẹo nhỏ
          </h1>
          <p className="text-sm text-muted-foreground">
            Mẹo hiện ở Tiện ích → Mẹo nhỏ trong app; Pinova Bot nói một mẹo mỗi ngày và dùng mẹo khi được hỏi.
          </p>
        </div>
        <Button onClick={() => setEditing({ ...empty })}>
          <Plus className="mr-2 h-4 w-4" /> Thêm mẹo
        </Button>
      </div>

      {editing && (
        <Card>
          <CardHeader>
            <CardTitle>{tips.some((t) => t.id === editing.id) ? 'Sửa mẹo' : 'Mẹo mới'}</CardTitle>
            <CardDescription>Không ghi con số khi không có nguồn. Nguồn chỉ nhận liên kết https.</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-3">
            <Input
              placeholder="Mã mẹo, ví dụ drive-eco-city"
              value={editing.id}
              onChange={(e) => setEditing({ ...editing, id: e.target.value.trim() })}
            />
            <Input
              placeholder="Tiêu đề (tối đa 60 ký tự)"
              maxLength={60}
              value={editing.title}
              onChange={(e) => setEditing({ ...editing, title: e.target.value })}
            />
            <textarea
              className="min-h-24 rounded-md border border-border bg-background p-3 text-sm"
              placeholder="Nội dung (1–3 câu)"
              maxLength={600}
              value={editing.body}
              onChange={(e) => setEditing({ ...editing, body: e.target.value })}
            />
            <div className="flex flex-wrap gap-3">
              <Select value={editing.category} options={CATEGORIES} onChange={(v) => setEditing({ ...editing, category: v })} />
              <Select value={editing.appliesTo} options={APPLIES} onChange={(v) => setEditing({ ...editing, appliesTo: v })} />
              <Select value={editing.when} options={MOMENTS} onChange={(v) => setEditing({ ...editing, when: v })} />
              <Select value={editing.action ?? ''} options={ACTIONS} onChange={(v) => setEditing({ ...editing, action: v || undefined })} />
            </div>
            <Input
              placeholder="Từ khóa, cách nhau bằng dấu phẩy"
              value={editing.tags.join(', ')}
              onChange={(e) =>
                setEditing({ ...editing, tags: e.target.value.split(',').map((s) => s.trim()).filter(Boolean) })
              }
            />
            <div className="grid gap-3 md:grid-cols-2">
              <Input
                placeholder="Tên nguồn"
                value={editing.source.name}
                onChange={(e) => setEditing({ ...editing, source: { ...editing.source, name: e.target.value } })}
              />
              <Input
                placeholder="https://… (tùy chọn)"
                value={editing.source.url ?? ''}
                onChange={(e) =>
                  setEditing({ ...editing, source: { ...editing.source, url: e.target.value.trim() || null } })
                }
              />
            </div>
            <div className="flex gap-2">
              <Button onClick={save} disabled={saving}>
                <Save className="mr-2 h-4 w-4" /> Lưu
              </Button>
              <Button variant="outline" onClick={() => setEditing(null)}>
                Hủy
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
        <Input className="pl-9" placeholder="Tìm mẹo" value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>

      {CATEGORIES.map(([id, label]) => {
        const group = shown.filter((t) => t.category === id);
        if (!group.length) return null;
        return (
          <Card key={id}>
            <CardHeader>
              <CardTitle className="text-base">
                {label} · {group.length}
              </CardTitle>
            </CardHeader>
            <CardContent className="divide-y divide-border">
              {group.map((tip) => (
                <div key={tip.id} className="flex flex-wrap items-start justify-between gap-3 py-3">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-medium">{tip.title}</span>
                      {tip.enabled === false && <Badge variant="outline">Đã ẩn</Badge>}
                      {tip.origin === 'admin' && <Badge variant="secondary">Đã sửa</Badge>}
                      {tip.appliesTo !== 'all' && (
                        <Badge variant="outline">{APPLIES.find(([a]) => a === tip.appliesTo)?.[1]}</Badge>
                      )}
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">{tip.body}</p>
                    <p className="mt-1 text-xs text-muted-foreground">
                      {tip.id} · Nguồn: {tip.source?.name}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" variant="outline" onClick={() => setEditing({ ...empty, ...tip, enabled: true })}>
                      Sửa
                    </Button>
                    {tip.enabled !== false && (
                      <Button size="sm" variant="ghost" onClick={() => hide(tip)}>
                        <EyeOff className="mr-1 h-4 w-4" /> Ẩn
                      </Button>
                    )}
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
