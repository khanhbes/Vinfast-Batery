import { useEffect, useState } from 'react';
import { Settings as SettingsIcon, AlertTriangle, Wrench, Database, Shield, HelpCircle, PlugZap } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { shellyProfiles, saveShellyProfile, revokeShellyProfile } from '@/api';

function SmartChargerVaultCard() {
  const [profiles, setProfiles] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [form, setForm] = useState({ vehicleId: '', deviceId: '', cloudHost: '', cloudAuthKey: '', lanAddress: '', localUsername: 'admin', localPassword: '' });

  const refresh = async () => {
    setLoading(true);
    try {
      const result = await shellyProfiles(form.vehicleId);
      setProfiles(result?.data?.items || []);
    } catch {
      setMessage('Không thể tải cấu hình Smart Charger.');
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => { refresh(); }, []);

  const update = (key: string, value: string) => setForm(current => ({ ...current, [key]: value }));
  const save = async () => {
    if (!form.deviceId || !form.cloudHost || !form.cloudAuthKey) {
      setMessage('Nhập Device ID, Cloud host và Authorization Cloud Key.');
      return;
    }
    setLoading(true);
    try {
      await saveShellyProfile(form.deviceId, { ...form, source: 'web' });
      setMessage('Đã lưu cấu hình mã hóa. Android sẽ kiểm tra LAN/no-load trước khi kích hoạt.');
      setForm(current => ({ ...current, cloudAuthKey: '', localPassword: '' }));
      await refresh();
    } catch {
      setMessage('Không thể lưu cấu hình. Kiểm tra vault server và quyền tài khoản.');
    } finally {
      setLoading(false);
    }
  };

  return <Card className="border-border/50 bg-surface/50 backdrop-blur-sm md:col-span-2 lg:col-span-3">
    <CardHeader>
      <div className="flex items-center gap-3"><div className="p-2 bg-emerald-100 rounded-lg"><PlugZap className="w-5 h-5 text-emerald-600" /></div><div><CardTitle className="text-lg">Smart Charger</CardTitle><CardDescription>Vault mã hóa cấu hình Shelly theo tài khoản và xe</CardDescription></div></div>
    </CardHeader>
    <CardContent className="space-y-4">
      <p className="text-sm text-muted-foreground">Cloud key và mật khẩu LAN chỉ dùng để ghi vào vault mã hóa; chúng không được hiển thị lại hoặc lưu trong Firestore metadata.</p>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        {[['vehicleId', 'Vehicle ID'], ['deviceId', 'Shelly Device ID'], ['cloudHost', 'Shelly Cloud host'], ['lanAddress', 'LAN IP / .local'], ['localUsername', 'Local username']].map(([key, label]) => <input key={key} value={(form as any)[key]} onChange={e => update(key, e.target.value)} placeholder={label} className="rounded-md border bg-background px-3 py-2 text-sm" />)}
        <input value={form.cloudAuthKey} onChange={e => update('cloudAuthKey', e.target.value)} placeholder="Authorization Cloud Key" type="password" autoComplete="new-password" className="rounded-md border bg-background px-3 py-2 text-sm" />
        <input value={form.localPassword} onChange={e => update('localPassword', e.target.value)} placeholder="Mật khẩu LAN (nếu có)" type="password" autoComplete="new-password" className="rounded-md border bg-background px-3 py-2 text-sm" />
      </div>
      <div className="flex flex-wrap gap-2"><Button onClick={save} disabled={loading}>Lưu mã hóa</Button><Button variant="outline" onClick={refresh} disabled={loading}>Quét lại</Button>{message && <span className="text-sm text-muted-foreground self-center">{message}</span>}</div>
      <div className="space-y-2">{profiles.length === 0 ? <p className="text-sm text-muted-foreground">Chưa có Shelly đã lưu cho tài khoản/xe này.</p> : profiles.map(profile => <div key={profile.deviceId} className="flex items-center justify-between rounded-md border p-3 text-sm"><span>{profile.displayName || 'Shelly'} · {profile.deviceId} · rev {profile.revision}</span><div className="flex gap-2 items-center"><Badge variant="outline">{profile.noLoadTestVerified ? 'Đã xác minh' : 'Chờ xác minh'}</Badge><Button variant="outline" size="sm" onClick={async () => { await revokeShellyProfile(profile.deviceId); await refresh(); }}>Thu hồi</Button></div></div>)}</div>
    </CardContent>
  </Card>;
}

export default function Settings() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">Cài đặt hệ thống</h1>
          <p className="text-muted-foreground mt-1">Quản lý cấu hình và thiết lập hệ thống VinFast BMS</p>
        </div>
      </div>

      {/* Settings Categories */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <SmartChargerVaultCard />
        {/* General Settings */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 rounded-lg">
                <SettingsIcon className="w-5 h-5 text-blue-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Cài đặt chung</CardTitle>
                <CardDescription>Thiết lập hệ thống cơ bản</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">Ngôn ngữ</span>
                <Badge variant="outline">Tiếng Việt</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">Múi giờ</span>
                <Badge variant="outline">GMT+7</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Chỉnh sửa
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Database Settings */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-green-100 rounded-lg">
                <Database className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Cơ sở dữ liệu</CardTitle>
                <CardDescription>Quản lý kết nối và backup</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">Trạng thái</span>
                <Badge className="bg-green-100 text-green-800">Đang hoạt động</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">Backup cuối</span>
                <Badge variant="outline">2 giờ trước</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Quản lý
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Security Settings */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-purple-100 rounded-lg">
                <Shield className="w-5 h-5 text-purple-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Bảo mật</CardTitle>
                <CardDescription>Cài đặt bảo mật hệ thống</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">2FA</span>
                <Badge className="bg-green-100 text-green-800">Đã bật</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">SSL</span>
                <Badge className="bg-green-100 text-green-800">Đã kích hoạt</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Cấu hình
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Maintenance */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-orange-100 rounded-lg">
                <Wrench className="w-5 h-5 text-orange-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Bảo trì</CardTitle>
                <CardDescription>Lịch bảo trì hệ thống</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">Lịch tiếp theo</span>
                <Badge variant="outline">Chưa lên lịch</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">Trạng thái</span>
                <Badge className="bg-green-100 text-green-800">Hoạt động</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Lên lịch
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Alerts */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-red-100 rounded-lg">
                <AlertTriangle className="w-5 h-5 text-red-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Cảnh báo</CardTitle>
                <CardDescription>Cấu hình hệ thống cảnh báo</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">Email alerts</span>
                <Badge className="bg-green-100 text-green-800">Đã bật</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">SMS alerts</span>
                <Badge variant="outline">Đang phát triển</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Cài đặt
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Help */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="p-2 bg-indigo-100 rounded-lg">
                <HelpCircle className="w-5 h-5 text-indigo-600" />
              </div>
              <div>
                <CardTitle className="text-lg">Trợ giúp</CardTitle>
                <CardDescription>Tài liệu và hỗ trợ</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm">Documentation</span>
                <Badge variant="outline">Đang phát triển</Badge>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm">Support</span>
                <Badge variant="outline">24/7</Badge>
              </div>
              <Button variant="outline" className="w-full mt-4">
                Liên hệ
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* System Information */}
      <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <SettingsIcon className="w-5 h-5 text-primary" />
            Thông tin hệ thống
          </CardTitle>
          <CardDescription>
            Thông tin phiên bản và trạng thái hệ thống VinFast BMS
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <h4 className="font-medium text-foreground mb-2">Phiên bản</h4>
              <div className="space-y-1 text-sm text-muted-foreground">
                <p>BMS Dashboard: v2.1.0</p>
                <p>Backend API: v1.5.2</p>
                <p>AI Models: v1.0.3</p>
              </div>
            </div>
            <div>
              <h4 className="font-medium text-foreground mb-2">Hiệu suất</h4>
              <div className="space-y-1 text-sm text-muted-foreground">
                <p>CPU Usage: 45%</p>
                <p>Memory: 2.1GB / 8GB</p>
                <p>Storage: 15.3GB / 100GB</p>
              </div>
            </div>
            <div>
              <h4 className="font-medium text-foreground mb-2">Kết nối</h4>
              <div className="space-y-1 text-sm text-muted-foreground">
                <p>Vehicles: 42 / 50</p>
                <p>API Response: 120ms</p>
                <p>Uptime: 15 days 8h</p>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
