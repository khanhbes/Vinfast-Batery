import { Link } from 'react-router-dom';
import {
  BrainCircuit,
  Car,
  CreditCard,
  Database,
  History,
  LifeBuoy,
  PlugZap,
  Settings,
  ShieldCheck,
  Terminal,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { StatusBadge } from '@/components/common/StatusBadge';

const tools = [
  {
    path: '/data',
    label: 'Khám phá dữ liệu (Data Explorer)',
    description: 'Truy vấn 23 tập dữ liệu Firestore được đồng bộ giữa app và backend.',
    icon: Database,
    tag: 'Dữ liệu',
    tone: 'info' as const,
  },
  {
    path: '/ai',
    label: 'Trung tâm AI & Model Lab',
    description: 'Quản trị vòng đời mô hình, smoke test, canary và theo dõi drift.',
    icon: BrainCircuit,
    tag: 'Mô hình AI',
    tone: 'primary' as const,
  },
  {
    path: '/audit',
    label: 'Nhật ký kiểm toán (Audit Trail)',
    description: 'Truy vết toàn vẹn các hành động nhạy cảm và sự kiện quản trị.',
    icon: History,
    tag: 'Bảo mật',
    tone: 'danger' as const,
  },
  {
    path: '/shelly',
    label: 'Cổng thiết bị Shelly',
    description: 'Quản lý ổ cắm Shelly Plug S Gen3, cấp mã kết nối 6 ký tự 24h.',
    icon: PlugZap,
    tag: 'IoT Phần cứng',
    tone: 'warning' as const,
  },
  {
    path: '/catalog',
    label: 'Danh mục xe & Showroom',
    description: 'Quản lý thông số kỹ thuật xe VinFast, media showroom và định mức pin.',
    icon: Car,
    tag: 'Catalog',
    tone: 'neutral' as const,
  },
  {
    path: '/plans',
    label: 'Gói cước & Mã ưu đãi',
    description: 'Cấu hình gói Ultra/Fleet, phát hành voucher và tra cứu doanh thu.',
    icon: CreditCard,
    tag: 'Thương mại',
    tone: 'success' as const,
  },
  {
    path: '/support',
    label: 'Hỗ trợ khách hàng (SLA Desk)',
    description: 'Tiếp nhận ticket hỗ trợ, chẩn đoán lỗi app và ghi chú nội bộ.',
    icon: LifeBuoy,
    tag: 'Vận hành',
    tone: 'neutral' as const,
  },
  {
    path: '/settings',
    label: 'Tích hợp & Cấu hình',
    description: 'Cấu hình cổng Shelly Dispatch Gate, Azure Cloud và môi trường API.',
    icon: Settings,
    tag: 'Hệ thống',
    tone: 'neutral' as const,
  },
];

export default function DeveloperHub() {
  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Terminal className="h-5 w-5 text-emerald-500" />
            <span className="text-xs font-semibold uppercase tracking-wider text-emerald-500">
              Công cụ kỹ thuật
            </span>
          </div>
          <h1 className="mt-1 text-2xl font-bold tracking-tight text-foreground sm:text-3xl">
            Trung tâm phát triển (Developer Hub)
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Cổng điều hướng tập trung vào các công cụ chẩn đoán, dữ liệu kỹ thuật và hạ tầng IoT của Pinova.
          </p>
        </div>
      </div>

      {/* Grid of Tools */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {tools.map(({ path, label, description, icon: Icon, tag, tone }) => (
          <Link key={path} to={path} className="group">
            <Card className="h-full border-border/60 bg-surface/50 transition-all duration-200 hover:border-emerald-500/50 hover:bg-surface hover:shadow-md">
              <CardContent className="p-5 flex flex-col justify-between h-full space-y-4">
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="rounded-xl border border-border/60 bg-elevated/80 p-2.5 text-foreground group-hover:text-emerald-400 group-hover:border-emerald-500/30 transition-colors">
                      <Icon className="h-5 w-5" />
                    </div>
                    <StatusBadge label={tag} tone={tone} dot={false} />
                  </div>
                  <div>
                    <h3 className="font-semibold text-foreground text-sm group-hover:text-emerald-400 transition-colors">
                      {label}
                    </h3>
                    <p className="mt-1.5 text-xs text-muted-foreground line-clamp-2 leading-relaxed">
                      {description}
                    </p>
                  </div>
                </div>

                <span className="text-[11px] font-mono font-medium text-emerald-500 group-hover:underline">
                  Truy cập &rarr;
                </span>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>

      {/* Security & Access Notice */}
      <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4 flex items-start gap-3">
        <ShieldCheck className="h-5 w-5 text-emerald-500 shrink-0 mt-0.5" />
        <div className="text-xs text-muted-foreground leading-relaxed">
          <p className="font-semibold text-foreground">Chính sách bảo mật quyền quản trị (RBAC)</p>
          <p className="mt-0.5">
            Mọi yêu cầu gọi tới API backend đều được xác thực qua Firebase Admin Token. Các công cụ trong Hub luôn tuân thủ nguyên tắc không để lộ khóa bí mật nhà cung cấp hoặc dữ liệu nhạy cảm của người dùng.
          </p>
        </div>
      </div>
    </div>
  );
}
