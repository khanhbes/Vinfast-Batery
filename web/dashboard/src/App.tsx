import { useState, useEffect, lazy, Suspense } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { DashboardShell } from '@/components/layout/DashboardShell';
import { MotionConfig } from 'motion/react';
import { toast } from 'sonner';
const Dashboard = lazy(() => import('@/pages/Dashboard'));
const UserManagement = lazy(() => import('@/pages/UserManagement'));
const AiCenter = lazy(() => import('@/pages/AiCenter'));
const AuditSystem = lazy(() => import('@/pages/AuditSystem'));
const Settings = lazy(() => import('@/pages/Settings'));
const DataExplorer = lazy(() => import('@/pages/DataExplorer'));
const VehicleCatalog = lazy(() => import('@/pages/VehicleCatalog'));
const DeveloperHub = lazy(() => import('@/pages/DeveloperHub'));
import ShellyGateway from '@/pages/ShellyGateway';
import AssistantKnowledge from '@/pages/AssistantKnowledge';
const AssistantTips = lazy(() => import('@/pages/AssistantTips'));
const PremiumPlans = lazy(() => import('@/pages/PremiumPlans'));
const SupportInbox = lazy(() => import('@/pages/SupportInbox'));
import { PageLoadBoundary, PageLoading } from '@/components/PageLoadBoundary';
import Login from '@/pages/Login';
import { Toaster } from '@/components/ui/sonner';
import { auth } from '@/firebase';
import { onIdTokenChanged, signOut, type User } from 'firebase/auth';
import { AdminAccessGate } from '@/components/AdminAccessGate';
import { AdminDataProvider } from '@/data/AdminDataContext';
import { DevelopModeProvider } from '@/data/DevelopModeContext';
import { DevelopModeGate } from '@/components/DevelopModeGate';

import { PinovaMark } from '@/components/layout/PinovaMark';

function AppContent({ user, loading, sessionRevision }: { user: User | null; loading: boolean; sessionRevision: number }) {
  const { pathname } = useLocation();
  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-canvas)] text-[var(--text-primary)] flex items-center justify-center p-6">
        <div className="text-center space-y-4">
          <div className="mx-auto inline-flex h-14 w-14 items-center justify-center rounded-2xl border border-[var(--border-strong)] bg-[var(--bg-surface)] shadow-[0_0_24px_rgba(99,102,241,0.18)]">
            <PinovaMark tile className="h-12 w-12" />
          </div>
          <div className="flex items-center justify-center gap-2.5 text-xs text-[var(--text-secondary)]">
            <span className="h-3.5 w-3.5 rounded-full border-2 border-[var(--accent-primary)]/30 border-t-[var(--accent-primary)] animate-spin" />
            <span>Đang tải không gian quản trị bảo mật...</span>
          </div>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Login />;
  }

  return (
    <>
      <AdminAccessGate key={`${user.uid}:${sessionRevision}`} uid={user.uid} onSignOut={() => { void signOut(auth).catch(() => toast.error('Đăng xuất thất bại. Vui lòng thử lại.')); }}>
      <DevelopModeProvider><AdminDataProvider>
      <DashboardShell
        userName={auth.currentUser?.displayName}
        userEmail={auth.currentUser?.email}
        onSignOut={() => { void signOut(auth).catch(() => toast.error('Đăng xuất thất bại. Vui lòng thử lại.')); }}
      >
            <PageLoadBoundary key={`${user.uid}:${pathname}`}><Suspense fallback={<PageLoading />}>
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/users" element={<UserManagement />} />
              <Route path="/develop" element={<DevelopModeGate><DeveloperHub /></DevelopModeGate>} />
              <Route path="/data" element={<DevelopModeGate><DataExplorer /></DevelopModeGate>} />
              <Route path="/catalog" element={<VehicleCatalog />} />
              <Route path="/shelly" element={<ShellyGateway />} />
              <Route path="/assistant" element={<AssistantKnowledge />} />
              <Route path="/assistant/tips" element={<AssistantTips />} />
              <Route path="/premium" element={<PremiumPlans />} />
              <Route path="/support" element={<SupportInbox />} />
              <Route path="/ai" element={<DevelopModeGate><AiCenter /></DevelopModeGate>} />
              <Route path="/audit" element={<DevelopModeGate><AuditSystem /></DevelopModeGate>} />
              <Route path="/settings" element={<DevelopModeGate><Settings /></DevelopModeGate>} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
            </Suspense></PageLoadBoundary>
      </DashboardShell>
      </AdminDataProvider></DevelopModeProvider>
      </AdminAccessGate>
      <Toaster position="top-right" />
    </>
  );
}

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [sessionRevision, setSessionRevision] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    document.documentElement.classList.add('dark');
  }, []);

  useEffect(() => {
    // Remount the admin tree only when the account changes. The hourly ID
    // token refresh used to bump the revision too, remounting every page and
    // losing half-typed forms (Task 125).
    let lastUid: string | null | undefined;
    const unsubscribe = onIdTokenChanged(auth, (user) => {
      setUser(user);
      const uid = user?.uid ?? null;
      // Signed out: drop the cached admin snapshot (profiles, emails).
      if (!uid) {
        try { window.sessionStorage.removeItem('vinfast-admin-snapshot-v2'); } catch { /* optional */ }
      }
      if (uid !== lastUid) {
        lastUid = uid;
        setSessionRevision(value => value + 1);
      }
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  return (
    <MotionConfig reducedMotion="user" transition={{ duration: 0.24, ease: [0.2, 0, 0, 1] }}>
    <Router>
      <AppContent user={user} loading={loading} sessionRevision={sessionRevision} />
    </Router>
    </MotionConfig>
  );
}
