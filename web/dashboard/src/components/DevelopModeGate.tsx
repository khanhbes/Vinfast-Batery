import { type ReactNode } from 'react';
import { Code2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useDevelopMode } from '@/data/DevelopModeContext';

export function DevelopModeGate({ children }: { children: ReactNode }) {
  const { enabled, setEnabled } = useDevelopMode();
  if (enabled) return <>{children}</>;
  return <section className="grid min-h-[52vh] place-items-center border-y border-border/70 py-12 text-center"><div className="max-w-md"><Code2 className="mx-auto h-9 w-9 text-primary" /><h1 className="mt-4 text-2xl font-semibold">Chế độ kỹ thuật đang tắt</h1><p className="mt-2 text-sm text-muted-foreground">Các công cụ kỹ thuật được ẩn trong chế độ thường. Bật chế độ kỹ thuật để tiếp tục.</p><Button className="mt-5" onClick={() => setEnabled(true)}>Bật chế độ kỹ thuật</Button></div></section>;
}
