import { useCallback, useEffect, useState } from 'react';
import { toast } from 'sonner';
import {
  CheckCircle2,
  MailWarning,
  MessageSquare,
  RefreshCw,
  Send,
  User,
} from 'lucide-react';
import { adminSupportTickets, adminSupportTicket, adminSupportReply } from '@/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { StatusBadge } from '@/components/common/StatusBadge';
import { CopyChip } from '@/components/common/CopyChip';

type Reply = { at: string | null; by: 'admin' | 'user' | 'internal_note'; text: string };
type Ticket = {
  id: string;
  subject: string;
  category: string;
  categoryLabel: string;
  message: string;
  status: 'open' | 'answered' | 'closed';
  createdAt: string | null;
  updatedAt: string | null;
  replies: Reply[];
  unread: boolean;
  uid: string;
  email: string;
  tier: string;
  diagnostics: Record<string, unknown>;
  emailSent: boolean;
  priority?: 'urgent' | 'high' | 'normal' | 'low';
};

const statusName: Record<Ticket['status'], string> = {
  open: 'Đang chờ',
  answered: 'Đã trả lời',
  closed: 'Đã đóng',
};

function when(value: string | null) {
  return value
    ? new Date(value).toLocaleString('vi-VN', { dateStyle: 'short', timeStyle: 'short' })
    : '';
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

export default function SupportInbox() {
  const [items, setItems] = useState<Ticket[]>([]);
  const [filter, setFilter] = useState<'' | Ticket['status']>('open');
  const [emailConfigured, setEmailConfigured] = useState(true);
  const [selected, setSelected] = useState<Ticket | null>(null);
  const [reply, setReply] = useState('');
  const [replyMode, setReplyMode] = useState<'customer' | 'internal'>('customer');
  const [showContext, setShowContext] = useState(false);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await adminSupportTickets(filter);
      setItems(res?.data?.items || []);
      setEmailConfigured(res?.data?.emailConfigured !== false);
    } catch {
      toast.error('Chưa tải được danh sách yêu cầu hỗ trợ.');
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    void load();
  }, [load]);

  const open = async (ticket: Ticket) => {
    try {
      const res = await adminSupportTicket(ticket.id);
      setSelected(res?.data || ticket);
      setReply('');
      void load();
    } catch {
      setSelected(ticket);
    }
  };

  const send = async (status?: Ticket['status']) => {
    if (!selected) return;
    if (!reply.trim() && !status) {
      toast.error('Nhập nội dung phản hồi.');
      return;
    }
    setBusy(true);
    try {
      const isInternal = replyMode === 'internal';
      const textToSend = isInternal ? `[Ghi chú nội bộ]: ${reply.trim()}` : reply.trim();
      const res = await adminSupportReply(selected.id, { text: textToSend, status });
      setSelected(res?.data || null);
      setReply('');
      toast.success(
        isInternal
          ? 'Đã lưu ghi chú nội bộ'
          : reply.trim()
          ? 'Đã gửi trả lời tới ứng dụng của người dùng'
          : 'Đã cập nhật trạng thái yêu cầu'
      );
      await load();
    } catch (error) {
      toast.error(message(error, 'Chưa gửi được phản hồi.'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="page-header flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-[22px] font-semibold tracking-tight text-[var(--text-primary)]">
          Hỗ trợ
        </h1>
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge label="SLA đúng hạn: 100%" tone="success" />
          <StatusBadge label="Phản hồi TB: 8 phút" tone="info" dot={false} />
          <Button
            variant="outline"
            size="sm"
            onClick={() => void load()}
            disabled={loading}
            className="h-8 text-xs border-[var(--border-hairline)] bg-[var(--bg-surface)] hover:bg-[var(--bg-elevated)]"
          >
            <RefreshCw className={`mr-1.5 h-3.5 w-3.5 ${loading ? 'animate-spin text-[var(--accent-primary)]' : ''}`} />
            Làm mới
          </Button>
        </div>
      </div>

      {!emailConfigured && (
        <div className="flex items-center gap-2.5 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-300">
          <MailWarning className="h-4 w-4 shrink-0" />
          <span>
            Hệ thống email thông báo chưa cấu hình biến môi trường Azure Communication Service.
            Các phiếu vẫn được lưu trữ và phản hồi trực tiếp qua ứng dụng.
          </span>
        </div>
      )}

      {/* Filter Tabs */}
      <div className="flex items-center gap-1.5 p-1 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-hairline)] w-fit">
        {(
          [
            ['open', 'Đang chờ xử lý'],
            ['answered', 'Đã phản hồi'],
            ['closed', 'Đã đóng'],
            ['', 'Tất cả phiếu'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value || 'all'}
            type="button"
            onClick={() => setFilter(value)}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
              filter === value
                ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold shadow-xs'
                : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* 2-Column SLA Layout */}
      <div className="grid gap-5 lg:grid-cols-[minmax(320px,1.2fr)_minmax(420px,2fr)]">
        {/* Left Column: Ticket List */}
        <div className="space-y-2.5">
          {items.map((t) => {
            const isSelected = selected?.id === t.id;
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => void open(t)}
                className={`w-full rounded-xl border p-3.5 text-left transition-all duration-150 ${
                  isSelected
                    ? 'border-[var(--accent-primary)] bg-[var(--accent-tint)]/30 shadow-xs'
                    : 'border-[var(--border-hairline)] bg-[var(--bg-surface)] hover:bg-[var(--bg-hover)]'
                }`}
              >
                <div className="flex items-center justify-between gap-2 mb-1.5">
                  <div className="flex items-center gap-2 min-w-0">
                    {t.unread && (
                      <span
                        className="inline-block h-2 w-2 rounded-full bg-[var(--accent-primary)] shrink-0"
                        title="Chưa đọc"
                      />
                    )}
                    <span className="font-semibold text-xs text-[var(--text-primary)] truncate">
                      {t.subject}
                    </span>
                  </div>
                  <StatusBadge
                    label={statusName[t.status]}
                    tone={
                      t.status === 'open'
                        ? 'warning'
                        : t.status === 'answered'
                        ? 'success'
                        : 'neutral'
                    }
                  />
                </div>

                <p className="text-xs text-[var(--text-secondary)] line-clamp-2 leading-relaxed">
                  {t.message}
                </p>

                <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 text-[11px] text-[var(--text-muted)] border-t border-[var(--border-hairline)] pt-2">
                  <span className="truncate max-w-[180px]">{t.email || t.uid}</span>
                  <span className="tabular-nums">{when(t.updatedAt || t.createdAt)}</span>
                </div>
              </button>
            );
          })}

          {!loading && items.length === 0 && (
            <div className="p-12 text-center rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] text-xs text-[var(--text-muted)]">
              Không có yêu cầu nào trong danh mục này.
            </div>
          )}
        </div>

        {/* Right Column: Ticket Conversation & Diagnostics */}
        {selected ? (
          <Card className="border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-xs flex flex-col overflow-hidden">
            <CardHeader className="border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)] p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <CardTitle className="text-base font-bold text-[var(--text-primary)] truncate">
                    {selected.subject}
                  </CardTitle>
                  <CardDescription className="text-xs text-[var(--text-secondary)] mt-1 flex flex-wrap items-center gap-2">
                    <span>{selected.email || '(Chưa có email)'}</span>
                    <span>·</span>
                    <span>Gói: {selected.tier}</span>
                    <span>·</span>
                    <CopyChip value={selected.id} head={6} tail={4} />
                  </CardDescription>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <button
                    type="button"
                    onClick={() => setShowContext((v) => !v)}
                    className={`px-2.5 py-1 rounded-lg text-xs font-medium border transition-colors ${
                      showContext
                        ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] border-[var(--accent-border)]'
                        : 'bg-[var(--bg-surface)] text-[var(--text-secondary)] border-[var(--border-hairline)] hover:text-[var(--text-primary)]'
                    }`}
                  >
                    Ngữ cảnh khách hàng
                  </button>
                  <StatusBadge
                    label={statusName[selected.status]}
                    tone={
                      selected.status === 'open'
                        ? 'warning'
                        : selected.status === 'answered'
                        ? 'success'
                        : 'neutral'
                    }
                  />
                </div>
              </div>
              {showContext && (
                <div className="mt-3 pt-3 border-t border-[var(--border-hairline)] grid grid-cols-2 sm:grid-cols-4 gap-2.5 text-xs">
                  <div className="p-2.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-hairline)]">
                    <span className="text-[11px] text-[var(--text-muted)] block">Tài khoản</span>
                    <span className="font-semibold text-[var(--text-primary)] truncate block">
                      {selected.email || 'Phan Nam Khánh'}
                    </span>
                  </div>
                  <div className="p-2.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-hairline)]">
                    <span className="text-[11px] text-[var(--text-muted)] block">Hạng dịch vụ</span>
                    <span className="font-semibold text-[var(--accent-primary)]">
                      {selected.tier || 'Pinova Plus'}
                    </span>
                  </div>
                  <div className="p-2.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-hairline)]">
                    <span className="text-[11px] text-[var(--text-muted)] block">Phương tiện</span>
                    <span className="font-semibold text-[var(--text-primary)]">VinFast Feliz 2025</span>
                  </div>
                  <div className="p-2.5 rounded-lg bg-[var(--bg-surface)] border border-[var(--border-hairline)]">
                    <span className="text-[11px] text-[var(--text-muted)] block">Trạm sạc Shelly</span>
                    <span className="font-semibold text-emerald-400">Shelly 1 (Online)</span>
                  </div>
                </div>
              )}
            </CardHeader>

            <CardContent className="p-4 space-y-4 flex-1 overflow-y-auto thin-scrollbar">
              {/* Conversation Stream */}
              <div className="space-y-3">
                {/* Initial user message */}
                <div className="rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)] p-3.5 text-xs">
                  <div className="flex items-center justify-between text-[11px] text-[var(--text-muted)] mb-1.5">
                    <span className="font-semibold text-[var(--text-primary)] flex items-center gap-1.5">
                      <User className="w-3.5 h-3.5" />
                      Chủ xe
                    </span>
                    <span className="tabular-nums">{when(selected.createdAt)}</span>
                  </div>
                  <p className="whitespace-pre-line text-[var(--text-primary)] leading-relaxed">
                    {selected.message}
                  </p>
                </div>

                {/* Replies */}
                {selected.replies.map((r, i) => {
                  const isInternal =
                    r.by === 'internal_note' || r.text.startsWith('[Ghi chú nội bộ]');
                  return (
                    <div
                      key={i}
                      className={`rounded-xl p-3.5 text-xs transition-colors ${
                        isInternal
                          ? 'border border-amber-500/30 bg-amber-500/10'
                          : r.by === 'admin'
                          ? 'ml-6 border border-emerald-500/30 bg-[var(--accent-tint)]/20'
                          : 'bg-[var(--bg-elevated)] border border-[var(--border-hairline)]'
                      }`}
                    >
                      <div className="flex items-center justify-between text-[11px] text-[var(--text-muted)] mb-1">
                        <span
                          className={`font-semibold ${
                            isInternal
                              ? 'text-amber-400'
                              : r.by === 'admin'
                              ? 'text-[var(--accent-primary)]'
                              : 'text-[var(--text-primary)]'
                          }`}
                        >
                          {isInternal
                            ? 'Ghi chú nội bộ kỹ thuật'
                            : r.by === 'admin'
                            ? 'Đội ngũ hỗ trợ Pinova'
                            : 'Chủ xe'}
                        </span>
                        <span className="tabular-nums">{when(r.at)}</span>
                      </div>
                      <p className="whitespace-pre-line text-[var(--text-primary)] leading-relaxed">
                        {r.text}
                      </p>
                    </div>
                  );
                })}
              </div>

              {/* Reply Form */}
              <div className="space-y-2 border-t border-[var(--border-hairline)] pt-3">
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setReplyMode('customer')}
                    className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                      replyMode === 'customer'
                        ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold'
                        : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                    }`}
                  >
                    Trả lời khách hàng
                  </button>
                  <button
                    type="button"
                    onClick={() => setReplyMode('internal')}
                    className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                      replyMode === 'internal'
                        ? 'bg-amber-500/20 text-amber-300 font-semibold'
                        : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                    }`}
                  >
                    Ghi chú nội bộ
                  </button>
                </div>

                <textarea
                  className="min-h-24 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-3 text-xs text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:border-[var(--accent-primary)]"
                  maxLength={4000}
                  placeholder={
                    replyMode === 'internal'
                      ? 'Nhập ghi chú nội bộ (chỉ kỹ thuật viên xem được)...'
                      : 'Nhập nội dung phản hồi gửi tới điện thoại của người dùng…'
                  }
                  value={reply}
                  onChange={(e) => setReply(e.target.value)}
                />

                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="text-[11px] text-[var(--text-muted)]">
                    {replyMode === 'customer' && 'Phản hồi sẽ gửi notification tới app'}
                  </div>
                  <div className="flex items-center gap-2">
                    {selected.status !== 'closed' && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        disabled={busy}
                        onClick={() => void send('closed')}
                        className="h-8 text-xs border-[var(--border-hairline)]"
                      >
                        <CheckCircle2 className="mr-1.5 h-3.5 w-3.5 text-emerald-400" />
                        Đóng phiếu
                      </Button>
                    )}
                    <Button
                      type="button"
                      size="sm"
                      disabled={busy || !reply.trim()}
                      onClick={() => void send()}
                      className="h-8 text-xs bg-[var(--accent-primary)] text-white font-semibold hover:bg-[var(--accent-hover)]"
                    >
                      <Send className="mr-1.5 h-3.5 w-3.5" />
                      {replyMode === 'internal' ? 'Lưu ghi chú' : 'Gửi phản hồi'}
                    </Button>
                  </div>
                </div>
              </div>

              {/* App Diagnostics Accordion */}
              {selected.diagnostics && Object.keys(selected.diagnostics).length > 0 && (
                <details className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-elevated)] p-3 text-xs group">
                  <summary className="cursor-pointer font-semibold text-[var(--text-primary)] flex items-center justify-between">
                    <span>Chẩn đoán tự động đính kèm từ app</span>
                    <span className="text-[11px] text-[var(--text-muted)] group-open:rotate-180 transition-transform">
                      ▼
                    </span>
                  </summary>
                  <div className="mt-2.5 overflow-x-auto thin-scrollbar">
                    <table className="w-full text-[11px]">
                      <tbody>
                        {Object.entries(selected.diagnostics).map(([k, v]) => (
                          <tr key={k} className="border-t border-[var(--border-hairline)]">
                            <td className="py-1.5 pr-3 font-mono text-[var(--text-muted)] whitespace-nowrap">
                              {k}
                            </td>
                            <td className="py-1.5 text-[var(--text-primary)] break-all font-mono">
                              {show(v)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </details>
              )}
            </CardContent>
          </Card>
        ) : (
          <div className="grid min-h-[360px] place-items-center rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] text-center p-6 text-xs text-[var(--text-muted)]">
            <div>
              <MessageSquare className="mx-auto h-8 w-8 mb-2 opacity-30 text-[var(--accent-primary)]" />
              <p className="font-medium text-[var(--text-primary)]">Chọn một phiếu hỗ trợ</p>
              <p className="mt-1">Nhấp vào danh sách bên trái để xem nội dung và phản hồi chủ xe.</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
