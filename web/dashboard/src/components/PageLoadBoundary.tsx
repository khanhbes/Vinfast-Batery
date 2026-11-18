import { Component, useEffect, useState, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';

export function PageLoading() {
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setSlow(true), 12000);
    return () => clearTimeout(timer);
  }, []);
  return (
    <section className="space-y-6 py-2 animate-fadeIn" aria-busy="true">
      <div className="flex items-center justify-between gap-4">
        <div className="space-y-2">
          <div className="skeleton-shimmer h-7 w-44 rounded-lg" />
          <div className="skeleton-shimmer h-3.5 w-72 rounded-md" />
        </div>
        <div className="skeleton-shimmer h-8 w-28 rounded-lg" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <div key={index} className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5 space-y-3">
            <div className="skeleton-shimmer h-3.5 w-24 rounded-md" />
            <div className="skeleton-shimmer h-7 w-20 rounded-lg" />
            <div className="skeleton-shimmer h-3 w-32 rounded-md" />
          </div>
        ))}
      </div>
      <div className="rounded-xl border border-[var(--border-hairline)] bg-[var(--bg-surface)] p-5 space-y-3">
        <div className="skeleton-shimmer h-4 w-40 rounded-md" />
        <div className="skeleton-shimmer h-52 w-full rounded-xl" />
      </div>
      <p role="status" className="text-xs text-[var(--text-muted)]">
        {slow ? 'Trang đang tải lâu hơn dự kiến. Kiểm tra kết nối hoặc tải lại trang.' : 'Đang mở trang...'}
      </p>
      {slow && <Button className="max-md:min-h-12" variant="outline" onClick={() => window.location.reload()}>Tải lại trang</Button>}
    </section>
  );
}

export class PageLoadBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    if (this.state.failed) return <section className="space-y-3 py-8">
      <h1 className="text-xl font-semibold">Không thể mở trang này</h1>
      <p role="alert" className="text-muted-foreground">Tải lại trang để thử lại. Không có thao tác nào được gửi lại.</p>
      <Button className="min-h-12" onClick={() => window.location.reload()}>Tải lại trang</Button>
    </section>;
    return this.props.children;
  }
}
