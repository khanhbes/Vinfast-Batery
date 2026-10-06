import { Component, useEffect, useState, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';

export function PageLoading() {
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => setSlow(true), 12000);
    return () => clearTimeout(timer);
  }, []);
  return <section className="space-y-3 py-8" aria-busy="true">
    <p role="status" className="text-muted-foreground">{slow ? 'Trang đang tải lâu hơn dự kiến. Kiểm tra kết nối hoặc tải lại trang.' : 'Đang mở trang...'}</p>
    {slow && <Button className="min-h-12" variant="outline" onClick={() => window.location.reload()}>Tải lại trang</Button>}
  </section>;
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
