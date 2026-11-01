import { useState, useMemo, useRef, useEffect } from 'react';
import {
  Bell,
  ChevronDown,
  Moon,
  Search,
  Sun,
} from 'lucide-react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useAdminData, datasetItems } from '@/data/AdminDataContext';
import { CommandPalette } from '@/components/common/CommandPalette';

const titles: Record<string, string> = {
  '/': 'Tổng quan',
  '/users': 'Tài khoản',
  '/catalog': 'Danh mục xe',
  '/shelly': 'Thiết bị Shelly',
  '/assistant': 'Pinova',
  '/premium': 'Gói & Khuyến mại',
  '/support': 'Hỗ trợ',
  '/develop': 'Công cụ kỹ thuật',
  '/data': 'Dữ liệu ứng dụng',
  '/ai': 'Kết quả AI & Mô hình',
  '/audit': 'Nhật ký & Bảo mật',
  '/settings': 'Cài đặt',
};

export function Topbar({
  userName,
  userEmail,
  onSignOut,
  scrolled = false,
}: {
  userName?: string | null;
  userEmail?: string | null;
  onSignOut: () => void;
  scrolled?: boolean;
}) {
  const { pathname } = useLocation();
  const navigate = useNavigate();
  const { snapshot } = useAdminData();

  const [cmdOpen, setCmdOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);
  const notifRef = useRef<HTMLDivElement>(null);

  // Dark / Light Mode state
  const [isDark, setIsDark] = useState(() => {
    return document.documentElement.classList.contains('dark');
  });

  const toggleTheme = () => {
    const nextDark = !isDark;
    setIsDark(nextDark);
    if (nextDark) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  };

  useEffect(() => {
    const handleOutsideClick = (e: MouseEvent) => {
      if (notifRef.current && !notifRef.current.contains(e.target as Node)) {
        setNotifOpen(false);
      }
    };
    document.addEventListener('mousedown', handleOutsideClick);
    return () => document.removeEventListener('mousedown', handleOutsideClick);
  }, []);

  // Compute Actionable alerts
  const vehicles = useMemo(() => datasetItems(snapshot, 'vehicles'), [snapshot]);
  const lowBatteryVehicles = useMemo(
    () => vehicles.filter((v) => Number(v.currentBattery ?? v.soc ?? 100) < 20),
    [vehicles]
  );
  const shellyDevices = useMemo(() => datasetItems(snapshot, 'shelly'), [snapshot]);
  const offlineShelly = useMemo(
    () => shellyDevices.filter((d) => d.online === false),
    [shellyDevices]
  );
  const supportTickets = useMemo(() => datasetItems(snapshot, 'support'), [snapshot]);
  const openTickets = useMemo(
    () => supportTickets.filter((t) => String(t.status || '').toLowerCase() === 'open'),
    [supportTickets]
  );

  const totalAlerts = lowBatteryVehicles.length + offlineShelly.length + openTickets.length;

  return (
    <>
      <header
        className={cn(
          'dashboard-topbar h-14 px-4 lg:px-6 bg-[var(--bg-surface)]/90 backdrop-blur-md border-b border-[var(--border-hairline)] flex items-center justify-between gap-4 sticky top-0 z-10 select-none transition-colors',
          scrolled && 'is-scrolled shadow-xs'
        )}
      >
        {/* Left: Breadcrumb */}
        <div className="flex items-center gap-2 min-w-0">
          <Link
            to="/"
            className="text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors whitespace-nowrap"
          >
            Pinova
          </Link>
          <span className="text-xs text-[var(--text-muted)]">/</span>
          <span className="text-sm font-semibold text-[var(--text-primary)] whitespace-nowrap truncate">
            {titles[pathname] ?? 'Tổng quan'}
          </span>
        </div>

        {/* Center: Command Palette Trigger */}
        <div className="flex-1 max-w-sm hidden sm:block">
          <button
            type="button"
            onClick={() => setCmdOpen(true)}
            aria-label="Mở tìm kiếm nhanh"
            className="w-full h-8 flex items-center justify-between gap-2 px-3 text-xs text-[var(--text-muted)] bg-[var(--bg-canvas)] border border-[var(--border-hairline)] hover:border-[var(--border-strong)] rounded-lg transition-colors"
          >
            <span className="flex items-center gap-2 truncate">
              <Search className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate">Tìm trang, xe, ID thiết bị...</span>
            </span>
            <kbd className="px-1.5 py-0.5 text-[10px] font-mono bg-[var(--bg-surface)] border border-[var(--border-hairline)] rounded text-[var(--text-muted)] shrink-0">
              ⌘K
            </kbd>
          </button>
        </div>

        {/* Right Actions: Notifications, Theme Switch, Avatar Menu */}
        <div className="flex items-center gap-2 shrink-0">
          {/* Actionable Alerts Bell */}
          <div ref={notifRef} className="relative">
            <button
              type="button"
              onClick={() => setNotifOpen((prev) => !prev)}
              aria-label="Việc cần xử lý ngay"
              title="Cần xử lý ngay"
              className="relative p-2 rounded-lg text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)] transition-colors"
            >
              <Bell className="w-4 h-4" />
              {totalAlerts > 0 && (
                <span className="absolute top-1.5 right-1.5 w-2 h-2 rounded-full bg-[var(--status-danger-dot)] ring-2 ring-[var(--bg-surface)]" />
              )}
            </button>

            {/* Notification Popover */}
            {notifOpen && (
              <div className="absolute right-0 mt-2 w-80 rounded-2xl bg-[var(--bg-elevated)] border border-[var(--border-strong)] shadow-2xl p-3 z-40 space-y-2 animate-modal-enter">
                <div className="flex items-center justify-between px-1 pb-1.5 border-b border-[var(--border-hairline)]">
                  <span className="text-xs font-semibold text-[var(--text-primary)]">
                    Việc cần xử lý ({totalAlerts})
                  </span>
                  <button
                    type="button"
                    onClick={() => {
                      navigate('/');
                      setNotifOpen(false);
                    }}
                    className="text-[11px] text-[var(--accent-primary)] hover:underline"
                  >
                    Xem tổng quan
                  </button>
                </div>

                <div className="space-y-1 text-xs">
                  {openTickets.length > 0 && (
                    <button
                      type="button"
                      onClick={() => {
                        navigate('/support');
                        setNotifOpen(false);
                      }}
                      className="w-full p-2 rounded-lg hover:bg-slate-500/10 text-left flex items-center justify-between gap-2"
                    >
                      <div>
                        <div className="font-medium text-[var(--text-primary)]">
                          {openTickets.length} phiếu hỗ trợ đang chờ
                        </div>
                        <div className="text-[11px] text-[var(--text-secondary)]">
                          Khách hàng cần phản hồi kỹ thuật
                        </div>
                      </div>
                      <span className="text-[11px] text-[var(--accent-primary)] font-medium">
                        Xử lý →
                      </span>
                    </button>
                  )}

                  {offlineShelly.length > 0 && (
                    <button
                      type="button"
                      onClick={() => {
                        navigate('/shelly');
                        setNotifOpen(false);
                      }}
                      className="w-full p-2 rounded-lg hover:bg-slate-500/10 text-left flex items-center justify-between gap-2"
                    >
                      <div>
                        <div className="font-medium text-[var(--text-primary)]">
                          {offlineShelly.length} thiết bị Shelly offline
                        </div>
                        <div className="text-[11px] text-[var(--text-secondary)]">
                          Mất kết nối heartbeat với cloud
                        </div>
                      </div>
                      <span className="text-[11px] text-[var(--accent-primary)] font-medium">
                        Kiểm tra →
                      </span>
                    </button>
                  )}

                  {lowBatteryVehicles.length > 0 && (
                    <button
                      type="button"
                      onClick={() => {
                        navigate('/catalog');
                        setNotifOpen(false);
                      }}
                      className="w-full p-2 rounded-lg hover:bg-slate-500/10 text-left flex items-center justify-between gap-2"
                    >
                      <div>
                        <div className="font-medium text-[var(--text-primary)]">
                          {lowBatteryVehicles.length} xe có mức pin &lt; 20%
                        </div>
                        <div className="text-[11px] text-[var(--text-secondary)]">
                          Cần sạc pin để bảo vệ cell
                        </div>
                      </div>
                      <span className="text-[11px] text-[var(--accent-primary)] font-medium">
                        Xem xe →
                      </span>
                    </button>
                  )}

                  {totalAlerts === 0 && (
                    <div className="py-6 text-center text-xs text-[var(--text-muted)]">
                      Hệ thống hoạt động bình thường, không có cảnh báo tồn đọng.
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>

          {/* Theme Toggle (Dark / Light) */}
          <button
            type="button"
            onClick={toggleTheme}
            aria-label={isDark ? 'Chuyển sang giao diện Sáng' : 'Chuyển sang giao diện Tối'}
            title={isDark ? 'Chế độ Sáng' : 'Chế độ Tối'}
            className="p-2 rounded-lg text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-elevated)] transition-colors"
          >
            {isDark ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
          </button>

          {/* User Profile Dropdown */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="sm"
                className="h-8 max-w-[200px] gap-2 px-2 text-xs border border-[var(--border-hairline)] hover:bg-[var(--bg-elevated)]"
                aria-label="Mở menu tài khoản"
              >
                <div className="w-5 h-5 rounded-full bg-[var(--accent-primary)] text-white font-bold text-[10px] flex items-center justify-center shrink-0">
                  {(userName || userEmail || 'A')[0].toUpperCase()}
                </div>
                <span
                  className="hidden sm:inline truncate text-[var(--text-primary)] font-medium"
                  title={userName || userEmail || 'Tài khoản'}
                >
                  {userName || userEmail || 'Tài khoản'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-[var(--text-muted)] shrink-0" aria-hidden="true" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-60 bg-[var(--bg-elevated)] border-[var(--border-strong)]">
              <DropdownMenuLabel className="break-words text-xs text-[var(--text-primary)]">
                {userEmail || 'Tài khoản quản trị'}
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem asChild>
                <Link to="/audit" className="text-xs cursor-pointer">Nhật ký & Bảo mật</Link>
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem className="text-xs text-rose-500 cursor-pointer" onSelect={onSignOut}>
                Đăng xuất
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </header>

      {/* Global Command Palette */}
      <CommandPalette open={cmdOpen} onClose={() => setCmdOpen(false)} />
    </>
  );
}
