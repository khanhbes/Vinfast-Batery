import React from 'react';
import { AlertTriangle, Inbox } from 'lucide-react';
import { Button } from '@/components/ui/button';

export interface ColumnDef<T> {
  key: string;
  header: string;
  width?: string;
  className?: string;
  render?: (item: T, index: number) => React.ReactNode;
}

export interface DataTableSurfaceProps<T> {
  columns: ColumnDef<T>[];
  data: T[];
  loading?: boolean;
  error?: string | null;
  emptyMessage?: string;
  onRetry?: () => void;
  density?: 'comfortable' | 'compact';
  onRowClick?: (item: T) => void;
  keyExtractor?: (item: T, index: number) => string;
  rowActions?: (item: T) => React.ReactNode;
  pagination?: {
    currentPage: number;
    totalPages: number;
    totalRecords?: number;
    onPageChange: (page: number) => void;
    rangeText?: string;
  };
}

export function DataTableSurface<T>({
  columns,
  data,
  loading = false,
  error = null,
  emptyMessage = 'Không có dữ liệu phù hợp với bộ lọc hiện tại.',
  onRetry,
  density = 'comfortable',
  onRowClick,
  keyExtractor = (_, idx) => String(idx),
  rowActions,
  pagination,
}: DataTableSurfaceProps<T>) {
  const rowHeightClass = density === 'compact' ? 'h-11' : 'h-14';

  return (
    <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] overflow-hidden shadow-xs">
      <div className="overflow-x-auto thin-scrollbar">
        <table className="w-full text-left text-xs border-collapse">
          <thead>
            <tr className="border-b border-[var(--border-hairline)] bg-[var(--bg-canvas)] text-[var(--text-secondary)] font-medium select-none">
              {columns.map((col) => (
                <th
                  key={col.key}
                  style={col.width ? { width: col.width } : undefined}
                  className={`px-4 py-3 whitespace-nowrap ${col.className || ''}`}
                >
                  {col.header}
                </th>
              ))}
              {rowActions && <th className="px-4 py-3 text-right w-24">Thao tác</th>}
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border-hairline)] text-[var(--text-primary)]">
            {/* Loading Skeleton */}
            {loading && (
              <>
                {Array.from({ length: 5 }).map((_, i) => (
                  <tr key={`sk_${i}`} className={`${rowHeightClass} animate-pulse bg-[var(--bg-surface)]`}>
                    {columns.map((_, cIdx) => (
                      <td key={`sk_col_${cIdx}`} className="px-4 py-2">
                        <div
                          className="h-3.5 bg-slate-500/15 rounded-md"
                          style={{ width: `${Math.max(40, 75 - (cIdx * 10))}%` }}
                        />
                      </td>
                    ))}
                    {rowActions && (
                      <td className="px-4 py-2 text-right">
                        <div className="h-3.5 w-12 bg-slate-500/15 rounded-md ml-auto" />
                      </td>
                    )}
                  </tr>
                ))}
              </>
            )}

            {/* Error State */}
            {!loading && error && (
              <tr>
                <td colSpan={columns.length + (rowActions ? 1 : 0)} className="py-12 text-center">
                  <div className="flex flex-col items-center justify-center gap-2 max-w-md mx-auto text-center px-4">
                    <div className="p-3 rounded-full bg-rose-500/10 text-rose-500">
                      <AlertTriangle className="w-6 h-6" />
                    </div>
                    <span className="text-sm font-semibold text-[var(--text-primary)]">
                      Lỗi tải dữ liệu bảng
                    </span>
                    <p className="text-xs text-[var(--text-muted)]">{error}</p>
                    {onRetry && (
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={onRetry}
                        className="mt-2 text-xs border-[var(--border-strong)]"
                      >
                        Thử tải lại
                      </Button>
                    )}
                  </div>
                </td>
              </tr>
            )}

            {/* Empty State */}
            {!loading && !error && data.length === 0 && (
              <tr>
                <td colSpan={columns.length + (rowActions ? 1 : 0)} className="py-14 text-center">
                  <div className="flex flex-col items-center justify-center gap-2 text-center px-4">
                    <div className="p-3 rounded-full bg-slate-500/10 text-[var(--text-muted)]">
                      <Inbox className="w-6 h-6" />
                    </div>
                    <span className="text-xs font-medium text-[var(--text-secondary)]">
                      {emptyMessage}
                    </span>
                  </div>
                </td>
              </tr>
            )}

            {/* Data Rows */}
            {!loading && !error && data.length > 0 && (
              <>
                {data.map((item, idx) => (
                  <tr
                    key={keyExtractor(item, idx)}
                    onClick={() => onRowClick && onRowClick(item)}
                    className={`${rowHeightClass} group transition-colors hover:bg-[var(--bg-hover)] ${
                      onRowClick ? 'cursor-pointer' : ''
                    }`}
                  >
                    {columns.map((col) => (
                      <td
                        key={col.key}
                        className={`px-4 py-2 whitespace-nowrap ${col.className || ''}`}
                      >
                        {col.render
                          ? col.render(item, idx)
                          : String((item as Record<string, unknown>)[col.key] ?? '—')}
                      </td>
                    ))}
                    {rowActions && (
                      <td
                        className="px-4 py-2 text-right whitespace-nowrap"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <div className="flex items-center justify-end gap-1 opacity-80 group-hover:opacity-100 transition-opacity">
                          {rowActions(item)}
                        </div>
                      </td>
                    )}
                  </tr>
                ))}
              </>
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination Footer */}
      {pagination && (
        <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-2.5 border-t border-[var(--border-hairline)] bg-[var(--bg-canvas)] text-xs text-[var(--text-secondary)]">
          <div className="tabular-nums">
            {pagination.rangeText ||
              `Trang ${pagination.currentPage} / ${pagination.totalPages}${
                pagination.totalRecords ? ` (${pagination.totalRecords} bản ghi)` : ''
              }`}
          </div>
          <div className="flex items-center gap-1">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={pagination.currentPage <= 1 || loading}
              onClick={() => pagination.onPageChange(pagination.currentPage - 1)}
              className="h-7 px-2 text-xs border-[var(--border-hairline)] disabled:opacity-40"
            >
              Trang trước
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={pagination.currentPage >= pagination.totalPages || loading}
              onClick={() => pagination.onPageChange(pagination.currentPage + 1)}
              className="h-7 px-2 text-xs border-[var(--border-hairline)] disabled:opacity-40"
            >
              Trang sau
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
