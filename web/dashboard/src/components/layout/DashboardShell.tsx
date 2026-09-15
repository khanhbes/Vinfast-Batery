import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { useLocation } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';

export function DashboardShell({ children, userName, userEmail, onSignOut }: {
  children: ReactNode;
  userName?: string | null;
  userEmail?: string | null;
  onSignOut: () => void;
}) {
  const { pathname } = useLocation();
  const main = useRef<HTMLElement>(null);
  const previousPath = useRef(pathname);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    if (previousPath.current !== pathname) {
      main.current?.scrollTo({ top: 0 });
      main.current?.focus({ preventScroll: true });
      previousPath.current = pathname;
    }
  }, [pathname]);

  const handleScroll = useCallback(() => {
    setScrolled((main.current?.scrollTop ?? 0) > 8);
  }, []);

  return <div className="dashboard-shell">
    <a className="skip-link" href="#main-content">Skip to main content</a>
    <Sidebar onSignOut={onSignOut} />
    <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
      <Topbar userName={userName} userEmail={userEmail} onSignOut={onSignOut} scrolled={scrolled} />
      <main id="main-content" ref={main} tabIndex={-1} className="dashboard-main" onScroll={handleScroll}>
        <div key={pathname} className="page-enter mx-auto w-full max-w-7xl min-w-0">{children}</div>
      </main>
    </div>
  </div>;
}

