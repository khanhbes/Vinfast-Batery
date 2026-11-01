import React, { useEffect } from 'react';
import { Maximize2, Minimize2, X } from 'lucide-react';

export interface EntityDrawerProps {
  open: boolean;
  onClose: () => void;
  title: string;
  subtitle?: string;
  badge?: React.ReactNode;
  actions?: React.ReactNode;
  children: React.ReactNode;
  footer?: React.ReactNode;
  allowExpand?: boolean;
}

export const EntityDrawer: React.FC<EntityDrawerProps> = ({
  open,
  onClose,
  title,
  subtitle,
  badge,
  actions,
  children,
  footer,
  allowExpand = true,
}) => {
  const [expanded, setExpanded] = React.useState(false);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && open) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex justify-end bg-black/60 backdrop-blur-[2px] animate-fadeIn"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className={`h-full flex flex-col bg-[var(--bg-surface)] border-l border-[var(--border-strong)] shadow-2xl transition-all duration-200 animate-drawer-enter overflow-hidden ${
          expanded ? 'w-full max-w-4xl' : 'w-full max-w-xl'
        }`}
      >
        {/* Drawer Header */}
        <div className="flex items-start justify-between gap-4 p-5 border-b border-[var(--border-hairline)] bg-[var(--bg-elevated)] shrink-0">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2.5 flex-wrap">
              <h2 className="text-base font-semibold text-[var(--text-primary)] truncate">
                {title}
              </h2>
              {badge}
            </div>
            {subtitle && (
              <p className="text-xs text-[var(--text-secondary)] mt-1 truncate">{subtitle}</p>
            )}
          </div>

          <div className="flex items-center gap-1 shrink-0">
            {allowExpand && (
              <button
                type="button"
                onClick={() => setExpanded((prev) => !prev)}
                title={expanded ? 'Thu nhỏ' : 'Mở rộng'}
                aria-label={expanded ? 'Thu nhỏ' : 'Mở rộng'}
                className="p-1.5 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface)] transition-colors"
              >
                {expanded ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
              </button>
            )}
            <button
              type="button"
              onClick={onClose}
              title="Đóng bảng chi tiết (Esc)"
              aria-label="Đóng bảng chi tiết"
              className="p-1.5 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-surface)] transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Quick Action Bar (Optional) */}
        {actions && (
          <div className="flex items-center gap-2 p-3 px-5 border-b border-[var(--border-hairline)] bg-[var(--bg-canvas)] shrink-0 overflow-x-auto thin-scrollbar">
            {actions}
          </div>
        )}

        {/* Drawer Body (Scrollable) */}
        <div className="flex-1 overflow-y-auto p-5 thin-scrollbar space-y-5 text-xs text-[var(--text-primary)]">
          {children}
        </div>

        {/* Drawer Footer (Optional) */}
        {footer && (
          <div className="p-4 px-5 border-t border-[var(--border-hairline)] bg-[var(--bg-canvas)] shrink-0 flex items-center justify-between gap-3">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
};
