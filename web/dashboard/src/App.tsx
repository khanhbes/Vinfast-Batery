import { useState, useEffect, lazy, Suspense } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { DashboardShell } from '@/components/layout/DashboardShell';
import { MotionConfig } from 'motion/react';
import { toast } from 'sonner';
const Dashboard = lazy(() => import('@/pages/Dashboard'));
const UserManagement = lazy(() => import('@/pages/UserManagement'));
const AiCenter = lazy(() => import('@/pages/AiCenter'));
const AuditSystem = lazy(() => import('@/pages/AuditSystem'));
const Settings = lazy(() => import('@/pages/Settings'));
import Login from '@/pages/Login';
import { Toaster } from '@/components/ui/sonner';
import { auth } from '@/firebase';
import { onAuthStateChanged, signOut } from 'firebase/auth';

function AppContent({ isAuthenticated, loading }: { isAuthenticated: boolean; loading: boolean }) {
  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Đang tải...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Login />;
  }

  return (
    <>
      <DashboardShell
        userName={auth.currentUser?.displayName}
        userEmail={auth.currentUser?.email}
        onSignOut={() => { void signOut(auth).catch(() => toast.error('Chưa đăng xuất được. Hãy thử lại.')); }}
      >
            <Suspense fallback={<p role="status" className="py-8 text-muted-foreground">Đang tải trang…</p>}>
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/users" element={<UserManagement />} />
              <Route path="/ai" element={<AiCenter />} />
              <Route path="/audit" element={<AuditSystem />} />
              <Route path="/settings" element={<Settings />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
            </Suspense>
      </DashboardShell>
      <Toaster position="top-right" />
    </>
  );
}

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setIsAuthenticated(!!user);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  return (
    <MotionConfig reducedMotion="user" transition={{ duration: 0.24, ease: [0.2, 0, 0, 1] }}>
    <Router>
      <AppContent isAuthenticated={isAuthenticated} loading={loading} />
    </Router>
    </MotionConfig>
  );
}
