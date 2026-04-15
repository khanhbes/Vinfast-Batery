import { Settings as SettingsIcon, AlertTriangle, Wrench, Database, Shield, HelpCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

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
