import { useCallback, useEffect, useState } from 'react';
import {
  AlertCircle,
  Car,
  Code2,
  Eye,
  EyeOff,
  KeyRound,
  MoreHorizontal,
  RotateCcw,
  ShieldAlert,
  ShieldCheck,
  Trash2,
  UserRoundX,
  Users,
} from 'lucide-react';
import { sendPasswordResetEmail } from 'firebase/auth';
import { toast } from 'sonner';
import { auth } from '@/firebase';
import {
  adminAccount,
  adminAccountData,
  adminAccounts,
  adminDeleteAccount,
  adminPasswordResetAudit,
  adminRevokeAccountSessions,
  adminSetAccountStatus,
} from '@/api';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { useDevelopMode } from '@/data/DevelopModeContext';
import { StatusBadge, PlanBadge } from '@/components/common/StatusBadge';
import { CopyChip } from '@/components/common/CopyChip';
import { FilterBar } from '@/components/common/FilterBar';
import { DataTableSurface, type ColumnDef } from '@/components/common/DataTableSurface';
import { EntityDrawer } from '@/components/common/EntityDrawer';

type Account = Record<string, unknown> & {
  uid: string;
  email?: string;
  displayName?: string;
  status?: string;
  isAdmin?: boolean;
  authOnly?: boolean;
  vehicleCount?: number;
  lastSignInAt?: string;
  createdAt?: string;
  tier?: string;
};

const initials = (account: Account) =>
  String(account.displayName || account.email || account.uid)
    .split(/[\s@]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase();

const maskEmail = (email?: string) => {
  if (!email || !email.includes('@')) return email || '—';
  const [local, domain] = email.split('@');
  if (local.length <= 3) return `${local[0] || '*'}***@${domain}`;
  return `${local.slice(0, 4)}•••@${domain}`;
};

const when = (value: unknown) => {
  if (!value) return '—';
  const date = new Date(String(value));
  return Number.isNaN(date.getTime())
    ? '—'
    : date.toLocaleString('vi-VN', { dateStyle: 'short', timeStyle: 'short' });
};

function UserDetailDrawer({
  uid,
  onClose,
  onChanged,
}: {
  uid: string;
  onClose: () => void;
  onChanged: () => Promise<void>;
}) {
  const [account, setAccount] = useState<Account | null>(null);
  const [dataset, setDataset] = useState('vehicles');
  const [records, setRecords] = useState<Record<string, unknown>[]>([]);
  const [showRawJson, setShowRawJson] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmation, setConfirmation] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await adminAccount(uid);
      setAccount((response.data?.account || response.data) as Account);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Không tải được hồ sơ tài khoản');
    } finally {
      setLoading(false);
    }
  }, [uid]);

  const loadData = useCallback(
    async (next = dataset) => {
      try {
        const response = await adminAccountData(uid, { dataset: next, limit: 50 });
        setRecords(response.data || []);
      } catch (error) {
        toast.error(error instanceof Error ? error.message : 'Không tải được dữ liệu liên kết');
      }
    },
    [dataset, uid]
  );

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const action = async (name: string, run: () => Promise<unknown>) => {
    setBusy(name);
    try {
      await run();
      toast.success(
        name === 'disable'
          ? 'Đã khóa đăng nhập & thu hồi phiên'
          : `Đã hoàn tất thao tác: ${name}`
      );
      await load();
      await onChanged();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Thao tác không thành công');
    } finally {
      setBusy('');
    }
  };

  const resetPassword = () =>
    action('gửi email đổi mật khẩu', async () => {
      if (!account?.email) throw new Error('Tài khoản này chưa có địa chỉ email');
      await sendPasswordResetEmail(auth, account.email);
      return adminPasswordResetAudit(uid);
    });

  const deleteAccount = async () => {
    if (confirmation !== uid) {
      toast.error('Nhập chính xác UID để xác nhận xóa');
      return;
    }
    setBusy('delete');
    try {
      const response = await adminDeleteAccount(uid, confirmation);
      const deleted = Number(response.data?.deletedDocuments || 0);
      toast.success(
        `Đã xóa vĩnh viễn tài khoản${deleted ? ` (đã dọn dẹp ${deleted} tài liệu liên quan)` : ''}`
      );
      await onChanged();
      onClose();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Xóa tài khoản thất bại');
    } finally {
      setBusy('');
    }
  };

  const selectDataset = (value: string) => {
    setDataset(value);
    void loadData(value);
  };

  return (
    <EntityDrawer
      open={Boolean(uid)}
      onClose={onClose}
      title={String(account?.displayName || 'Chi tiết tài khoản')}
      subtitle={String(account?.email || account?.uid || 'Đang tải thông tin...')}
      badge={
        account ? (
          <StatusBadge
            label={
              account.status === 'disabled'
                ? 'Đang khóa'
                : account.isAdmin
                ? 'Quản trị viên'
                : 'Hoạt động'
            }
            tone={
              account.status === 'disabled'
                ? 'danger'
                : account.isAdmin
                ? 'primary'
                : 'success'
            }
          />
        ) : null
      }
      actions={
        account && (
          <div className="flex flex-wrap items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={Boolean(busy) || account.isAdmin}
              onClick={() =>
                void action(account.status === 'disabled' ? 'mở khóa' : 'khóa', () =>
                  adminSetAccountStatus(
                    uid,
                    account.status === 'disabled' ? 'active' : 'disabled'
                  )
                )
              }
              className="text-xs h-8 gap-1.5 border-[var(--border-hairline)]"
            >
              {account.status === 'disabled' ? (
                <>
                  <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                  Mở khóa
                </>
              ) : (
                <>
                  <UserRoundX className="w-3.5 h-3.5 text-rose-400" />
                  Khóa tài khoản
                </>
              )}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={Boolean(busy) || account.isAdmin}
              onClick={() => void action('thu hồi phiên', () => adminRevokeAccountSessions(uid))}
              className="text-xs h-8 gap-1.5 border-[var(--border-hairline)]"
            >
              <RotateCcw className="w-3.5 h-3.5 text-[var(--text-muted)]" />
              Thu hồi phiên
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={Boolean(busy) || !account.email}
              onClick={resetPassword}
              className="text-xs h-8 gap-1.5 border-[var(--border-hairline)]"
            >
              <KeyRound className="w-3.5 h-3.5 text-amber-400" />
              Đặt lại mật khẩu
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={Boolean(busy) || account.isAdmin}
              onClick={() => {
                setConfirmDelete(true);
                setConfirmation('');
              }}
              className="text-xs h-8 gap-1.5 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 ml-auto"
            >
              <Trash2 className="w-3.5 h-3.5" />
              Xóa vĩnh viễn
            </Button>
          </div>
        )
      }
    >
      {loading || !account ? (
        <div className="grid min-h-60 place-items-center">
          <div className="w-8 h-8 rounded-full border-2 border-[var(--accent-primary)]/20 border-t-[var(--accent-primary)] animate-spin" />
        </div>
      ) : (
        <div className="space-y-5">
          {/* 2x2 Summary Cards (Level 2 Progressive Disclosure) */}
          <div className="grid grid-cols-2 gap-3">
            <div className="p-3.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)]">
              <div className="text-[11px] text-[var(--text-muted)] mb-1">Mã định danh (UID)</div>
              <CopyChip value={account.uid} head={8} tail={5} />
            </div>
            <div className="p-3.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)]">
              <div className="text-[11px] text-[var(--text-muted)] mb-1">Gói dịch vụ</div>
              <PlanBadge planIdOrName={String(account.tier || (account.isAdmin ? 'Pinova Plus' : 'free'))} />
            </div>
            <div className="p-3.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)]">
              <div className="text-[11px] text-[var(--text-muted)] mb-1">Phương tiện & Thiết bị</div>
              <div className="text-sm font-semibold tabular-nums text-[var(--text-primary)] whitespace-nowrap">
                {Number(account.vehicleCount ?? 1)} xe · {account.isAdmin ? '1 thiết bị' : '0 thiết bị'}
              </div>
            </div>
            <div className="p-3.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)]">
              <div className="text-[11px] text-[var(--text-muted)] mb-1">Hoạt động gần nhất</div>
              <div className="text-xs font-medium tabular-nums text-[var(--text-primary)]">
                {when(account.lastSignInAt || account.createdAt)}
              </div>
            </div>
          </div>

          {/* Delete Danger Confirmation */}
          {confirmDelete && !account.isAdmin && (
            <div className="p-4 rounded-xl border border-rose-500/40 bg-rose-500/10 space-y-3">
              <div className="flex items-center gap-2 text-xs font-semibold text-rose-400">
                <ShieldAlert className="w-4 h-4 shrink-0" />
                <span>Xác nhận xóa vĩnh viễn tài khoản người dùng?</span>
              </div>
              <p className="text-xs text-rose-200/80 leading-relaxed">
                Hành động này sẽ vô hiệu hóa tài khoản Firebase, thu hồi toàn bộ phiên đăng nhập
                và gỡ bỏ dữ liệu liên quan. Không thể hoàn tác.
              </p>
              <div>
                <label className="block text-[11px] font-medium text-rose-300 mb-1">
                  Nhập chính xác UID để xác nhận: <code className="font-mono">{uid}</code>
                </label>
                <Input
                  className="h-8 text-xs font-mono border-rose-500/40 bg-[var(--bg-canvas)]"
                  value={confirmation}
                  onChange={(e) => setConfirmation(e.target.value)}
                  placeholder={uid}
                  autoComplete="off"
                />
              </div>
              <div className="flex items-center gap-2 pt-1">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setConfirmDelete(false);
                    setConfirmation('');
                  }}
                  className="h-7 text-xs border-[var(--border-strong)]"
                >
                  Hủy
                </Button>
                <Button
                  size="sm"
                  variant="destructive"
                  disabled={busy === 'delete' || confirmation !== uid}
                  onClick={() => void deleteAccount()}
                  className="h-7 text-xs"
                >
                  Xác nhận xóa vĩnh viễn
                </Button>
              </div>
            </div>
          )}

          {/* Related Collections Tabs */}
          <div>
            <div className="flex items-center justify-between border-b border-[var(--border-hairline)] pb-2 gap-2">
              <div className="flex items-center gap-1 overflow-x-auto thin-scrollbar">
                {[
                  { id: 'vehicles', label: 'Xe liên kết' },
                  { id: 'charges', label: 'Lịch sử sạc' },
                  { id: 'trips', label: 'Chuyến đi' },
                  { id: 'ai', label: 'Mô hình AI' },
                  { id: 'notifications', label: 'Thông báo' },
                ].map((tab) => (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => selectDataset(tab.id)}
                    className={`px-3 py-1 rounded-md text-xs font-medium transition-colors whitespace-nowrap ${
                      dataset === tab.id
                        ? 'bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold'
                        : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-hover)]'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>
              <button
                type="button"
                onClick={() => setShowRawJson((v) => !v)}
                className="inline-flex items-center gap-1 text-[11px] text-[var(--text-muted)] hover:text-[var(--text-primary)] shrink-0"
                title="Chuyển đổi hiển thị JSON kỹ thuật"
              >
                <Code2 className="w-3.5 h-3.5" />
                <span>{showRawJson ? 'Dạng thẻ' : 'JSON'}</span>
              </button>
            </div>

            <div className="mt-3">
              <div className="text-[11px] text-[var(--text-muted)] mb-2 flex items-center justify-between">
                <span>{records.length} bản ghi đã đồng bộ</span>
              </div>
              {records.length ? (
                <div className="space-y-2 max-h-80 overflow-y-auto thin-scrollbar">
                  {records.map((record, index) =>
                    showRawJson ? (
                      <pre
                        key={String(record.id || index)}
                        className="p-3 rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-hairline)] text-[11px] font-mono text-[var(--text-secondary)] overflow-x-auto"
                      >
                        {JSON.stringify(record, null, 2)}
                      </pre>
                    ) : (
                      <div
                        key={String(record.id || index)}
                        className="p-3 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-hairline)] flex items-center justify-between gap-3 text-xs"
                      >
                        <div className="min-w-0">
                          <div className="font-semibold text-[var(--text-primary)] truncate">
                            {String(
                              record.vehicleName ||
                                record.vinfastModelName ||
                                record.title ||
                                record.sessionId ||
                                record.id ||
                                `Bản ghi #${index + 1}`
                            )}
                          </div>
                          <div className="text-[11px] text-[var(--text-secondary)] truncate mt-0.5 tabular-nums">
                            {record.energyWh !== undefined
                              ? `Điện năng: ${Number(record.energyWh).toFixed(0)} Wh`
                              : record.currentBattery !== undefined
                              ? `Pin hiện tại: ${record.currentBattery}% · ODO: ${record.currentOdo ?? 0} km`
                              : String(record.body || record.status || record.vehicleId || 'Đã đồng bộ')}
                          </div>
                        </div>
                        <span className="text-[11px] text-[var(--text-muted)] tabular-nums whitespace-nowrap shrink-0">
                          {when(record.updatedAt || record.createdAt || record.startTime)}
                        </span>
                      </div>
                    )
                  )}
                </div>
              ) : (
                <div className="py-8 text-center text-xs text-[var(--text-muted)]">
                  Chưa có bản ghi nào trong mục này.
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </EntityDrawer>
  );
}

export default function UserManagement() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [cursor, setCursor] = useState('');
  const [nextCursor, setNextCursor] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [density, setDensity] = useState<'comfortable' | 'compact'>('comfortable');
  const [revealedEmails, setRevealedEmails] = useState<Record<string, boolean>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [selectedUid, setSelectedUid] = useState('');
  const { enabled: developMode } = useDevelopMode();

  const load = useCallback(
    async (next = '', replace = true) => {
      setLoading(true);
      setError('');
      try {
        const response = await adminAccounts({
          limit: 25,
          cursor: next,
          query,
          status: status === 'all' ? '' : status,
        });
        const data = (response.data || []) as Account[];
        setAccounts(replace ? data : (current) => [...current, ...data]);
        setCursor(next);
        setNextCursor(String(response.nextCursor || ''));
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : 'Không tải được danh bạ tài khoản');
      } finally {
        setLoading(false);
      }
    },
    [query, status]
  );

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 220);
    return () => window.clearTimeout(timer);
  }, [load]);

  const counts = {
    total: accounts.length,
    active: accounts.filter((item) => item.status !== 'disabled').length,
    disabled: accounts.filter((item) => item.status === 'disabled').length,
    authOnly: accounts.filter((item) => item.authOnly).length,
  };

  const columns: ColumnDef<Account>[] = [
    {
      key: 'user',
      header: 'Tài khoản',
      width: '32%',
      render: (acc) => {
        const isRevealed = Boolean(revealedEmails[acc.uid]);
        const emailStr = String(acc.email || acc.uid);
        return (
          <div className="flex items-center gap-3 min-w-0">
            <Avatar className="h-8 w-8 shrink-0">
              <AvatarFallback className="bg-[var(--accent-tint)] text-[var(--accent-primary)] font-semibold text-xs">
                {initials(acc)}
              </AvatarFallback>
            </Avatar>
            <div className="min-w-0">
              <p className="font-semibold text-xs text-[var(--text-primary)] truncate">
                {String(acc.displayName || 'Chủ xe Pinova')}
              </p>
              <div className="flex items-center gap-1.5 text-[11px] text-[var(--text-secondary)]">
                <span className="truncate" title={emailStr}>
                  {isRevealed ? emailStr : maskEmail(emailStr)}
                </span>
                {acc.email && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      setRevealedEmails((prev) => ({ ...prev, [acc.uid]: !prev[acc.uid] }));
                    }}
                    className="text-[var(--text-muted)] hover:text-[var(--text-primary)] p-0.5 rounded"
                    title={isRevealed ? 'Ẩn bớt email' : 'Hiện đầy đủ email'}
                    aria-label={isRevealed ? 'Ẩn bớt email' : 'Hiện đầy đủ email'}
                  >
                    {isRevealed ? <EyeOff className="w-3 h-3" /> : <Eye className="w-3 h-3" />}
                  </button>
                )}
              </div>
            </div>
          </div>
        );
      },
    },
    {
      key: 'plan',
      header: 'Gói',
      width: '15%',
      render: (acc) => (
        <PlanBadge planIdOrName={String(acc.tier || (acc.isAdmin ? 'Pinova Plus' : 'free'))} />
      ),
    },
    {
      key: 'status',
      header: 'Trạng thái',
      width: '16%',
      render: (acc) => (
        <StatusBadge
          label={
            acc.authOnly
              ? 'Chờ xác minh'
              : acc.status === 'disabled'
              ? 'Đang khóa'
              : 'Hoạt động'
          }
          tone={
            acc.status === 'disabled'
              ? 'danger'
              : acc.authOnly
              ? 'warning'
              : 'success'
          }
        />
      ),
    },
    {
      key: 'vehicles',
      header: 'Xe & Thiết bị',
      width: '18%',
      render: (acc) => (
        <span className="inline-flex items-center gap-1.5 tabular-nums whitespace-nowrap text-xs text-[var(--text-secondary)]">
          <Car className="h-3.5 w-3.5 text-[var(--accent-primary)] shrink-0" />
          <span>
            {Number(acc.vehicleCount ?? 0)} xe · {acc.isAdmin ? '1 thiết bị' : '0 thiết bị'}
          </span>
        </span>
      ),
    },
    {
      key: 'lastSignInAt',
      header: 'Hoạt động gần nhất',
      width: '19%',
      render: (acc) => (
        <span className="text-xs text-[var(--text-secondary)] tabular-nums whitespace-nowrap">
          {when(acc.lastSignInAt || acc.createdAt)}
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      {/* Page Header */}
      <div className="page-header flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-[22px] font-semibold tracking-tight text-[var(--text-primary)]">
            Tài khoản
          </h1>
          {developMode && (
            <p className="mt-1 text-xs text-[var(--text-muted)]">
              Quản lý chủ xe, phương tiện liên kết và trạng thái truy cập ứng dụng.
            </p>
          )}
        </div>
        <div className="flex items-center gap-2 text-xs text-[var(--text-secondary)]">
          <Users className="w-4 h-4 text-[var(--accent-primary)]" />
          <span className="tabular-nums font-medium">{counts.total} tài khoản</span>
        </div>
      </div>

      {error && (
        <div
          role="alert"
          className="flex items-start gap-3 rounded-xl border border-rose-500/30 bg-rose-500/10 p-3 text-xs text-rose-400"
        >
          <AlertCircle className="h-4 w-4 shrink-0 text-rose-400 mt-0.5" />
          <span>{error}</span>
        </div>
      )}

      {/* Single-Row Filter Bar */}
      <FilterBar
        searchQuery={query}
        onSearchChange={setQuery}
        searchPlaceholder="Tìm tên chủ xe, email hoặc UID..."
        statusFilter={status}
        onStatusChange={setStatus}
        statusTabs={[
          { id: 'all', label: 'Tất cả', count: counts.total },
          { id: 'active', label: 'Hoạt động', count: counts.active },
          { id: 'disabled', label: 'Đang khóa', count: counts.disabled },
          ...(counts.authOnly > 0 ? [{ id: 'auth_only', label: 'Chờ xác minh', count: counts.authOnly }] : []),
        ]}
        density={density}
        onDensityChange={setDensity}
        onRefresh={() => void load(cursor)}
        refreshing={loading}
      />

      {/* Data Table Surface (5 columns + ⋯ menu) */}
      <DataTableSurface
        columns={columns}
        data={accounts}
        loading={loading}
        density={density}
        keyExtractor={(acc) => acc.uid}
        onRowClick={(acc) => setSelectedUid(acc.uid)}
        emptyMessage="Không tìm thấy tài khoản nào khớp với bộ lọc."
        rowActions={(acc) => (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                size="sm"
                variant="ghost"
                onClick={(e) => e.stopPropagation()}
                className="h-8 w-8 p-0 text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                aria-label="Mở menu thao tác tài khoản"
                title="Thao tác khác"
              >
                <MoreHorizontal className="w-4 h-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="w-48 bg-[var(--bg-elevated)] border-[var(--border-strong)] text-xs"
            >
              <DropdownMenuItem
                onSelect={() => setSelectedUid(acc.uid)}
                className="cursor-pointer text-xs"
              >
                Xem hồ sơ & thiết bị
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                disabled={Boolean(acc.isAdmin)}
                onSelect={() => setSelectedUid(acc.uid)}
                className="cursor-pointer text-xs text-rose-400"
              >
                Khóa hoặc thu hồi phiên...
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        )}
        pagination={
          nextCursor
            ? {
                currentPage: 1,
                totalPages: 2,
                totalRecords: accounts.length,
                onPageChange: () => void load(nextCursor, false),
                rangeText: `Đã tải ${accounts.length} tài khoản`,
              }
            : undefined
        }
      />

      {/* Entity Drawer Detail */}
      {selectedUid && (
        <UserDetailDrawer
          uid={selectedUid}
          onClose={() => setSelectedUid('')}
          onChanged={() => load(cursor)}
        />
      )}
    </div>
  );
}
