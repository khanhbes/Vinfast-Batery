import { useState, useEffect, useCallback } from 'react';
import { toast } from 'sonner';
import {
  Plug,
  Plus,
  Copy,
  Trash2,
  RefreshCw,
  Wifi,
  Cloud,
  CheckCircle2,
  Clock,
  Check,
  Eye,
  EyeOff,
  Sparkles,
  Info,
  Layers,
} from 'lucide-react';
import {
  adminShellyDevices,
  adminSaveShellyDevice,
  adminDeleteShellyDevice,
  adminGenerateCodeForDevice,
} from '@/api';

function Badge({ variant = 'default', children }: { variant?: string; children: React.ReactNode }) {
  const colors: Record<string, string> = {
    default: 'bg-slate-100 text-slate-700',
    success: 'bg-emerald-100 text-emerald-700 border border-emerald-200',
    warning: 'bg-amber-100 text-amber-700 border border-amber-200',
    danger: 'bg-red-100 text-red-700 border border-red-200',
    info: 'bg-blue-100 text-blue-700 border border-blue-200',
    primary: 'bg-primary/10 text-primary border border-primary/20',
  };
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold ${colors[variant] || colors.default}`}>
      {children}
    </span>
  );
}

function CodeBox({ code, label = 'Mã kết nối' }: { code: string; label?: string }) {
  const [copied, setCopied] = useState(false);

  const copy = () => {
    navigator.clipboard.writeText(code);
    setCopied(true);
    toast.success(`Đã sao chép mã kết nối: ${code}`);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={copy}
        title={`Sao chép ${label.toLowerCase()}`}
        className="group relative inline-flex items-center gap-2 rounded-xl border-2 border-primary/40 bg-primary/5 px-3.5 py-2 font-mono text-xl font-extrabold tracking-[.25em] text-primary transition-all hover:scale-[1.02] hover:border-primary hover:bg-primary/10 hover:shadow-md active:scale-95"
      >
        <span>{code}</span>
        {copied ? (
          <Check className="h-4 w-4 text-emerald-600 transition-all" />
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
  const [saving, setSaving] = useState(false);
  const [generatingFor, setGeneratingFor] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [newlyCreated, setNewlyCreated] = useState<{ code: string; deviceName: string; deviceId: string } | null>(null);

  // Form for adding a dedicated Shelly
  const initialForm = {
    deviceId: '',
    deviceName: 'Shelly Trạm Sạc 1',
    model: 'S3PL-00112EU',
    cloudHost: 'https://shelly-104-eu.shelly.cloud',
    cloudAuthKey: '',
    lanAddress: '',
    localPassword: '',
    expiresHours: 720,
    maxRedemptions: 10,
    note: '',
  };
  const [form, setForm] = useState(initialForm);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const res = await adminShellyDevices();
      setDevices(res?.data || []);
    } catch (err: any) {
      toast.error('Không thể tải danh sách thiết bị Shelly: ' + (err?.message || 'Lỗi kết nối'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  // Handle Save Device & Auto Generate Code
  const handleSaveDevice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.deviceId.trim()) {
      toast.error('Vui lòng nhập Mã thiết bị (Device ID)');
      return;
    }
    if (!form.cloudAuthKey.trim() && !form.lanAddress.trim()) {
      toast.error('Vui lòng nhập Cloud Auth Key hoặc IP LAN để kết nối');
      return;
    }

    setSaving(true);
    try {
      const res = await adminSaveShellyDevice(form);
      const code = res?.data?.code || res?.code;
      const dev = res?.data?.device || res?.device || {};

      toast.success(`Đã lưu thiết bị và tạo mã kết nối: ${code}`);
      setNewlyCreated({
        code,
        deviceName: form.deviceName || dev.displayName || 'Shelly',
        deviceId: form.deviceId,
      });

      // Reset form with incremented default name
      setForm((f) => ({
        ...initialForm,
        deviceName: `Shelly Trạm Sạc ${devices.length + 2}`,
        cloudHost: f.cloudHost,
      }));

      // Refresh list below
      await refresh();
    } catch (err: any) {
      toast.error(err?.message || 'Không thể lưu thiết bị');
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
      toast.success(`Đã tạo mã mới: ${code} cho thiết bị ${dev.displayName}`);
      setNewlyCreated({
        code,
        deviceName: dev.displayName,
        deviceId: dev.deviceId,
      });
      await refresh();
    } catch (err: any) {
      toast.error(err?.message || 'Không thể tạo mã mới');
    } finally {
      setGeneratingFor(null);
    }
  };

  // Delete device
  const handleDeleteDevice = async (dev: any) => {
    if (!confirm(`Xóa thiết bị "${dev.displayName || dev.deviceId}" khỏi danh sách? Các mã kết nối liên quan sẽ bị thu hồi.`)) {
      return;
    }
    try {
      await adminDeleteShellyDevice(dev.deviceId);
      toast.success(`Đã xóa thiết bị ${dev.displayName || dev.deviceId}`);
      await refresh();
    } catch (err: any) {
      toast.error('Không thể xóa thiết bị: ' + (err?.message || 'Lỗi server'));
    }
  };

  return (
    <div className="space-y-8 pb-16">
      {/* Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between border-b pb-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2.5 text-foreground">
            <div className="rounded-xl bg-primary/10 p-2 text-primary">
              <Plug className="h-6 w-6" />
            </div>
            Quản lý thiết bị Shelly & Mã kết nối
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Nhập thông tin cho từng thiết bị Shelly. Khi bấm Lưu, hệ thống tự động sinh 1 mã kết nối và lưu vào danh sách bên dưới để Admin cấp cho người dùng.
          </p>
        </div>
        <button
          onClick={refresh}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-xl border bg-card px-4 py-2 text-sm font-medium shadow-sm transition hover:bg-muted disabled:opacity-50"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Làm mới danh sách
        </button>
      </div>

      {/* Popup banner when a new code is created */}
      {newlyCreated && (
        <div className="rounded-2xl border-2 border-emerald-500/40 bg-gradient-to-r from-emerald-500/10 via-teal-500/10 to-primary/10 p-5 shadow-lg animate-in fade-in slide-in-from-top-4">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-emerald-700 font-bold text-base">
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
                className="rounded-lg border px-3 py-1.5 text-xs font-medium hover:bg-white/80 transition"
              >
                Đóng
              </button>
            </div>
          </div>
        </div>
      )}

      {/* FUNCTION 1: DEDICATED SHELLY CREATION FORM */}
      <section className="rounded-2xl border bg-card p-6 shadow-sm">
        <div className="mb-5 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="rounded-lg bg-emerald-500/10 p-2 text-emerald-600">
              <Plus className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-foreground">Thêm mới thiết bị Shelly & Tạo mã kết nối</h2>
              <p className="text-xs text-muted-foreground">
                Mỗi khi thêm một Shelly mới (Shelly 1, Shelly 2, Shelly 3...), hệ thống sẽ lưu thông tin và tạo ngay 1 mã kết nối tương ứng.
              </p>
            </div>
          </div>
        </div>

        <form onSubmit={handleSaveDevice} className="space-y-4">
          <div className="grid gap-4 md:grid-cols-3">
            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Tên gợi nhớ / Trạm sạc <span className="text-primary">*</span>
              </label>
              <input
                type="text"
                value={form.deviceName}
                onChange={(e) => setForm((f) => ({ ...f, deviceName: e.target.value }))}
                placeholder="VD: Shelly Trạm Sạc 1"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
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
                placeholder="VD: shellyplus1pm-a8032abe1234"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm font-mono outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
                required
              />
              <span className="text-[11px] text-muted-foreground">Lấy từ mục Device Info trong Web/App Shelly</span>
            </div>

            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Dòng máy (Model)
              </label>
              <select
                value={form.model}
                onChange={(e) => setForm((f) => ({ ...f, model: e.target.value }))}
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              >
                <option value="S3PL-00112EU">Shelly Plug S Gen3 (S3PL-00112EU) [Khuyên dùng sạc EV]</option>
                <option value="SNSW-001P16EU">Shelly Plus 1PM (Đo công suất)</option>
                <option value="SPSW-001PE16EU">Shelly Pro 1PM</option>
                <option value="CUSTOM">Khác / Tùy chỉnh</option>
              </select>
            </div>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Shelly Cloud Server (Host)
              </label>
              <input
                type="url"
                value={form.cloudHost}
                onChange={(e) => setForm((f) => ({ ...f, cloudHost: e.target.value }))}
                placeholder="https://shelly-104-eu.shelly.cloud"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
              <span className="text-[11px] text-muted-foreground">Server Cloud của tài khoản Shelly của bạn</span>
            </div>

            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Mã xác thực Cloud (Authorization Cloud Key) <span className="text-primary">*</span>
              </label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={form.cloudAuthKey}
                  onChange={(e) => setForm((f) => ({ ...f, cloudAuthKey: e.target.value }))}
                  placeholder="Dán Authorization Cloud Key vào đây"
                  className="w-full rounded-xl border bg-background px-3.5 py-2.5 pr-10 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-2.5 text-muted-foreground hover:text-foreground"
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <span className="text-[11px] text-muted-foreground">Mở app Shelly → User Profile → Authorization Cloud Key</span>
            </div>
          </div>

          <div className="grid gap-4 md:grid-cols-3">
            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Địa chỉ IP LAN cục bộ (Tùy chọn)
              </label>
              <input
                type="text"
                value={form.lanAddress}
                onChange={(e) => setForm((f) => ({ ...f, lanAddress: e.target.value }))}
                placeholder="VD: 192.168.1.50"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
            </div>

            <div>
              <label className="mb-1 block text-xs font-semibold text-foreground">
                Mật khẩu thiết bị cục bộ (Tùy chọn)
              </label>
              <input
                type="password"
                value={form.localPassword}
                onChange={(e) => setForm((f) => ({ ...f, localPassword: e.target.value }))}
                placeholder="Nếu có đặt mật khẩu trên Web UI"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
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
                placeholder="VD: Ổ sạc tầng 1 cho xe Feliz"
                className="w-full rounded-xl border bg-background px-3.5 py-2.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
            </div>
          </div>

          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-2">
            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Info className="h-4 w-4 text-primary" />
              <span>Khi bấm Lưu, hệ thống sẽ lưu thông tin và tự động sinh 1 mã kết nối 6 ký tự để Admin cấp cho người dùng.</span>
            </div>
            <button
              type="submit"
              disabled={saving}
              className="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-6 py-2.5 text-sm font-bold text-white shadow-md transition hover:bg-primary/90 disabled:opacity-50"
            >
              {saving ? <RefreshCw className="h-4 w-4 animate-spin" /> : <Sparkles className="h-4 w-4" />}
              {saving ? 'Đang lưu & tạo mã...' : 'Lưu thiết bị & Tạo mã kết nối'}
            </button>
          </div>
        </form>
      </section>

      {/* FUNCTION 2: LIST OF SAVED SHELLY DEVICES AND CODES */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary" />
            <h2 className="text-lg font-bold text-foreground">
              Danh sách thiết bị Shelly đã lưu ({devices.length})
            </h2>
          </div>
          <span className="text-xs text-muted-foreground">
            Mỗi thiết bị được cấp mã riêng bên dưới. Khi người dùng cần, Admin chỉ việc copy mã gửi cho họ.
          </span>
        </div>

        {loading ? (
          <div className="rounded-2xl border bg-card p-12 text-center text-muted-foreground">
            <RefreshCw className="mx-auto mb-2 h-6 w-6 animate-spin text-primary" />
            <p>Đang tải danh sách thiết bị Shelly...</p>
          </div>
        ) : devices.length === 0 ? (
          <div className="rounded-2xl border-2 border-dashed bg-card/50 p-12 text-center text-muted-foreground">
            <Plug className="mx-auto mb-3 h-10 w-10 opacity-30 text-primary" />
            <h3 className="font-semibold text-foreground text-base">Chưa có thiết bị Shelly nào được lưu</h3>
            <p className="mt-1 text-xs max-w-md mx-auto">
              Hãy nhập thông tin thiết bị Shelly đầu tiên ở khung biểu mẫu bên trên và nhấn "Lưu thiết bị & Tạo mã kết nối".
            </p>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {devices.map((dev) => (
              <div
                key={dev.deviceId}
                className="group relative flex flex-col justify-between rounded-2xl border bg-card p-5 shadow-sm transition hover:border-primary/40 hover:shadow-md"
              >
                <div>
                  {/* Top line: Name & Status */}
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <div className="rounded-lg bg-primary/10 p-2 text-primary">
                        <Plug className="h-4 w-4" />
                      </div>
                      <div>
                        <h3 className="font-bold text-base text-foreground leading-tight">
                          {dev.displayName || 'Shelly Device'}
                        </h3>
                        <p className="text-xs font-mono text-muted-foreground mt-0.5">{dev.deviceId}</p>
                      </div>
                    </div>
                    {dev.hasUsableCode ? (
                      <Badge variant="success">
                        <CheckCircle2 className="h-3 w-3" /> Sẵn sàng cấp mã
                      </Badge>
                    ) : (
                      <Badge variant="warning">
                        <Clock className="h-3 w-3" /> Cần cấp mã
                      </Badge>
                    )}
                  </div>

                  {/* Device Specs */}
                  <div className="mt-4 space-y-1.5 rounded-xl bg-muted/40 p-3 text-xs text-muted-foreground">
                    <div className="flex items-center justify-between">
                      <span className="font-medium text-foreground">Model:</span>
                      <span className="font-mono">{dev.model || 'S3PL-00112EU'}</span>
                    </div>
                    {dev.cloudHost && (
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-foreground flex items-center gap-1">
                          <Cloud className="h-3 w-3" /> Cloud:
                        </span>
                        <span className="truncate max-w-[170px]" title={dev.cloudHost}>
                          {dev.cloudHost.replace('https://', '')}
                        </span>
                      </div>
                    )}
                    {dev.lanAddress && (
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-foreground flex items-center gap-1">
                          <Wifi className="h-3 w-3" /> IP LAN:
                        </span>
                        <span>{dev.lanAddress}</span>
                      </div>
                    )}
                    {dev.note && (
                      <div className="border-t pt-1.5 text-foreground italic">
                        "{dev.note}"
                      </div>
                    )}
                  </div>

                  {/* PROMINENT CONNECTION CODE */}
                  <div className="mt-4 rounded-xl border border-primary/20 bg-primary/[0.03] p-3.5">
                    <div className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground mb-1.5 flex items-center justify-between">
                      <span>Mã kết nối hiện hành:</span>
                      {dev.activeCodeEntry && (
                        <span className="text-[10px] text-muted-foreground">
                          {dev.activeCodeEntry.redemptionCount}/{dev.activeCodeEntry.maxRedemptions} lượt
                        </span>
                      )}
                    </div>
                    {dev.latestCode ? (
                      <CodeBox code={dev.latestCode} />
                    ) : (
                      <p className="text-xs text-amber-600 font-medium">Chưa có mã kết nối nào hoạt động</p>
                    )}
                  </div>
                </div>

                {/* Bottom actions */}
                <div className="mt-5 flex items-center justify-between border-t pt-3.5">
                  <button
                    onClick={() => handleGenerateNewCode(dev)}
                    disabled={generatingFor === dev.deviceId}
                    className="inline-flex items-center gap-1.5 rounded-lg border bg-background px-3 py-1.5 text-xs font-semibold text-primary transition hover:bg-primary/5 disabled:opacity-50"
                  >
                    <RefreshCw className={`h-3.5 w-3.5 ${generatingFor === dev.deviceId ? 'animate-spin' : ''}`} />
                    {generatingFor === dev.deviceId ? 'Đang tạo...' : 'Cấp mã mới'}
                  </button>

                  <button
                    onClick={() => handleDeleteDevice(dev)}
                    className="inline-flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-medium text-destructive transition hover:bg-destructive/10"
                    title="Xóa thiết bị này"
                  >
                    <Trash2 className="h-3.5 w-3.5" /> Xóa
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
