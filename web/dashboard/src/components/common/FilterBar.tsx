import React from 'react';
import { Download, RefreshCw, Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';

export interface FilterTabOption {
  id: string;
  label: string;
  count?: number;
}

export interface FilterBarProps {
  searchQuery: string;
  onSearchChange: (query: string) => void;
  searchPlaceholder?: string;
  statusFilter?: string;
  onStatusChange?: (status: string) => void;
  statusTabs?: FilterTabOption[];
  onRefresh?: () => void;
  refreshing?: boolean;
  onExportCsv?: () => void;
  exportLoading?: boolean;
  density?: 'comfortable' | 'compact';
  onDensityChange?: (d: 'comfortable' | 'compact') => void;
  actions?: React.ReactNode;
}

export const FilterBar: React.FC<FilterBarProps> = ({
  searchQuery,
  onSearchChange,
  searchPlaceholder = 'Tìm kiếm nhanh...',
  statusFilter,
  onStatusChange,
  statusTabs = [],
  onRefresh,
  refreshing = false,
  onExportCsv,
  exportLoading = false,
  density,
  onDensityChange,
  actions,
}) => {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 p-2 rounded-xl bg-[var(--bg-surface)] border border-[var(--border-hairline)] shadow-xs">
      {/* Left: Search input + Segmented tabs */}
      <div className="flex flex-wrap items-center gap-2 flex-1 min-w-[280px]">
        {/* Search Input */}
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--text-muted)] pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder={searchPlaceholder}
            className="w-full h-8 pl-8 pr-7 text-xs bg-[var(--bg-canvas)] border border-[var(--border-hairline)] hover:border-[var(--border-strong)] rounded-lg text-[var(--text-primary)] placeholder:text-[var(--text-muted)] focus:outline-none focus:border-[var(--accent-primary)] transition-colors"
          />
          {searchQuery && (
            <button
              type="button"
              onClick={() => onSearchChange('')}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-0.5 rounded text-[var(--text-muted)] hover:text-[var(--text-primary)]"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>

        {/* Status Segmented Tabs */}
        {statusTabs.length > 0 && onStatusChange && (
          <div className="inline-flex items-center p-0.5 rounded-lg bg-[var(--bg-canvas)] border border-[var(--border-hairline)]">
            {statusTabs.map((tab) => {
              const active = (statusFilter || 'all') === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => onStatusChange(tab.id)}
                  className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                    active
                      ? 'bg-[var(--bg-surface)] text-[var(--accent-primary)] shadow-xs font-semibold'
                      : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                  }`}
                >
                  <span>{tab.label}</span>
                  {tab.count !== undefined && (
                    <span className="ml-1 text-[11px] opacity-70 tabular-nums">({tab.count})</span>
                  )}
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* Right: Refresh, Density, Export CSV & Custom Actions */}
      <div className="flex items-center gap-2">
        {density && onDensityChange && (
          <div className="hidden sm:inline-flex p-0.5 rounded-lg bg-[var(--bg-canvas)] border border-[var(--border-hairline)] text-xs">
            <button
              type="button"
              onClick={() => onDensityChange('comfortable')}
              className={`px-2 py-0.5 rounded text-[11px] ${
                density === 'comfortable'
                  ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] font-medium shadow-xs'
                  : 'text-[var(--text-muted)]'
              }`}
            >
              Chuẩn
            </button>
            <button
              type="button"
              onClick={() => onDensityChange('compact')}
              className={`px-2 py-0.5 rounded text-[11px] ${
                density === 'compact'
                  ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] font-medium shadow-xs'
                  : 'text-[var(--text-muted)]'
              }`}
            >
              Gọn
            </button>
          </div>
        )}

        {onExportCsv && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onExportCsv}
            disabled={exportLoading}
            className="h-8 gap-1.5 text-xs border-[var(--border-hairline)] hover:bg-[var(--bg-elevated)]"
          >
            <Download className="w-3.5 h-3.5 text-[var(--text-muted)]" />
            <span className="hidden sm:inline">Xuất CSV</span>
          </Button>
        )}

        {onRefresh && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onRefresh}
            disabled={refreshing}
            className="h-8 w-8 p-0 border-[var(--border-hairline)] hover:bg-[var(--bg-elevated)]"
            title="Làm mới dữ liệu"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin text-[var(--accent-primary)]' : 'text-[var(--text-muted)]'}`} />
          </Button>
        )}

        {actions}
      </div>
    </div>
  );
};
