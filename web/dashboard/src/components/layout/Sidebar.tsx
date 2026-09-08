import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { LayoutDashboard, Users, BrainCircuit, History, Settings, ChevronLeft, ChevronRight, BatteryCharging, LogOut } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

const navItems = [
  { icon: LayoutDashboard, label: 'Tổng quan', path: '/' },
  { icon: Users, label: 'Người dùng', path: '/users' },
  { icon: BrainCircuit, label: 'AI Center', path: '/ai' },
  { icon: History, label: 'Kiểm toán', path: '/audit' },
  { icon: Settings, label: 'Hệ thống', path: '/settings' },
];

export function Sidebar({ onSignOut }: { onSignOut: () => void }) {
  const [collapsed, setCollapsed] = useState(false);
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
      {navItems.map(({ icon: Icon, label, path }) => <NavLink
        key={path} to={path} end={path === '/'} title={label} aria-label={label}
        className={({ isActive }) => cn('sidebar-link', isActive && 'is-active')}
      >
        {({ isActive }) => <>
          {isActive && <motion.span layoutId="active-navigation" className="nav-active-surface" transition={{ duration: reduceMotion ? 0 : 0.22 }} />}
          <Icon className="relative h-5 w-5 shrink-0" aria-hidden="true" />
          <span className="nav-label relative">{label}</span>
        </>}
      </NavLink>)}
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
