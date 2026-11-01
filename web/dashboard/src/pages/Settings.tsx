import {
  Cpu,
  ExternalLink,
  PlugZap,
  Server,
  ShieldCheck,
  Sliders,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { StatusBadge } from '@/components/common/StatusBadge';

export default function Settings() {
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Sliders className="h-5 w-5 text-emerald-500" />
            <span className="text-xs font-semibold uppercase tracking-wider text-emerald-500">
              Cấu hình hệ thống
            </span>
          </div>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Cài đặt & Tích hợp
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Quản trị kết nối thiết bị IoT, hạ tầng dịch vụ đám mây Azure và tham số vận hành Pinova.
          </p>
        </div>
      </div>

      {/* Primary Integration Cards */}
      <div className="grid gap-6 md:grid-cols-2">
        {/* Shelly Card */}
        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-6 flex flex-col justify-between h-full space-y-5">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3 text-emerald-400">
                  <PlugZap className="h-6 w-6" />
                </div>
                <StatusBadge label="IoT Hoạt động" tone="success" dot />
              </div>
              <div>
                <h2 className="text-lg font-bold text-foreground">
                  Thiết bị Shelly Plug S Gen3
                </h2>
                <p className="mt-1 text-xs text-muted-foreground leading-relaxed">
                  Quản lý cổng sạc thông minh, điều phối CloudDispatchGate với ngưỡng an toàn 12A / 2500W, cấp mã kết nối 6 ký tự (24h) và giám sát trạng thái trực tuyến.
                </p>
              </div>
            </div>
            <div className="pt-2 border-t border-border/40 flex items-center justify-between">
              <span className="text-xs font-mono text-muted-foreground">/shelly</span>
              <Button
                onClick={() => navigate('/shelly')}
                className="gap-2 h-9 text-xs bg-emerald-500 hover:bg-emerald-600 text-white font-medium"
              >
                Mở trang Shelly
                <ExternalLink className="h-3.5 w-3.5" />
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* AI Studio Card */}
        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-6 flex flex-col justify-between h-full space-y-5">
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <div className="rounded-xl border border-indigo-500/20 bg-indigo-500/10 p-3 text-indigo-400">
                  <Cpu className="h-6 w-6" />
                </div>
                <StatusBadge label="AI Engine v2" tone="primary" dot />
              </div>
              <div>
                <h2 className="text-lg font-bold text-foreground">
                  Trung tâm AI Studio & Model Lab
                </h2>
                <p className="mt-1 text-xs text-muted-foreground leading-relaxed">
                  Tải lên trọng số ONNX/TFLite, chạy thử nghiệm đầu vào tự động, theo dõi độ trôi (drift) và phát hành mô hình dự đoán pin xe máy điện VinFast.
                </p>
              </div>
            </div>
            <div className="pt-2 border-t border-border/40 flex items-center justify-between">
              <span className="text-xs font-mono text-muted-foreground">/ai</span>
              <Button
                variant="outline"
                onClick={() => navigate('/ai')}
                className="gap-2 h-9 text-xs"
              >
                Mở AI Studio
                <ExternalLink className="h-3.5 w-3.5" />
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Cloud & Architecture Details Card */}
      <Card className="border-border/60 bg-surface/50">
        <CardContent className="p-6 space-y-4">
          <div className="flex items-center gap-2">
            <Server className="h-5 w-5 text-emerald-500" />
            <h2 className="text-base font-bold text-foreground">
              Hạ tầng điện toán đám mây & Tiêu chuẩn bảo mật
            </h2>
          </div>
          <div className="grid gap-3 sm:grid-cols-3 pt-2">
            <div className="rounded-xl border border-border/60 bg-canvas p-3.5 space-y-1">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                Cổng API Backend
              </span>
              <p className="font-mono text-xs font-semibold text-foreground">
                Flask API 2026.10
              </p>
              <p className="text-[11px] text-muted-foreground">Port 5000 / Azure Container Apps</p>
            </div>

            <div className="rounded-xl border border-border/60 bg-canvas p-3.5 space-y-1">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                Cơ sở dữ liệu
              </span>
              <p className="font-mono text-xs font-semibold text-foreground">
                Firestore Multi-region
              </p>
              <p className="text-[11px] text-muted-foreground">users, vehicles, telemetry</p>
            </div>

            <div className="rounded-xl border border-border/60 bg-canvas p-3.5 space-y-1">
              <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                Shelly Dispatch State
              </span>
              <p className="font-mono text-xs font-semibold text-foreground">
                Azure Table Storage
              </p>
              <p className="text-[11px] text-muted-foreground">Lease worker & In-flight gate 1.1s</p>
            </div>
          </div>

          <div className="flex items-start gap-2 pt-2 text-xs text-muted-foreground">
            <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-500 mt-0.5" />
            <span>
              Mọi thay đổi cấu hình quan trọng đều được ghi nhận trực tiếp vào Nhật ký kiểm toán (/audit) để đảm bảo tuân thủ tiêu chuẩn Enterprise SaaS.
            </span>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
