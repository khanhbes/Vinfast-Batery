import { ChevronDown, UserRound } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

const titles: Record<string, string> = { '/': 'Fleet overview', '/users': 'Accounts', '/catalog': 'Vehicle catalog', '/develop': 'Developer hub', '/data': 'App data', '/ai': 'AI Studio', '/audit': 'Audit log', '/settings': 'Settings' };

export function Topbar({ userName, userEmail, onSignOut, scrolled = false }: {
  userName?: string | null; userEmail?: string | null; onSignOut: () => void; scrolled?: boolean;
}) {
  const { pathname } = useLocation();
  return <header className={cn('dashboard-topbar', scrolled && 'is-scrolled')}>
    <div className="min-w-0">
      <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground">VinFast BMS</p>
      <p className="text-sm font-semibold">{titles[pathname] ?? 'Dashboard'}</p>
    </div>
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" className="max-w-[60%] gap-2" aria-label="Open account menu">
          <UserRound className="shrink-0 text-primary" aria-hidden="true" />
          <span className="hidden sm:block max-w-[180px]" title={userName || userEmail || 'Account'}>{userName || userEmail || 'Account'}</span>
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

