import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';

type DevelopModeValue = { enabled: boolean; setEnabled: (enabled: boolean) => void };
const DevelopModeContext = createContext<DevelopModeValue | null>(null);
const storageKey = 'vinfast-dashboard-develop-mode';

export function DevelopModeProvider({ children }: { children: ReactNode }) {
  const [enabled, setEnabled] = useState(() => window.localStorage.getItem(storageKey) === 'true');
  useEffect(() => { window.localStorage.setItem(storageKey, String(enabled)); }, [enabled]);
  return <DevelopModeContext.Provider value={{ enabled, setEnabled }}>{children}</DevelopModeContext.Provider>;
}

export function useDevelopMode() {
  const value = useContext(DevelopModeContext);
  if (!value) throw new Error('useDevelopMode must be used inside DevelopModeProvider');
  return value;
}
