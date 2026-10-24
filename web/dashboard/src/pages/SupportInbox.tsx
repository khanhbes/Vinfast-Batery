import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import { LifeBuoy, RefreshCw, Send, CheckCircle2, MailWarning } from 'lucide-react';
import { adminSupportTickets, adminSupportTicket, adminSupportReply } from '@/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';

type Reply = { at: string | null; by: 'admin' | 'user'; text: string };
type Ticket = {
  id: string; subject: string; category: string; categoryLabel: string; message: string;
  status: 'open' | 'answered' | 'closed'; createdAt: string | null; updatedAt: string | null;
  replies: Reply[]; unread: boolean; uid: string; email: string; tier: string;
  diagnostics: Record<string, unknown>; emailSent: boolean;
};

const statusName: Record<Ticket['status'], string> = { open: 'Đang chờ', answered: 'Đã trả lời', closed: 'Đã đóng' };
const statusTone: Record<Ticket['status'], string> = {
  open: 'bg-amber-100 text-amber-700', answered: 'bg-emerald-100 text-emerald-700', closed: 'bg-slate-100 text-slate-700',
};

function when(value: string | null) {
  return value ? new Date(value).toLocaleString('vi-VN', { dateStyle: 'short', timeStyle: 'short' }) : '';
}

function message(error: unknown, fallback: string) {
  const data = (error as { data?: { userMessage?: unknown } })?.data;
  return typeof data?.userMessage === 'string' ? data.userMessage : fallback;
}

function show(value: unknown): string {
  if (value === null || value === undefined) return '—';
  if (Array.isArray(value)) return value.join(', ') || '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

/** Support inbox (QA 135): tickets from every plan, with the app's
 *  self-check attached; a reply reaches the owner's phone. */
export default function SupportInbox() {
  const [items, setItems] = useState<Ticket[]>([]);
  const [filter, setFilter] = useState<'' | Ticket['status']>('open');
  const [emailConfigured, setEmailConfigured] = useState(true);
  const [selected, setSelected] = useState<Ticket | null>(null);
  const [reply, setReply] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await adminSupportTickets(filter);
      setItems(res?.data?.items || []);
      setEmailConfigured(res?.data?.emailConfigured !== false);
    } catch { toast.error('Chưa tải được yêu cầu hỗ trợ.'); }
  }, [filter]);

  useEffect(() => { void load(); }, [load]);

  const open = async (ticket: Ticket) => {
    try {
      const res = await adminSupportTicket(ticket.id);
      setSelected(res?.data || ticket);
      setReply('');
      void load();
    } catch { setSelected(ticket); }
  };

  const send = async (status?: Ticket['status']) => {
    if (!selected) return;
    if (!reply.trim() && !status) { toast.error('Nhập nội dung trả lời.'); return; }
    setBusy(true);
    try {
      const res = await adminSupportReply(selected.id, { text: reply.trim(), status });
      setSelected(res?.data || null);
      setReply('');
      toast.success(reply.trim() ? 'Đã gửi trả lời tới app của người dùng.' : 'Đã cập nhật trạng thái.');
      await load();
    } catch (error) {
      toast.error(message(error, 'Chưa gửi được.'));
    } finally { setBusy(false); }
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle className="flex items-center gap-2"><LifeBuoy className="h-5 w-5 text-primary" /> Hỗ trợ người dùng</CardTitle>
            <CardDescription>Yêu cầu gửi từ app (mọi gói). Trả lời ở đây hiện trong app và gửi thông báo tới điện thoại của người dùng.</CardDescription>
          </div>
          <Button variant="outline" onClick={() => void load()}><RefreshCw className="mr-2 h-4 w-4" />Tải lại</Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {!emailConfigured && (
            <p className="flex items-center gap-2 rounded-md bg-amber-50 p-3 text-sm text-amber-800">
              <MailWarning className="h-4 w-4" />Email báo yêu cầu mới chưa bật (cần ACS_CONNECTION_STRING, SUPPORT_SENDER_EMAIL, SUPPORT_ADMIN_EMAIL). Yêu cầu vẫn được lưu ở đây.
            </p>
          )}
          <div className="flex flex-wrap gap-2">
            {([['open', 'Đang chờ'], ['answered', 'Đã trả lời'], ['closed', 'Đã đóng'], ['', 'Tất cả']] as const).map(([value, label]) => (
              <Button key={value || 'all'} size="sm" variant={filter === value ? 'default' : 'outline'} onClick={() => setFilter(value)}>{label}</Button>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
        <div className="space-y-2">
          {items.map((t) => (
            <button key={t.id} onClick={() => void open(t)}
              className={`w-full rounded-lg border p-3 text-left transition hover:bg-muted/40 ${selected?.id === t.id ? 'border-primary' : ''}`}>
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium">{t.unread && <span className="mr-2 inline-block h-2 w-2 rounded-full bg-emerald-500" aria-label="Chưa đọc" />}{t.subject}</span>
                <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${statusTone[t.status]}`}>{statusName[t.status]}</span>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">{t.email || t.uid} · {t.categoryLabel} · {t.tier} · {when(t.updatedAt)}</p>
            </button>
          ))}
          {items.length === 0 && <p className="text-sm text-muted-foreground">Không có yêu cầu nào.</p>}
        </div>

        {selected && (
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">{selected.subject}</CardTitle>
              <CardDescription>{selected.email || '(không có email)'} · UID {selected.uid} · gói {selected.tier} · {selected.categoryLabel} · mã {selected.id}{selected.emailSent ? '' : ' · chưa gửi email'}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <div className="rounded-lg bg-muted/50 p-3 text-sm"><p className="mb-1 text-xs text-muted-foreground">Người dùng · {when(selected.createdAt)}</p><p className="whitespace-pre-line">{selected.message}</p></div>
                {selected.replies.map((r, i) => (
                  <div key={i} className={`rounded-lg p-3 text-sm ${r.by === 'admin' ? 'ml-8 bg-emerald-50' : 'bg-muted/50'}`}>
                    <p className="mb-1 text-xs text-muted-foreground">{r.by === 'admin' ? 'Đội Pinova' : 'Người dùng'} · {when(r.at)}</p>
                    <p className="whitespace-pre-line">{r.text}</p>
                  </div>
                ))}
              </div>
              <textarea className="min-h-28 w-full rounded-md border bg-background p-3 text-sm" maxLength={4000}
                placeholder="Trả lời người dùng…" value={reply} onChange={(e) => setReply(e.target.value)} />
              <div className="flex flex-wrap justify-end gap-2">
                {selected.status !== 'closed' && <Button variant="outline" disabled={busy} onClick={() => void send('closed')}><CheckCircle2 className="mr-2 h-4 w-4" />Đóng yêu cầu</Button>}
                <Button disabled={busy || !reply.trim()} onClick={() => void send()}><Send className="mr-2 h-4 w-4" />Gửi trả lời</Button>
              </div>
              <details className="rounded-lg border p-3 text-sm">
                <summary className="cursor-pointer font-medium">Chẩn đoán tự động từ app</summary>
                <table className="mt-2 w-full text-xs">
                  <tbody>
                    {Object.entries(selected.diagnostics || {}).map(([k, v]) => (
                      <tr key={k} className="border-t"><td className="py-1 pr-3 font-mono text-muted-foreground">{k}</td><td className="py-1">{show(v)}</td></tr>
                    ))}
                  </tbody>
                </table>
              </details>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
