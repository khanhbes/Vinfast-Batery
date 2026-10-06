import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { LayoutDashboard, Users, BrainCircuit, History, Settings, ChevronLeft, ChevronRight, BatteryCharging, LogOut, Database, CarFront, Code2, Wrench, Plug } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { useDevelopMode } from '@/data/DevelopModeContext';

const primaryItems = [
  { icon: LayoutDashboard, label: 'Tổng quan', path: '/' },
  { icon: Users, label: 'Tài khoản', path: '/users' },
  { icon: CarFront, label: 'Danh mục xe', path: '/catalog' },
  { icon: Plug, label: 'Thiết bị Shelly', path: '/shelly' },
];
const developItems = [
  { icon: Wrench, label: 'Công cụ kỹ thuật', path: '/develop' },
  { icon: Database, label: 'Dữ liệu ứng dụng', path: '/data' },
  { icon: BrainCircuit, label: 'Trung tâm AI', path: '/ai' },
  { icon: History, label: 'Nhật ký quản trị', path: '/audit' },
  { icon: Settings, label: 'Cài đặt', path: '/settings' },
];

export function Sidebar({ onSignOut }: { onSignOut: () => void }) {
  const [collapsed, setCollapsed] = useState(false);
  const { enabled: developMode, setEnabled: setDevelopMode } = useDevelopMode();
  const reduceMotion = useReducedMotion();
  return <motion.aside
    initial={false}
    animate={{ width: collapsed ? 80 : 232 }}
    transition={{ duration: reduceMotion ? 0 : 0.24 }}
    className={cn('dashboard-sidebar', collapsed && 'is-collapsed')}
  >
    <div className="sidebar-brand flex items-center gap-3 px-5 py-6">
      <BatteryCharging className="h-9 w-9 shrink-0 text-primary" aria-hidden="true" />
      {!collapsed && <span className="whitespace-nowrap font-bold tracking-tight">VinFast BMS</span>}
    </div>
    <nav aria-label="Điều hướng chính" className="sidebar-nav">
      {primaryItems.map(({ icon: Icon, label, path }) => <NavLink
        key={path} to={path} end={path === '/'} title={label} aria-label={label}
        className={({ isActive }) => cn('sidebar-link', isActive && 'is-active')}
      >
        {({ isActive }) => <>
          {isActive && <motion.span layoutId="active-navigation" className="nav-active-surface" transition={{ duration: reduceMotion ? 0 : 0.22 }} />}
          <Icon className="relative h-5 w-5 shrink-0" aria-hidden="true" />
          <span className="nav-label relative">{label}</span>
        </>}
      </NavLink>)}
      <div className="mx-3 mt-4 border-t border-border/70 pt-3">
        <Button variant={developMode ? 'secondary' : 'ghost'} className="w-full justify-start" onClick={() => setDevelopMode(!developMode)} title="Bật/tắt chế độ kỹ thuật" aria-pressed={developMode}>
          <Code2 className="shrink-0" />{!collapsed && (developMode ? 'Chế độ kỹ thuật đang bật' : 'Chế độ kỹ thuật')}
        </Button>
      </div>
      {developMode && <div className="mt-2">{!collapsed && <p className="px-5 pb-1 text-[10px] font-semibold uppercase tracking-[.16em] text-muted-foreground">Develop</p>}{developItems.map(({ icon: Icon, label, path }) => <NavLink key={path} to={path} title={label} aria-label={label} className={({ isActive }) => cn('sidebar-link', isActive && 'is-active')}>
        {({ isActive }) => <>{isActive && <motion.span layoutId="active-navigation" className="nav-active-surface" transition={{ duration: reduceMotion ? 0 : 0.22 }} />}<Icon className="relative h-5 w-5 shrink-0" /><span className="nav-label relative">{label}</span></>}
      </NavLink>)}</div>}
    </nav>
    <div className="sidebar-footer mt-auto border-t p-3">
      <Button variant="ghost" className="w-full justify-start" aria-label="Đăng xuất" title="Đăng xuất" onClick={onSignOut}>
        <LogOut aria-hidden="true" />{!collapsed && 'Đăng xuất'}
      </Button>
      <Button variant="ghost" className="mt-2 w-full justify-start" aria-label={collapsed ? 'Mở rộng điều hướng' : 'Thu gọn điều hướng'} aria-expanded={!collapsed} title={collapsed ? 'Mở rộng điều hướng' : 'Thu gọn điều hướng'} onClick={() => setCollapsed(!collapsed)}>
        {collapsed ? <ChevronRight aria-hidden="true" /> : <ChevronLeft aria-hidden="true" />}
        {!collapsed && 'Thu gọn'}
      </Button>
    </div>
  </motion.aside>;
}
