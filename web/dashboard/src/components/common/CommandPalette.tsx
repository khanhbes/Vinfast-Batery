import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Bot,
  CarFront,
  Command,
  Cpu,
  CreditCard,
  History,
  LayoutDashboard,
  LifeBuoy,
  Sparkles,
  Users,
  X,
} from 'lucide-react';
import { useAdminData, datasetItems } from '@/data/AdminDataContext';

export interface CommandPaletteProps {
  open: boolean;
  onClose: () => void;
}

const MODULE_ROUTES = [
  { path: '/', label: 'Tổng quan', category: 'Trang điều hướng', icon: LayoutDashboard },
  { path: '/users', label: 'Tài khoản', category: 'Trang điều hướng', icon: Users },
  { path: '/catalog', label: 'Danh mục xe', category: 'Trang điều hướng', icon: CarFront },
  { path: '/shelly', label: 'Thiết bị Shelly', category: 'Trang điều hướng', icon: Cpu },
  { path: '/assistant', label: 'Pinova', category: 'Trang điều hướng', icon: Bot },
  { path: '/ai', label: 'Mô hình AI', category: 'Trang điều hướng', icon: Sparkles },
  { path: '/premium', label: 'Gói & Khuyến mại', category: 'Trang điều hướng', icon: CreditCard },
  { path: '/support', label: 'Hỗ trợ', category: 'Trang điều hướng', icon: LifeBuoy },
  { path: '/audit', label: 'Nhật ký & Bảo mật', category: 'Trang điều hướng', icon: History },
];

export const CommandPalette: React.FC<CommandPaletteProps> = ({ open, onClose }) => {
  const navigate = useNavigate();
  const { snapshot } = useAdminData();
  const [query, setQuery] = useState('');

  // Keyboard shortcut Cmd/Ctrl + K toggle
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (open) onClose();
      }
      if (e.key === 'Escape' && open) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, onClose]);

  const vehicles = useMemo(() => datasetItems(snapshot, 'vehicles'), [snapshot]);
  const chargeLogs = useMemo(() => datasetItems(snapshot, 'chargeLogs'), [snapshot]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const sections: {
      category: string;
      items: {
        id: string;
        title: string;
        subtitle: string;
        onSelect: () => void;
      }[];
    }[] = [
      { category: 'Trang điều hướng', items: [] },
      { category: 'Phương tiện trong hệ thống', items: [] },
      { category: 'Phiên sạc & Sự kiện', items: [] },
    ];

    // Filter pages
    MODULE_ROUTES.forEach((r) => {
      if (!q || r.label.toLowerCase().includes(q) || r.path.toLowerCase().includes(q)) {
        sections[0].items.push({
          id: `route_${r.path}`,
          title: r.label,
          subtitle: `Mở ${r.path}`,
          onSelect: () => {
            navigate(r.path);
            onClose();
          },
        });
      }
    });

    // Filter vehicles
    vehicles.slice(0, 30).forEach((v, idx) => {
      const name = String(v.vehicleName || v.vinfastModelName || v.model || v.vehicleId || `Xe #${idx}`);
      const plateOrVin = String(v.licensePlate || v.vin || v.vehicleId || '');
      if (!q || name.toLowerCase().includes(q) || plateOrVin.toLowerCase().includes(q)) {
        sections[1].items.push({
          id: `v_${idx}`,
          title: name,
          subtitle: plateOrVin ? `Biển số/ID: ${plateOrVin}` : 'Đã kết nối',
          onSelect: () => {
            navigate('/catalog');
            onClose();
          },
        });
      }
    });

    // Filter charge logs
    chargeLogs.slice(0, 20).forEach((c, idx) => {
      const label = String(c.sessionId || c.vehicleId || `Phiên #${idx}`);
      if (!q || label.toLowerCase().includes(q)) {
        sections[2].items.push({
          id: `cl_${idx}`,
          title: `Phiên sạc: ${label}`,
          subtitle: `Năng lượng: ${c.energyWh || c.energyConsumedWh || 0} Wh`,
          onSelect: () => {
            navigate('/data?dataset=chargeLogs');
            onClose();
          },
        });
      }
    });

    return sections
      .map((s) => ({ ...s, items: s.items.slice(0, 5) }))
      .filter((s) => s.items.length > 0);
  }, [query, vehicles, chargeLogs, navigate, onClose]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Tìm kiếm toàn cục Command Palette"
      className="fixed inset-0 z-50 flex items-start justify-center pt-20 bg-black/60 backdrop-blur-[2px] p-4 animate-fadeIn"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-xl bg-[var(--bg-surface)] border border-[var(--border-strong)] rounded-2xl shadow-2xl overflow-hidden animate-modal-enter"
      >
        <div className="flex items-center gap-3 px-4 py-3 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)]">
          <Command className="w-4 h-4 text-[var(--accent-primary)] shrink-0" />
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Tìm trang quản trị, tên xe, ID thiết bị, phiên sạc..."
            aria-label="Nhập từ khóa tìm kiếm toàn cục"
            className="w-full text-sm bg-transparent text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none"
          />
          <button
            type="button"
            onClick={onClose}
            aria-label="Đóng bảng tìm kiếm"
            className="p-1 text-[var(--text-muted)] hover:text-[var(--text-primary)]"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="max-h-96 overflow-y-auto p-2 space-y-3 thin-scrollbar">
          {results.length === 0 ? (
            <div className="p-8 text-center text-xs text-[var(--text-muted)]">
              Không tìm thấy kết quả phù hợp cho "{query}".
            </div>
          ) : (
            results.map((group) => (
              <div key={group.category} className="space-y-1">
                <div className="px-2.5 py-1 text-[11px] font-medium text-[var(--text-muted)]">
                  {group.category}
                </div>
                {group.items.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={item.onSelect}
                    className="w-full px-3 py-2 rounded-lg text-left hover:bg-[var(--bg-elevated)] flex items-center justify-between gap-4 transition-colors"
                  >
                    <div className="min-w-0">
                      <div className="text-xs font-medium text-[var(--text-primary)] truncate">
                        {item.title}
                      </div>
                      <div className="text-[11px] text-[var(--text-secondary)] truncate">
                        {item.subtitle}
                      </div>
                    </div>
                    <span className="text-[11px] text-[var(--accent-primary)] font-medium whitespace-nowrap shrink-0">
                      Mở →
                    </span>
                  </button>
                ))}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
