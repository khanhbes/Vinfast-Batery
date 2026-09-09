import { ChevronDown, UserRound } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

const titles: Record<string, string> = { '/': 'Fleet overview', '/users': 'Accounts', '/data': 'App data', '/ai': 'AI Studio', '/audit': 'Audit log', '/settings': 'Settings' };

export function Topbar({ userName, userEmail, onSignOut }: {
  userName?: string | null; userEmail?: string | null; onSignOut: () => void;
}) {
  const { pathname } = useLocation();
  return <header className="dashboard-topbar">
    <div className="min-w-0">
      <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">VinFast BMS</p>
      <p className="truncate text-sm font-semibold">{titles[pathname] ?? 'Dashboard'}</p>
    </div>
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" className="max-w-[60%] gap-2" aria-label="Open account menu">
          <UserRound className="shrink-0 text-primary" aria-hidden="true" />
          <span className="hidden truncate sm:block">{userName || userEmail || 'Account'}</span>
          <ChevronDown aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="max-w-[calc(100vw-2rem)] w-64">
        <DropdownMenuLabel className="break-words">{userEmail || 'My account'}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild><Link to="/settings">System settings</Link></DropdownMenuItem>
        <DropdownMenuItem asChild><Link to="/audit">Audit log</Link></DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem className="text-destructive" onSelect={onSignOut}>Sign out</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  </header>;
}
