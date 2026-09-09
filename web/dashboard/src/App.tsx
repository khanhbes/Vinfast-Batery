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
const DataExplorer = lazy(() => import('@/pages/DataExplorer'));
import Login from '@/pages/Login';
import { Toaster } from '@/components/ui/sonner';
import { auth } from '@/firebase';
import { onIdTokenChanged, signOut, type User } from 'firebase/auth';
import { AdminAccessGate } from '@/components/AdminAccessGate';
import { AdminDataProvider } from '@/data/AdminDataContext';

function AppContent({ user, loading, sessionRevision }: { user: User | null; loading: boolean; sessionRevision: number }) {
  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Loading secure workspace...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return <Login />;
  }

  return (
    <>
      <AdminAccessGate key={`${user.uid}:${sessionRevision}`} uid={user.uid} onSignOut={() => { void signOut(auth).catch(() => toast.error('Sign out failed. Please try again.')); }}>
      <AdminDataProvider>
      <DashboardShell
        userName={auth.currentUser?.displayName}
        userEmail={auth.currentUser?.email}
        onSignOut={() => { void signOut(auth).catch(() => toast.error('Sign out failed. Please try again.')); }}
      >
            <Suspense fallback={<p role="status" className="py-8 text-muted-foreground">Loading page...</p>}>
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/users" element={<UserManagement />} />
              <Route path="/data" element={<DataExplorer />} />
              <Route path="/ai" element={<AiCenter />} />
              <Route path="/audit" element={<AuditSystem />} />
              <Route path="/settings" element={<Settings />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
            </Suspense>
      </DashboardShell>
      </AdminDataProvider>
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
    const unsubscribe = onIdTokenChanged(auth, (user) => {
      setUser(user);
      setSessionRevision(value => value + 1);
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
