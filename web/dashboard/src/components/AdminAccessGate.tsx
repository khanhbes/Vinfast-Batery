import { useEffect, useState, type ReactNode } from 'react';
import { authMe } from '@/api';
import { isVerifiedAdmin } from '@/lib/portalAccess';
import { Button } from '@/components/ui/button';

// Do not mount data-fetching pages until the API confirms this exact identity.
export function AdminAccessGate({ uid, children, onSignOut }: {
  uid: string; children: ReactNode; onSignOut: () => void;
}) {
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState<{ uid: string; status: 'loading' | 'allowed' | 'denied' | 'error' }>({ uid, status: 'loading' });
  useEffect(() => {
    let current = true;
    setState({ uid, status: 'loading' });
    void authMe().then(result => {
      if (current) setState({ uid, status: isVerifiedAdmin(result, uid) ? 'allowed' : 'denied' });
    }).catch(() => { if (current) setState({ uid, status: 'error' }); });
    return () => { current = false; };
  }, [uid, attempt]);
  const status = state.uid === uid ? state.status : 'loading';
  if (status === 'allowed') return children;
  return <main className="min-h-dvh grid place-items-center bg-background p-6">
    <section className="w-full max-w-md space-y-4" aria-busy={status === 'loading'}>
      <h1 className="text-2xl font-semibold">{status === 'loading' ? 'Đang xác minh quyền truy cập' : status === 'denied' ? 'Cần quyền quản trị viên' : 'Chưa thể xác minh quyền truy cập'}</h1>
      <p role="status" className="text-muted-foreground">{status === 'loading' ? 'Đang chờ máy chủ xác minh tài khoản.' : status === 'denied' ? 'Trang này chỉ dành cho quản trị viên. Bạn vẫn có thể dùng ứng dụng điện thoại với tài khoản này.' : 'Kiểm tra kết nối rồi thử lại. Dữ liệu quản trị chưa được tải.'}</p>
      <div className="flex flex-wrap gap-3">
        {status === 'error' && <Button onClick={() => setAttempt(value => value + 1)}>Thử lại</Button>}
        <Button variant="outline" onClick={onSignOut}>Đăng xuất</Button>
      </div>
    </section>
  </main>;
}
