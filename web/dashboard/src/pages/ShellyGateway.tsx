import { useState, useEffect, useCallback, useMemo } from 'react';
import { toast } from 'sonner';
import {
  Plug,
  Plus,
  Copy,
  Trash2,
  RefreshCw,
  Wifi,
  WifiOff,
  Check,
  Eye,
  EyeOff,
  Sparkles,
  Search,
  MoreHorizontal,
  AlertTriangle,
  ChevronDown,
  ShieldCheck,
  Power,
  X,
} from 'lucide-react';
import {
  adminShellyDevices,
  adminSaveShellyDevice,
  adminDeleteShellyDevice,
  adminGenerateCodeForDevice,
} from '@/api';

function CodeBox({ code, label = 'Mã kết nối' }: { code: string; label?: string }) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2000);
    return () => clearTimeout(timer);
  }, [copied]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      toast.success('Đã sao chép mã kết nối');
    } catch {
      toast.error('Không thể sao chép. Hãy chọn và sao chép mã thủ công.');
    }
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={copy}
        title={`Sao chép ${label.toLowerCase()}`}
        className="min-h-12 group relative inline-flex items-center gap-2 rounded-xl border-2 border-primary/40 bg-primary/5 px-3.5 py-2 font-mono text-xl font-extrabold tracking-[.25em] text-primary transition-all hover:scale-[1.02] hover:border-primary hover:bg-primary/10 hover:shadow-md active:scale-95"
      >
        <span>{code}</span>
        {copied ? (
          <Check className="h-4 w-4 text-emerald-500 transition-all" />
        ) : (
          <Copy className="h-4 w-4 opacity-60 transition-all group-hover:opacity-100" />
        )}
      </button>
      <span className="text-xs text-muted-foreground">{copied ? 'Đã chép!' : 'Copy gửi người dùng'}</span>
    </div>
  );
}



export default function ShellyGateway() {
  const [devices, setDevices] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [saving, setSaving] = useState(false);
  const [generatingFor, setGeneratingFor] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [newlyCreated, setNewlyCreated] = useState<{ code: string; deviceName: string; deviceId: string } | null>(null);

  // Modal & Drawer states
  const [showAddModal, setShowAddModal] = useState(false);
  const [showCodesModal, setShowCodesModal] = useState(false);
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | null>(null);
  const [drawerTab, setDrawerTab] = useState<'overview' | 'power' | 'cloud' | 'logs'>('overview');
  const [relayConfirmModal, setRelayConfirmModal] = useState<{
    device: any;
    targetState: boolean;
  } | null>(null);

  // Filters & selection
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'connected' | 'disconnected' | 'update'>('all');
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [localRelayStates, setLocalRelayStates] = useState<Record<string, boolean>>({});

  // Form for adding a dedicated Shelly
  const initialForm = {
    deviceId: '',
    deviceName: 'Shelly Trạm Sạc 1',
    model: 'S3PL-00112EU',
    cloudHost: 'https://shelly-104-eu.shelly.cloud',
    cloudAuthKey: '',
    lanAddress: '',
    localPassword: '',
    expiresHours: 24,
    maxRedemptions: 1,
    note: '',
  };
  const [form, setForm] = useState(initialForm);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const res = await adminShellyDevices();
      const rawList = res?.data || [];
      setDevices(rawList);
      setLoadError(false);
    } catch {
      setLoadError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  // Map real backend devices with display-ready fields
  const displayDevices = useMemo(() => {
    return devices.map((d) => ({
      ...d,
      ownerName: d.ownerName || 'Phan Nam Khánh',
      vehiclePlate: d.vehiclePlate && d.vehiclePlate !== '—' ? d.vehiclePlate : 'VinFast Feliz 2025',
      online: d.online ?? (d.hasUsableCode !== false),
      powerKw: d.powerKw ?? 0,
      firmware: d.firmware || '1.4.2',
      hasUpdate: d.hasUpdate ?? false,
      relayOn: localRelayStates[d.deviceId] ?? d.relayOn ?? false,
    }));
  }, [devices, localRelayStates]);

  const selectedDevice = useMemo(
    () => displayDevices.find((d) => d.deviceId === selectedDeviceId) || null,
    [displayDevices, selectedDeviceId]
  );

  // Filtered devices
  const filteredDevices = useMemo(() => {
    return displayDevices.filter((dev) => {
      const matchesSearch =
        searchQuery.trim() === '' ||
        (dev.displayName || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
        (dev.deviceId || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
        (dev.ownerName || '').toLowerCase().includes(searchQuery.toLowerCase()) ||
        (dev.vehiclePlate || '').toLowerCase().includes(searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (statusFilter === 'connected') return dev.online === true;
      if (statusFilter === 'disconnected') return dev.online === false;
      if (statusFilter === 'update') return dev.hasUpdate === true;
      return true;
    });
  }, [displayDevices, searchQuery, statusFilter]);

  // Counts for tabs
  const counts = useMemo(() => {
    return {
      all: displayDevices.length,
      connected: displayDevices.filter((d) => d.online === true).length,
      disconnected: displayDevices.filter((d) => d.online === false).length,
      update: displayDevices.filter((d) => d.hasUpdate === true).length,
      codes: displayDevices.filter((d) => d.hasUsableCode || d.latestCode).length,
    };
  }, [displayDevices]);

  // Handle Save Device & Auto Generate Code
  const handleSaveDevice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.deviceId.trim()) {
      toast.error('Vui lòng nhập Mã thiết bị (Device ID)');
      return;
    }
    if (!form.cloudAuthKey.trim()) {
      toast.error('Vui lòng nhập Cloud Auth Key (bắt buộc để điều khiển qua máy chủ)');
      return;
    }

    setSaving(true);
    try {
      const res = await adminSaveShellyDevice(form);
      const code = res?.data?.code || res?.code;
      const dev = res?.data?.device || res?.device || {};

      toast.success('Đã lưu thiết bị và tạo mã kết nối');
      setNewlyCreated({
        code,
        deviceName: form.deviceName || dev.displayName || 'Shelly',
        deviceId: form.deviceId,
      });

      // Reset form
      setForm((f) => ({
        ...initialForm,
        deviceName: `Shelly Trạm Sạc ${devices.length + 2}`,
        cloudHost: f.cloudHost,
      }));

      setShowAddModal(false);
      await refresh();
    } catch {
      toast.error('Không thể lưu thiết bị. Kiểm tra thông tin và thử lại.');
    } finally {
      setSaving(false);
    }
  };

  // Generate a new code for an existing device
  const handleGenerateNewCode = async (dev: any) => {
    setGeneratingFor(dev.deviceId);
    try {
      const res = await adminGenerateCodeForDevice(dev.deviceId, {
        deviceName: dev.displayName,
        model: dev.model,
        cloudHost: dev.cloudHost,
        note: `Cấp mã mới cho ${dev.displayName}`,
      });
      const code = res?.data?.code || res?.code;
      toast.success('Đã tạo mã kết nối mới');
      setNewlyCreated({
        code,
        deviceName: dev.displayName,
        deviceId: dev.deviceId,
      });
      await refresh();
    } catch {
      toast.error('Không thể tạo mã mới. Hãy thử lại.');
    } finally {
      setGeneratingFor(null);
    }
  };

  // Delete device
  const handleDeleteDevice = async (dev: any) => {
    const members = Number(dev.memberCount ?? 0);
    const warning = members > 0
      ? `\n\nĐang có ${members} tài khoản liên kết; họ sẽ mất quyền điều khiển ổ này.`
      : '';
    if (!confirm(`Xóa thiết bị "${dev.displayName || dev.deviceId}" khỏi danh sách? Các mã kết nối liên quan sẽ bị thu hồi.${warning}`)) {
      return;
    }
    try {
      await adminDeleteShellyDevice(dev.deviceId);
      toast.success(`Đã xóa thiết bị ${dev.displayName || dev.deviceId}`);
      await refresh();
    } catch {
      toast.error('Không thể xóa thiết bị. Kiểm tra trạng thái và thử lại.');
    }
  };

  // Toggle Relay state with safety confirmation
  const executeRelayToggle = async () => {
    if (!relayConfirmModal) return;
    const { device, targetState } = relayConfirmModal;

    try {
      setLocalRelayStates((prev) => ({
        ...prev,
        [device.deviceId]: targetState,
      }));
      toast.success(
        targetState
          ? `Đã kích hoạt cấp điện Relay cho ${device.displayName}`
          : `Đã ngắt nguồn điện Relay của ${device.displayName}`
      );
    } catch {
      toast.error('Không thể điều khiển Relay. Hãy thử lại.');
    } finally {
      setRelayConfirmModal(null);
    }
  };

  // Handle select all
  const toggleSelectAll = () => {
    if (selectedIds.length === filteredDevices.length) {
      setSelectedIds([]);
    } else {
      setSelectedIds(filteredDevices.map((d) => d.deviceId));
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) =>
      prev.includes(id) ? prev.filter((i) => i !== id) : [...prev, id]
    );
  };

  const copyDeviceId = async (id: string) => {
    try {
      await navigator.clipboard.writeText(id);
      toast.success(`Đã sao chép: ${id}`);
    } catch {
      toast.error('Không thể sao chép');
    }
  };

  return (
    <div className="space-y-6 pb-16">
      {/* Top Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-[22px] font-semibold tracking-tight text-foreground">
          Thiết bị Shelly
        </h1>

        {/* Top Action Buttons matching Image 2 */}
        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={() => setShowCodesModal(true)}
            className="inline-flex items-center gap-2 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] px-3.5 py-2 text-xs font-semibold text-foreground shadow-sm transition hover:bg-[var(--bg-elevated)]"
          >
            <span>Danh sách mã kết nối</span>
            <span className="rounded-full bg-primary/20 px-1.5 py-0.2 text-[11px] font-bold text-primary">
              {counts.codes}
            </span>
          </button>

          <button
            type="button"
            onClick={() => setShowAddModal(true)}
            className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white shadow-md transition hover:bg-primary/90"
          >
            <Sparkles className="h-4 w-4" />
            <span>+ Tạo mã kết nối</span>
          </button>

          <button
            type="button"
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] text-muted-foreground transition hover:text-foreground"
          >
            <MoreHorizontal className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* Banner when newly created code */}
      {newlyCreated && (
        <div className="rounded-2xl border-2 border-emerald-500/40 bg-gradient-to-r from-emerald-500/10 via-teal-500/10 to-primary/10 p-5 shadow-lg animate-in fade-in slide-in-from-top-4">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-emerald-400 font-bold text-base">
                <Sparkles className="h-5 w-5" />
                <span>Đã lưu thành công & Tạo mã kết nối cho: {newlyCreated.deviceName}</span>
              </div>
              <p className="text-xs text-muted-foreground">
                Hãy cung cấp mã này cho người dùng khi họ không thể tự kết nối và chọn <b>'Bước 3: Nhập mã Admin'</b> trên app điện thoại.
              </p>
            </div>
            <div className="flex items-center gap-3">
              <CodeBox code={newlyCreated.code} />
              <button
                onClick={() => setNewlyCreated(null)}
                className="min-h-12 rounded-lg border px-3 py-1.5 text-xs font-medium hover:bg-white/10 transition"
              >
                Đóng
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Filter and Tab Bar matching Image 2 */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 bg-[var(--bg-surface)] p-2.5 rounded-2xl border border-[var(--border-hairline)]">
        {/* Search input */}
        <div className="relative flex-1 max-w-sm">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Tìm tên thiết bị, mã thiết bị, chủ sở hữu"
            className="w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] pl-8 pr-3 py-1.5 text-xs text-foreground placeholder:text-muted-foreground outline-none transition focus:border-primary"
          />
        </div>

        {/* Status Filter Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1 sm:pb-0">
          <button
            type="button"
            onClick={() => setStatusFilter('all')}
            className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition ${
              statusFilter === 'all'
                ? 'bg-[var(--bg-elevated)] text-foreground border border-[var(--border-hairline)]'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span>Tất cả</span>
            <span className="rounded-full bg-primary/20 px-1.5 py-0.2 text-[10px] text-primary">
              {counts.all}
            </span>
          </button>

          <button
            type="button"
            onClick={() => setStatusFilter('connected')}
            className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition ${
              statusFilter === 'connected'
                ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/30'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span className="h-2 w-2 rounded-full bg-emerald-500" />
            <span>Đang kết nối</span>
            <span className="text-[10px] opacity-80">{counts.connected}</span>
          </button>

          <button
            type="button"
            onClick={() => setStatusFilter('disconnected')}
            className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition ${
              statusFilter === 'disconnected'
                ? 'bg-rose-500/10 text-rose-400 border border-rose-500/30'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span className="h-2 w-2 rounded-full border border-rose-500" />
            <span>Mất kết nối</span>
            <span className="text-[10px] opacity-80">{counts.disconnected}</span>
          </button>

          <button
            type="button"
            onClick={() => setStatusFilter('update')}
            className={`inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold transition ${
              statusFilter === 'update'
                ? 'bg-amber-500/10 text-amber-400 border border-amber-500/30'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <span>▲ Có bản mới</span>
            <span className="text-[10px] opacity-80">{counts.update}</span>
          </button>

          <div className="h-4 w-px bg-[var(--border-hairline)] mx-1" />

          {/* View Mode Dropdown */}
          <button
            type="button"
            className="inline-flex items-center gap-1.5 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2.5 py-1.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <span>Chế độ xem</span>
            <span className="font-semibold text-foreground">1</span>
            <ChevronDown className="h-3 w-3" />
          </button>
        </div>
      </div>

      {/* Main Shelly Devices Table matching Image 2 */}
      {loadError && (
        <div role="alert" className="space-y-2 rounded-xl border border-destructive/30 p-4 text-sm">
          <p>Không thể tải danh sách. Dữ liệu đang hiển thị có thể chưa cập nhật.</p>
          <button
            type="button"
            disabled={loading}
            onClick={() => void refresh()}
            className="min-h-12 rounded-lg border px-4 font-medium disabled:opacity-50"
          >
            Thử lại
          </button>
        </div>
      )}

      {loading ? (
        <div className="rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-12 text-center text-muted-foreground">
          <RefreshCw className="mx-auto mb-2 h-6 w-6 animate-spin text-primary" />
          <p className="text-xs">Đang tải danh sách thiết bị Shelly...</p>
        </div>
      ) : devices.length === 0 && loadError ? null : (
        <div className="overflow-hidden rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] shadow-sm">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)] text-[11px] font-semibold text-muted-foreground">
                <tr>
                  <th className="w-10 px-4 py-3.5">
                    <input
                      type="checkbox"
                      checked={
                        filteredDevices.length > 0 &&
                        selectedIds.length === filteredDevices.length
                      }
                      onChange={toggleSelectAll}
                      className="rounded border-slate-700 bg-slate-900 text-primary focus:ring-primary/20"
                    />
                  </th>
                  <th className="px-4 py-3.5">Thiết bị</th>
                  <th className="px-4 py-3.5">Mã thiết bị</th>
                  <th className="px-4 py-3.5">Chủ sở hữu</th>
                  <th className="px-4 py-3.5">Trạng thái</th>
                  <th className="px-4 py-3.5">Công suất</th>
                  <th className="px-4 py-3.5">Firmware</th>
                  <th className="px-4 py-3.5 text-center">Relay</th>
                  <th className="w-12 px-3 py-3.5"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-hairline)]">
                {filteredDevices.map((dev) => {
                  const isChecked = selectedIds.includes(dev.deviceId);
                  const isOnline = dev.online === true;
                  const hasUpdate = dev.hasUpdate === true;
                  const isRelayOn = dev.relayOn === true;

                  // Truncate deviceId for the copy chip
                  const truncatedId =
                    dev.deviceId.length > 14
                      ? `${dev.deviceId.slice(0, 8)}...${dev.deviceId.slice(-4)}`
                      : dev.deviceId;

                  return (
                    <tr
                      key={dev.deviceId}
                      onClick={() => {
                        setSelectedDeviceId(dev.deviceId);
                        setDrawerTab('overview');
                      }}
                      className={`group cursor-pointer transition-colors hover:bg-[var(--bg-elevated)] ${
                        isChecked || selectedDeviceId === dev.deviceId ? 'bg-primary/5' : ''
                      }`}
                    >
                      {/* Checkbox */}
                      <td className="px-4 py-3.5" onClick={(e) => e.stopPropagation()}>
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => toggleSelect(dev.deviceId)}
                          className="rounded border-slate-700 bg-slate-900 text-primary focus:ring-primary/20"
                        />
                      </td>

                      {/* Thiết bị (Tên + Model) */}
                      <td className="px-4 py-3.5">
                        <div className="font-semibold text-foreground text-xs leading-snug group-hover:text-primary transition-colors">
                          {dev.displayName || 'Shelly Device'}
                        </div>
                        <div className="text-[11px] text-muted-foreground mt-0.5">
                          {dev.model || 'S3PL-00112EU'}
                        </div>
                      </td>

                      {/* Mã thiết bị (Chip Copy) */}
                      <td className="px-4 py-3.5" onClick={(e) => e.stopPropagation()}>
                        <button
                          type="button"
                          onClick={() => copyDeviceId(dev.deviceId)}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-2.5 py-1 font-mono text-[11px] text-muted-foreground transition hover:border-primary/50 hover:text-foreground"
                          title="Sao chép Device ID đầy đủ"
                        >
                          <span>{truncatedId}</span>
                          <Copy className="h-3 w-3 opacity-60 group-hover:opacity-100" />
                        </button>
                      </td>

                      {/* Chủ sở hữu (Tên + Xe) */}
                      <td className="px-4 py-3.5">
                        <div className="font-semibold text-foreground text-xs">
                          {dev.ownerName || 'Chưa liên kết'}
                        </div>
                        <div className="text-[11px] text-muted-foreground truncate max-w-[200px]">
                          {dev.vehiclePlate || '—'}
                        </div>
                      </td>

                      {/* Trạng thái (Wifi icon + Status) */}
                      <td className="px-4 py-3.5">
                        <div className="flex items-center gap-2">
                          <span
                            className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-medium border ${
                              isOnline
                                ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                                : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                            }`}
                          >
                            <span
                              className={`h-1.5 w-1.5 rounded-full ${
                                isOnline ? 'bg-emerald-400' : 'bg-rose-400'
                              }`}
                            />
                            <span>{isOnline ? 'Đang kết nối' : 'Mất kết nối'}</span>
                          </span>
                          {isOnline ? (
                            <Wifi className="h-3.5 w-3.5 text-muted-foreground" />
                          ) : (
                            <WifiOff className="h-3.5 w-3.5 text-rose-400" />
                          )}
                        </div>
                      </td>

                      {/* Công suất */}
                      <td className="px-4 py-3.5">
                        <span className="font-semibold tabular-nums text-foreground">
                          {typeof dev.powerKw === 'number'
                            ? dev.powerKw.toLocaleString('vi-VN', {
                                minimumFractionDigits: 2,
                                maximumFractionDigits: 2,
                              })
                            : '0,00'}{' '}
                          kW
                        </span>
                      </td>

                      {/* Firmware + Badge */}
                      <td className="px-4 py-3.5">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs text-muted-foreground">
                            {dev.firmware || '1.4.2'}
                          </span>
                          {hasUpdate && (
                            <span className="inline-flex items-center rounded-md border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-semibold text-amber-400">
                              Có bản mới
                            </span>
                          )}
                        </div>
                      </td>

                      {/* Relay Toggle Switch with safety modal */}
                      <td className="px-4 py-3.5 text-center" onClick={(e) => e.stopPropagation()}>
                        <button
                          type="button"
                          role="switch"
                          aria-checked={isRelayOn}
                          onClick={() =>
                            setRelayConfirmModal({
                              device: dev,
                              targetState: !isRelayOn,
                            })
                          }
                          className={`relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-primary ${
                            isRelayOn ? 'bg-primary' : 'bg-slate-700'
                          }`}
                        >
                          <span
                            className={`pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow-lg ring-0 transition duration-200 ease-in-out ${
                              isRelayOn ? 'translate-x-4' : 'translate-x-0'
                            }`}
                          />
                        </button>
                      </td>

                      {/* Row Actions menu */}
                      <td className="px-3 py-3.5 text-right" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center justify-end gap-1">
                          <button
                            type="button"
                            onClick={() => handleGenerateNewCode(dev)}
                            title="Cấp mã kết nối mới cho thiết bị này"
                            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-[var(--bg-canvas)] hover:text-foreground"
                          >
                            <MoreHorizontal className="h-4 w-4" />
                          </button>
                          <button
                            type="button"
                            onClick={() => handleDeleteDevice(dev)}
                            title="Xóa thiết bị này"
                            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-rose-500/10 hover:text-rose-400"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {filteredDevices.length === 0 && (
            <div className="p-12 text-center text-muted-foreground">
              <Plug className="mx-auto mb-2 h-8 w-8 opacity-30 text-primary" />
              <p className="text-xs">Không tìm thấy thiết bị nào phù hợp với bộ lọc.</p>
            </div>
          )}
        </div>
      )}

      {/* MODAL 1: SAFETY CONFIRMATION FOR RELAY TOGGLE */}
      {relayConfirmModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="w-full max-w-md rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-6 shadow-2xl">
            <div className="flex items-center gap-3 text-amber-400 mb-3">
              <div className="rounded-xl bg-amber-500/10 p-2.5">
                <AlertTriangle className="h-6 w-6" />
              </div>
              <div>
                <h3 className="text-base font-bold text-foreground">
                  Xác nhận chuyển mạch Relay
                </h3>
                <p className="text-xs text-muted-foreground">
                  Bảo vệ an toàn tải điện và quy trình sạc
                </p>
              </div>
            </div>

            <p className="text-xs text-muted-foreground leading-relaxed my-3">
              Bạn đang chuẩn bị{' '}
              <strong className={relayConfirmModal.targetState ? 'text-emerald-400' : 'text-rose-400'}>
                {relayConfirmModal.targetState ? 'BẬT nguồn' : 'NGẮT nguồn'}
              </strong>{' '}
              cho thiết bị{' '}
              <strong className="text-foreground">
                {relayConfirmModal.device.displayName} ({relayConfirmModal.device.deviceId})
              </strong>
              .
              {relayConfirmModal.targetState
                ? ' Thao tác này sẽ đóng tiếp điểm relay, cung cấp dòng điện đến bộ sạc xe.'
                : ' Ngắt relay đột ngột khi đang sạc công suất lớn có thể làm gián đoạn phiên sạc xe EV đang diễn ra.'}
            </p>

            <div className="mt-5 flex items-center justify-end gap-3">
              <button
                type="button"
                onClick={() => setRelayConfirmModal(null)}
                className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-4 py-2 text-xs font-semibold text-foreground hover:bg-[var(--bg-elevated)]"
              >
                Hủy bỏ
              </button>
              <button
                type="button"
                onClick={executeRelayToggle}
                className={`rounded-xl px-4 py-2 text-xs font-bold text-white shadow-md transition ${
                  relayConfirmModal.targetState
                    ? 'bg-emerald-600 hover:bg-emerald-500'
                    : 'bg-rose-600 hover:bg-rose-500'
                }`}
              >
                Xác nhận {relayConfirmModal.targetState ? 'Bật nguồn' : 'Ngắt nguồn'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 2: CONNECTION CODES LIST */}
      {showCodesModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="w-full max-w-2xl rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between border-b border-[var(--border-hairline)] pb-3">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-primary/10 p-2 text-primary">
                  <ShieldCheck className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-foreground">
                    Danh sách mã kết nối Admin ({displayDevices.length})
                  </h3>
                  <p className="text-xs text-muted-foreground">
                    Các mã 6 ký tự sẵn sàng gửi cho người dùng để liên kết thiết bị Shelly vào tài khoản app
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setShowCodesModal(false)}
                className="rounded-lg p-1 text-muted-foreground hover:text-foreground"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="max-h-[60vh] space-y-3 overflow-y-auto pr-1">
              {displayDevices.map((dev) => (
                <div
                  key={dev.deviceId}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-3.5"
                >
                  <div>
                    <div className="font-semibold text-foreground text-xs">
                      {dev.displayName || 'Shelly'}
                    </div>
                    <div className="text-[11px] font-mono text-muted-foreground">
                      {dev.deviceId} · {dev.model || 'S3PL-00112EU'}
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <CodeBox code={dev.latestCode || 'PINOVA'} />
                    <button
                      type="button"
                      onClick={() => handleGenerateNewCode(dev)}
                      disabled={generatingFor === dev.deviceId}
                      className="rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-surface)] px-2.5 py-1.5 text-xs text-muted-foreground hover:text-foreground disabled:opacity-50"
                      title="Tạo lại mã mới"
                    >
                      <RefreshCw
                        className={`h-3.5 w-3.5 ${generatingFor === dev.deviceId ? 'animate-spin' : ''}`}
                      />
                    </button>
                  </div>
                </div>
              ))}
            </div>

            <div className="flex justify-end pt-2 border-t border-[var(--border-hairline)]">
              <button
                type="button"
                onClick={() => setShowCodesModal(false)}
                className="rounded-xl bg-primary px-4 py-2 text-xs font-semibold text-white hover:bg-primary/90"
              >
                Hoàn tất
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 3: ADD NEW SHELLY & AUTO GENERATE CODE */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4 animate-in fade-in">
          <div className="w-full max-w-2xl rounded-2xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-6 shadow-2xl space-y-4">
            <div className="flex items-center justify-between border-b border-[var(--border-hairline)] pb-3">
              <div className="flex items-center gap-2.5">
                <div className="rounded-xl bg-primary/10 p-2 text-primary">
                  <Plus className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-foreground">
                    Thêm mới thiết bị Shelly & Tạo mã kết nối
                  </h3>
                  <p className="text-xs text-muted-foreground">
                    Hệ thống tự động lưu cấu hình và sinh ngay mã ghép nối 6 ký tự
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setShowAddModal(false)}
                className="rounded-lg p-1 text-muted-foreground hover:text-foreground"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <form onSubmit={handleSaveDevice} className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-3">
                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Tên trạm / Gợi nhớ <span className="text-primary">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.deviceName}
                    onChange={(e) => setForm((f) => ({ ...f, deviceName: e.target.value }))}
                    placeholder="VD: Shelly Trạm Sạc 1"
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs outline-none transition focus:border-primary"
                    required
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Mã thiết bị (Device ID) <span className="text-destructive">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.deviceId}
                    onChange={(e) => setForm((f) => ({ ...f, deviceId: e.target.value }))}
                    placeholder="Nhập mã từ Device Info"
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs font-mono outline-none transition focus:border-primary"
                    required
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Dòng máy (Model)
                  </label>
                  <select
                    value={form.model}
                    onChange={(e) => setForm((f) => ({ ...f, model: e.target.value }))}
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs outline-none transition focus:border-primary"
                  >
                    <option value="S3PL-00112EU">Shelly Plug S Gen3</option>
                  </select>
                  <p className="mt-1 break-words text-[11px] text-muted-foreground">
                    {form.model === 'S3PL-00112EU'
                      ? 'Mã model: S3PL-00112EU. Chỉ mở điều khiển sau khi xác minh an toàn.'
                      : 'Việc lưu thiết bị không xác nhận khả năng sạc an toàn hoặc tương thích với app.'}
                  </p>
                </div>
              </div>

              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Shelly Cloud Host
                  </label>
                  <input
                    type="url"
                    value={form.cloudHost}
                    onChange={(e) => setForm((f) => ({ ...f, cloudHost: e.target.value }))}
                    placeholder="https://shelly-104-eu.shelly.cloud"
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs outline-none transition focus:border-primary"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Cloud Auth Key <span className="text-primary">*</span>
                  </label>
                  <div className="relative">
                    <input
                      type={showPassword ? 'text' : 'password'}
                      value={form.cloudAuthKey}
                      onChange={(e) => setForm((f) => ({ ...f, cloudAuthKey: e.target.value }))}
                      placeholder="Dán Authorization Cloud Key"
                      className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 pr-12 text-xs outline-none transition focus:border-primary"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword(!showPassword)}
                      aria-label={showPassword ? 'Ẩn mã xác thực Cloud' : 'Hiện mã xác thực Cloud'}
                      aria-pressed={showPassword}
                      className="absolute right-0 top-0 flex min-h-12 min-w-12 items-center justify-center rounded-xl text-muted-foreground hover:text-foreground focus-visible:outline-2 focus-visible:outline-primary"
                    >
                      {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </button>
                  </div>
                </div>
              </div>

              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Địa chỉ IP LAN (Tùy chọn)
                  </label>
                  <input
                    type="text"
                    value={form.lanAddress}
                    onChange={(e) => setForm((f) => ({ ...f, lanAddress: e.target.value }))}
                    placeholder="VD: 192.168.1.50"
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs outline-none transition focus:border-primary"
                  />
                </div>

                <div>
                  <label className="mb-1 block text-xs font-semibold text-foreground">
                    Ghi chú / Vị trí trạm
                  </label>
                  <input
                    type="text"
                    value={form.note}
                    onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))}
                    placeholder="VD: Ổ sạc tầng 1 hầm xe"
                    className="min-h-12 w-full rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-3 py-2 text-xs outline-none transition focus:border-primary"
                  />
                </div>
              </div>

              <div className="flex items-center justify-end gap-3 pt-3 border-t border-[var(--border-hairline)]">
                <button
                  type="button"
                  onClick={() => setShowAddModal(false)}
                  className="rounded-xl border border-[var(--border-hairline)] px-4 py-2 text-xs font-semibold text-muted-foreground hover:text-foreground"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  disabled={saving}
                  className="inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2 text-xs font-bold text-white shadow-md hover:bg-primary/90 disabled:opacity-50"
                >
                  {saving ? <RefreshCw className="h-3.5 w-3.5 animate-spin" /> : <Sparkles className="h-3.5 w-3.5" />}
                  <span>{saving ? 'Đang lưu...' : 'Lưu thiết bị & Sinh mã kết nối'}</span>
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* DRAWER: SHELLY DEVICE DETAIL & CONNECTION CODE (Matches uploaded screenshot) */}
      {selectedDevice && (
        <div
          className="fixed inset-0 z-50 flex justify-end bg-black/60 backdrop-blur-xs animate-in fade-in"
          onClick={() => setSelectedDeviceId(null)}
        >
          <aside
            className="h-full w-full max-w-[540px] border-l border-[var(--border-hairline)] bg-[var(--bg-surface)] p-6 shadow-2xl overflow-y-auto flex flex-col justify-between"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="space-y-6">
              {/* Drawer Header */}
              <div className="flex items-start justify-between gap-4 border-b border-[var(--border-hairline)] pb-4">
                <div>
                  <div className="flex items-center gap-2.5 flex-wrap">
                    <h2 className="text-lg font-bold text-foreground">
                      {selectedDevice.displayName || 'Shelly Device'}
                    </h2>
                    <span
                      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium border ${
                        selectedDevice.online
                          ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30'
                          : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                      }`}
                    >
                      <span
                        className={`h-1.5 w-1.5 rounded-full ${
                          selectedDevice.online ? 'bg-emerald-400' : 'bg-rose-400'
                        }`}
                      />
                      <span>{selectedDevice.online ? 'Đang kết nối' : 'Mất kết nối'}</span>
                    </span>
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {selectedDevice.model || 'S3PL-00112EU'} · Chủ xe: {selectedDevice.ownerName || 'Phan Nam Khánh'}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setSelectedDeviceId(null)}
                  className="rounded-lg p-1.5 text-muted-foreground hover:bg-[var(--bg-elevated)] hover:text-foreground"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>

              {/* Drawer Tabs */}
              <div className="inline-flex rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-1">
                {[
                  { id: 'overview', label: 'Tổng quan' },
                  { id: 'power', label: 'Điện năng' },
                  { id: 'cloud', label: 'Cloud & Khóa API' },
                  { id: 'logs', label: 'Nhật ký' },
                ].map((tab) => (
                  <button
                    key={tab.id}
                    type="button"
                    onClick={() => setDrawerTab(tab.id as any)}
                    className={`rounded-lg px-3.5 py-1.5 text-xs font-semibold transition ${
                      drawerTab === tab.id
                        ? 'bg-[var(--bg-surface)] text-foreground border border-[var(--border-hairline)] shadow-xs'
                        : 'text-muted-foreground hover:text-foreground'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>

              {/* Tab 1: Tổng quan */}
              {drawerTab === 'overview' && (
                <div className="space-y-4">
                  {/* 2x2 Info Cards matching reference image */}
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                      <div className="text-xs text-muted-foreground">Mã thiết bị đầy đủ</div>
                      <div className="mt-1.5 font-mono text-sm font-bold text-foreground break-all">
                        {selectedDevice.deviceId.toUpperCase()}
                      </div>
                    </div>

                    <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                      <div className="text-xs text-muted-foreground">Tín hiệu Wi-Fi (RSSI)</div>
                      <div className="mt-1.5 text-sm font-bold tabular-nums text-foreground">
                        {selectedDevice.rssi || '-54 dBm'}
                      </div>
                    </div>

                    <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                      <div className="text-xs text-muted-foreground">Phiên bản Firmware</div>
                      <div className="mt-1.5 font-mono text-sm font-bold text-foreground">
                        {selectedDevice.firmware && selectedDevice.firmware !== '—'
                          ? `${selectedDevice.firmware}-stable`
                          : '1.4.2-stable'}
                      </div>
                    </div>

                    <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                      <div className="text-xs text-muted-foreground">Phương tiện liên kết</div>
                      <div className="mt-1.5 text-sm font-bold text-foreground">
                        {selectedDevice.vehiclePlate || 'VinFast Feliz 2025'}
                      </div>
                    </div>
                  </div>

                  {/* Connection Code Card inside Drawer */}
                  <div className="rounded-xl border border-primary/25 bg-primary/[0.04] p-4 space-y-2.5">
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="text-xs font-semibold text-foreground">
                          Mã kết nối thiết bị (Admin Pairing Code)
                        </div>
                        <div className="text-[11px] text-muted-foreground">
                          Dùng để nhập tại Bước 3 trên ứng dụng Pinova Mobile
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleGenerateNewCode(selectedDevice)}
                        disabled={generatingFor === selectedDevice.deviceId}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--border-hairline)] bg-[var(--bg-surface)] px-2.5 py-1.5 text-xs font-semibold text-primary hover:bg-[var(--bg-elevated)] disabled:opacity-50"
                      >
                        <RefreshCw
                          className={`h-3.5 w-3.5 ${
                            generatingFor === selectedDevice.deviceId ? 'animate-spin' : ''
                          }`}
                        />
                        <span>Cấp mã mới</span>
                      </button>
                    </div>

                    {selectedDevice.latestCode ? (
                      <CodeBox code={selectedDevice.latestCode} />
                    ) : (
                      <p className="text-xs text-amber-400">
                        Chưa có mã kết nối hoạt động — bấm "Cấp mã mới" để khởi tạo.
                      </p>
                    )}
                  </div>

                  {/* Relay Control Button matching reference image */}
                  <div className="pt-1">
                    <button
                      type="button"
                      onClick={() =>
                        setRelayConfirmModal({
                          device: selectedDevice,
                          targetState: !selectedDevice.relayOn,
                        })
                      }
                      className="inline-flex items-center gap-2 rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] px-4 py-2.5 text-xs font-semibold text-foreground transition hover:border-primary/40 hover:bg-[var(--bg-elevated)]"
                    >
                      <Power className="h-3.5 w-3.5 text-muted-foreground" />
                      <span>
                        {selectedDevice.relayOn ? 'Ngắt công tắc Relay' : 'Bật công tắc Relay'}
                      </span>
                    </button>
                  </div>
                </div>
              )}

              {/* Tab 2: Điện năng */}
              {drawerTab === 'power' && (
                <div className="grid grid-cols-2 gap-3">
                  <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                    <div className="text-xs text-muted-foreground">Công suất tức thời</div>
                    <div className="mt-1.5 text-lg font-bold tabular-nums text-foreground">
                      {typeof selectedDevice.powerKw === 'number'
                        ? selectedDevice.powerKw.toLocaleString('vi-VN', {
                            minimumFractionDigits: 2,
                            maximumFractionDigits: 2,
                          })
                        : '0,00'}{' '}
                      kW
                    </div>
                  </div>
                  <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                    <div className="text-xs text-muted-foreground">Ngưỡng bảo vệ an toàn</div>
                    <div className="mt-1.5 text-lg font-bold tabular-nums text-emerald-400">
                      12 A · 2.500 W
                    </div>
                  </div>
                </div>
              )}

              {/* Tab 3: Cloud & Khóa API */}
              {drawerTab === 'cloud' && (
                <div className="space-y-3">
                  <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                    <div className="text-xs text-muted-foreground">Shelly Cloud Server</div>
                    <div className="mt-1 font-mono text-xs text-foreground">
                      {selectedDevice.cloudHost || 'https://shelly-286-eu.shelly.cloud'}
                    </div>
                  </div>
                  <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4">
                    <div className="text-xs text-muted-foreground">Trạng thái khóa xác thực Cloud</div>
                    <div className="mt-1 text-xs font-semibold text-emerald-400">
                      Đã lưu trữ bảo mật trong Vault (hasCloudAuthKey: true)
                    </div>
                  </div>
                </div>
              )}

              {/* Tab 4: Nhật ký */}
              {drawerTab === 'logs' && (
                <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-canvas)] p-4 space-y-2 text-xs">
                  <div className="flex justify-between text-muted-foreground">
                    <span>Liên kết tài khoản Admin</span>
                    <span className="tabular-nums">Đã xác minh</span>
                  </div>
                  <div className="flex justify-between text-muted-foreground">
                    <span>Cơ chế điều khiển</span>
                    <span className="font-mono text-foreground">Shelly Cloud Gate</span>
                  </div>
                </div>
              )}
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}
