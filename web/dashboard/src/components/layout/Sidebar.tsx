import { useState } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { 
  LayoutDashboard, 
  Users, 
  BrainCircuit, 
  History, 
  Settings, 
  ChevronLeft, 
  ChevronRight,
  BatteryCharging,
  LogOut
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { motion } from 'motion/react';

const navItems = [
  { icon: LayoutDashboard, label: 'Tổng quan', path: '/' },
  { icon: Users, label: 'Người dùng', path: '/users' },
  { icon: BrainCircuit, label: 'AI Center', path: '/ai' },
  { icon: History, label: 'Kiểm toán', path: '/audit' },
  { icon: Settings, label: 'Hệ thống', path: '/settings' },
];

export function Sidebar() {
  const [isCollapsed, setIsCollapsed] = useState(false);
  const location = useLocation();

  return (
    <motion.aside
      initial={false}
      animate={{ width: isCollapsed ? 80 : 220 }}
      className={cn(
        "h-screen bg-surface text-muted-foreground flex flex-col border-r border-border sticky top-0 z-50",
        isCollapsed ? "items-center" : "items-stretch"
      )}
    >
      <div className="p-6 flex items-center gap-3 overflow-hidden">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0 border border-primary/20 shadow-[0_0_15px_rgba(0,209,255,0.1)]">
          <BatteryCharging className="text-primary w-6 h-6" />
        </div>
        {!isCollapsed && (
          <motion.span 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="font-bold text-lg text-primary tracking-tight whitespace-nowrap"
          >
            VinFast BMS
          </motion.span>
        )}
      </div>

      <nav className="flex-1 px-3 space-y-1 mt-4">
        {navItems.map((item) => {
          const isActive = location.pathname === item.path;
          return (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => cn(
                "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 group relative",
                isActive 
                  ? "bg-surface-light text-primary font-medium border-l-2 border-primary rounded-l-none" 
                  : "hover:bg-surface-light hover:text-foreground"
              )}
            >
              <item.icon className={cn("w-5 h-5", isActive ? "text-primary" : "text-muted-foreground group-hover:text-foreground")} />
              {!isCollapsed && (
                <motion.span
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  className="text-sm"
                >
                  {item.label}
                </motion.span>
              )}
            </NavLink>
          );
        })}
      </nav>

      <div className="p-4 border-t border-border">
        <Button
          variant="ghost"
          className={cn(
            "w-full justify-start gap-3 text-muted-foreground hover:text-destructive hover:bg-destructive/10",
            isCollapsed && "justify-center px-0"
          )}
        >
          <LogOut className="w-5 h-5" />
          {!isCollapsed && <span className="text-sm">Đăng xuất</span>}
        </Button>
      </div>

      <button
        onClick={() => setIsCollapsed(!isCollapsed)}
        className="absolute -right-3 top-20 w-6 h-6 bg-surface border border-border rounded-full flex items-center justify-center text-muted-foreground hover:text-primary transition-colors shadow-lg"
      >
        {isCollapsed ? <ChevronRight size={14} /> : <ChevronLeft size={14} />}
      </button>
    </motion.aside>
  );
}
