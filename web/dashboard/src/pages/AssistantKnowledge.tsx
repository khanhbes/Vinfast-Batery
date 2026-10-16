import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Bot, Plus, RefreshCw, Save, Search, Trash2, EyeOff } from 'lucide-react';
import {
  adminAssistantKnowledge,
  adminSaveAssistantKnowledge,
  adminDeleteAssistantKnowledge,
} from '@/api';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';

type Entry = { id: string; title: string; keywords: string[]; body: string; source: 'builtin' | 'admin'; enabled: boolean };
type Status = { configured: boolean; model: string; dailyLimit: number };
type Draft = { id: string; title: string; keywords: string; body: string; isNew: boolean };

const emptyDraft: Draft = { id: '', title: '', keywords: '', body: '', isNew: true };

/** BatteryBot knowledge (Task 124): built-in entries can be overridden or
 *  hidden; new entries are used by the assistant within a minute. */
export default function AssistantKnowledge() {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [status, setStatus] = useState<Status | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [query, setQuery] = useState('');
  const [draft, setDraft] = useState<Draft | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await adminAssistantKnowledge();
      setEntries(res?.data?.entries || []);
      setStatus(res?.data?.assistant || null);
    } catch {
      toast.error('Chưa tải được kiến thức BatteryBot.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return entries;
    return entries.filter((e) => `${e.title} ${e.body} ${e.keywords.join(' ')}`.toLowerCase().includes(q));
  }, [entries, query]);

  const edit = (entry: Entry) => setDraft({
    id: entry.id, title: entry.title, keywords: entry.keywords.join(', '), body: entry.body, isNew: false,
  });

  const save = async () => {
    if (!draft) return;
    const id = draft.id.trim().toLowerCase();
    if (!/^[a-z0-9-]{2,60}$/.test(id)) { toast.error('Mã chỉ gồm a-z, 0-9 và dấu gạch (2–60 ký tự).'); return; }
    if (!draft.title.trim() || !draft.body.trim()) { toast.error('Cần tiêu đề và nội dung.'); return; }
    setSaving(true);
    try {
      await adminSaveAssistantKnowledge(id, {
        title: draft.title.trim(), body: draft.body.trim(), enabled: true,
        keywords: draft.keywords.split(',').map((k) => k.trim()).filter(Boolean),
      });
      toast.success('Đã lưu. BatteryBot dùng nội dung mới trong vòng 1 phút.');
      setDraft(null);
      await load();
    } catch {
      toast.error('Chưa lưu được.');
    } finally {
      setSaving(false);
    }
  };

  const hide = async (entry: Entry) => {
    try {
      await adminSaveAssistantKnowledge(entry.id, { title: entry.title, body: entry.body, enabled: false });
      toast.success('Đã ẩn mục này khỏi BatteryBot.');
      await load();
    } catch { toast.error('Chưa ẩn được.'); }
  };

  const restore = async (entry: Entry) => {
    try {
      await adminDeleteAssistantKnowledge(entry.id);
      toast.success(entry.source === 'admin' ? 'Đã xóa bản sửa của admin.' : 'Đã khôi phục.');
      await load();
    } catch { toast.error('Chưa xóa được.'); }
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2"><Bot className="h-5 w-5 text-primary" /> Kiến thức BatteryBot</CardTitle>
            <CardDescription>
              Nội dung trợ lý dùng để trả lời về app, xe, sạc và Shelly. Mục có sẵn có thể sửa (tạo bản của admin) hoặc ẩn.
            </CardDescription>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => void load()} disabled={loading}><RefreshCw className="mr-2 h-4 w-4" />Tải lại</Button>
            <Button onClick={() => setDraft({ ...emptyDraft })}><Plus className="mr-2 h-4 w-4" />Thêm mục</Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          {status && (
            <p className="text-sm text-muted-foreground">
              Mô hình: <b>{status.model}</b> · {status.configured ? 'Đã cấu hình khóa API' : 'CHƯA cấu hình khóa API (bot dùng chế độ cơ bản)'} · Giới hạn {status.dailyLimit} tin/ngày/người
            </p>
          )}
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <Input className="pl-9" placeholder="Tìm theo tiêu đề, nội dung, từ khóa" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
        </CardContent>
      </Card>

      {draft && (
        <Card>
          <CardHeader><CardTitle>{draft.isNew ? 'Thêm mục kiến thức' : `Sửa: ${draft.id}`}</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <label className="block text-sm font-medium">Mã (a-z, 0-9, -)
              <Input value={draft.id} disabled={!draft.isNew} onChange={(e) => setDraft({ ...draft, id: e.target.value })} placeholder="vd: chinh-sach-bao-hanh" />
            </label>
            <label className="block text-sm font-medium">Tiêu đề
              <Input value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} />
            </label>
            <label className="block text-sm font-medium">Từ khóa (phân cách bằng dấu phẩy)
              <Input value={draft.keywords} onChange={(e) => setDraft({ ...draft, keywords: e.target.value })} placeholder="bảo hành, đổi pin" />
            </label>
            <label className="block text-sm font-medium">Nội dung (tối đa 2000 ký tự)
              <textarea
                className="mt-1 min-h-40 w-full rounded-md border bg-background p-3 text-sm"
                maxLength={2000}
                value={draft.body}
                onChange={(e) => setDraft({ ...draft, body: e.target.value })}
              />
            </label>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setDraft(null)}>Hủy</Button>
              <Button onClick={() => void save()} disabled={saving}><Save className="mr-2 h-4 w-4" />Lưu</Button>
            </div>
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3 md:grid-cols-2">
        {visible.map((entry) => (
          <Card key={entry.id}>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center justify-between gap-2 text-base">
                <span>{entry.title}</span>
                <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${!entry.enabled ? 'bg-amber-100 text-amber-700' : entry.source === 'admin' ? 'bg-blue-100 text-blue-700' : 'bg-slate-100 text-slate-700'}`}>
                  {!entry.enabled ? 'Đang ẩn' : entry.source === 'admin' ? 'Admin' : 'Có sẵn'}
                </span>
              </CardTitle>
              <CardDescription className="text-xs">{entry.id} · {entry.keywords.join(', ')}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="whitespace-pre-line text-sm">{entry.body}</p>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={() => edit(entry)}>Sửa</Button>
                {entry.enabled && (
                  <Button size="sm" variant="outline" onClick={() => void hide(entry)}><EyeOff className="mr-1 h-4 w-4" />Ẩn</Button>
                )}
                {entry.source === 'admin' && (
                  <Button size="sm" variant="outline" onClick={() => void restore(entry)}>
                    <Trash2 className="mr-1 h-4 w-4" />{entry.enabled ? 'Xóa bản admin' : 'Bỏ ẩn / khôi phục'}
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
        {!loading && visible.length === 0 && <p className="text-sm text-muted-foreground">Không có mục nào.</p>}
      </div>
    </div>
  );
}
