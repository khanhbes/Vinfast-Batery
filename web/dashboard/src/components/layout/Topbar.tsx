import { ChevronDown, UserRound } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

const titles: Record<string, string> = { '/': 'Tổng quan đội xe', '/users': 'Tài khoản', '/catalog': 'Danh mục xe', '/shelly': 'Thiết bị Shelly', '/develop': 'Công cụ kỹ thuật', '/data': 'Dữ liệu ứng dụng', '/ai': 'Trung tâm AI', '/audit': 'Nhật ký quản trị', '/settings': 'Cài đặt' };

export function Topbar({ userName, userEmail, onSignOut, scrolled = false }: {
  userName?: string | null; userEmail?: string | null; onSignOut: () => void; scrolled?: boolean;
}) {
  const { pathname } = useLocation();
  return <header className={cn('dashboard-topbar', scrolled && 'is-scrolled')}>
    <div className="min-w-0">
      <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">VinFast BMS</p>
      <p className="text-sm font-semibold">{titles[pathname] ?? 'Tổng quan'}</p>
    </div>
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" className="max-w-[60%] gap-2" aria-label="Mở menu tài khoản">
          <UserRound className="shrink-0 text-primary" aria-hidden="true" />
          <span className="hidden sm:block max-w-[180px]" title={userName || userEmail || 'Tài khoản'}>{userName || userEmail || 'Tài khoản'}</span>
          <ChevronDown aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-w-[calc(100vw-2rem)] w-64">
        <DropdownMenuLabel className="break-words">{userEmail || 'Tài khoản của tôi'}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild><Link to="/settings">Cài đặt hệ thống</Link></DropdownMenuItem>
        <DropdownMenuItem asChild><Link to="/audit">Nhật ký quản trị</Link></DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem className="text-destructive" onSelect={onSignOut}>Đăng xuất</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  </header>;
}
