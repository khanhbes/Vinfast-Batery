import { useState, useMemo } from 'react';
import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  Users,
  BrainCircuit,
  History,
  ChevronLeft,
  ChevronRight,
  LogOut,
  CarFront,
  Cpu,
  Bot,
  Crown,
  LifeBuoy,
} from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { PinovaMark } from './PinovaMark';
import { useAdminData, datasetItems } from '@/data/AdminDataContext';

interface NavGroup {
  id: string;
  label: string;
  items: {
    icon: React.ComponentType<{ className?: string }>;
    label: string;
    path: string;
    badgeCount?: number;
  }[];
}

export function Sidebar({ onSignOut }: { onSignOut: () => void }) {
  const [collapsed, setCollapsed] = useState(false);
  const reduceMotion = useReducedMotion();
  const { snapshot } = useAdminData();

  // Dynamic alert counters for badges
  const pendingTickets = useMemo(() => {
    const tickets = datasetItems(snapshot, 'support');
    return tickets.filter((t) => String(t.status || '').toLowerCase() === 'open').length;
  }, [snapshot]);

  const offlineShelly = useMemo(() => {
    const devices = datasetItems(snapshot, 'shelly');
    return devices.filter((d) => d.online === false).length;
  }, [snapshot]);

  const navGroups: NavGroup[] = useMemo(
    () => [
      {
        id: 'core',
        label: 'Nền tảng',
        items: [
          { icon: LayoutDashboard, label: 'Tổng quan', path: '/' },
          { icon: Users, label: 'Tài khoản', path: '/users' },
          { icon: CarFront, label: 'Danh mục xe', path: '/catalog' },
          { icon: Cpu, label: 'Thiết bị Shelly', path: '/shelly', badgeCount: offlineShelly > 0 ? offlineShelly : undefined },
        ],
      },
      {
        id: 'ai_biz',
        label: 'AI & Thương mại',
        items: [
          { icon: Bot, label: 'Pinova', path: '/assistant' },
          { icon: BrainCircuit, label: 'Mô hình AI', path: '/ai' },
          { icon: Crown, label: 'Gói & Khuyến mại', path: '/premium' },
          { icon: LifeBuoy, label: 'Hỗ trợ', path: '/support', badgeCount: pendingTickets > 0 ? pendingTickets : undefined },
        ],
      },
      {
        id: 'ops',
        label: 'Hệ thống',
        items: [
          { icon: History, label: 'Nhật ký & Bảo mật', path: '/audit' },
        ],
      },
    ],
    [offlineShelly, pendingTickets]
  );

  return (
    <motion.aside
      initial={false}
      animate={{ width: collapsed ? 72 : 248 }}
      transition={{ duration: reduceMotion ? 0 : 0.2 }}
      className={cn(
        'dashboard-sidebar select-none transition-all duration-200 border-r border-[var(--border-hairline)] bg-[var(--bg-surface)] text-[var(--text-primary)]',
        collapsed && 'is-collapsed'
      )}
    >
      {/* Brand Header */}
      <div className="sidebar-brand h-14 px-4 flex items-center justify-between border-b border-[var(--border-hairline)] shrink-0">
        <NavLink to="/" className="flex items-center gap-2.5 text-left focus:outline-none min-w-0">
          <PinovaMark tile className="h-7 w-7 shrink-0 rounded-lg shadow-xs" />
          {!collapsed && (
            <span className="font-semibold text-sm tracking-tight text-[var(--text-primary)] whitespace-nowrap truncate">
              Pinova Drive
            </span>
          )}
        </NavLink>
        <button
          type="button"
          onClick={() => setCollapsed((c) => !c)}
          aria-label={collapsed ? 'Mở rộng điều hướng' : 'Thu gọn điều hướng'}
          title={collapsed ? 'Mở rộng điều hướng' : 'Thu gọn điều hướng'}
          className="hidden lg:inline-flex p-1 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)] transition-colors"
        >
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronLeft className="w-4 h-4" />}
        </button>
      </div>

      {/* Navigation Groups */}
      <nav aria-label="Điều hướng chính" className="sidebar-nav flex-1 overflow-y-auto px-2.5 py-2.5 space-y-3 thin-scrollbar">
        {navGroups.map((group) => (
          <div key={group.id} className="space-y-0.5">
            {!collapsed && (
              <div className="px-2.5 pb-1 text-[11px] font-semibold text-[var(--text-secondary)]/80 tracking-wider uppercase">
                {group.label}
              </div>
            )}
            {group.items.map(({ icon: Icon, label, path, badgeCount }) => (
              <NavLink
                key={path}
                to={path}
                end={path === '/'}
                title={collapsed ? label : undefined}
                aria-label={label}
                className={({ isActive }) =>
                  cn(
                    'relative w-full h-9 flex items-center rounded-lg text-[13px] font-medium transition-colors',
                    collapsed ? 'justify-center px-0' : 'justify-between px-2.5',
                    isActive
                      ? 'bg-[var(--accent-tint)] text-[var(--text-primary)] font-semibold'
                      : 'text-[var(--text-secondary)] hover:bg-[var(--bg-hover)] hover:text-[var(--text-primary)]'
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    {/* Active Left Indicator */}
                    {isActive && (
                      <span
                        aria-hidden="true"
                        className="absolute left-0 top-1.5 bottom-1.5 w-0.5 rounded-r bg-[var(--accent-primary)]"
                      />
                    )}

                    <div className="flex items-center gap-2.5 min-w-0">
                      <Icon
                        className={cn(
                          'w-4 h-4 shrink-0 transition-colors',
                          isActive ? 'text-[var(--accent-primary)]' : 'text-[var(--text-muted)]'
                        )}
                      />
                      {!collapsed && <span className="truncate whitespace-nowrap">{label}</span>}
                    </div>

                    {!collapsed && badgeCount !== undefined && badgeCount > 0 && (
                      <span
                        className={cn(
                          'tabular-nums text-[11px] px-1.5 py-0.2 rounded-md font-medium',
                          isActive
                            ? 'bg-[var(--accent-primary)]/20 text-[var(--accent-primary)]'
                            : 'bg-slate-500/15 text-[var(--text-secondary)]'
                        )}
                      >
                        {badgeCount}
                      </span>
                    )}

                    {collapsed && badgeCount !== undefined && badgeCount > 0 && (
                      <span className="absolute top-1.5 right-2 w-1.5 h-1.5 rounded-full bg-[var(--accent-primary)]" />
                    )}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        ))}
      </nav>

      {/* Sidebar Footer */}
      <div className="sidebar-footer p-2.5 border-t border-[var(--border-hairline)] space-y-1 shrink-0 bg-[var(--bg-canvas)]">
        <Button
          variant="ghost"
          size="sm"
          className="w-full justify-start h-8 text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)]"
          aria-label="Đăng xuất"
          title="Đăng xuất tài khoản quản trị"
          onClick={onSignOut}
        >
          <LogOut className="w-3.5 h-3.5 text-[var(--text-muted)] shrink-0" />
          {!collapsed && <span className="truncate ml-2">Đăng xuất</span>}
        </Button>
      </div>
    </motion.aside>
  );
}
