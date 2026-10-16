import { Cpu, ExternalLink, PlugZap, ShieldCheck } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

/** Shelly devices are managed on /shelly (Task 125). The old vault form here
 *  saved through the connection-code flow but listed the admin's own
 *  profiles, so a saved device never appeared and "revoke" unlinked the
 *  admin's own plug. */
function ShellyShortcut() {
  const navigate = useNavigate();
  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex gap-3">
        <div className="rounded-xl bg-primary/10 p-3 text-primary"><PlugZap className="h-5 w-5" /></div>
        <div>
          <p className="font-semibold">Shelly devices & connection codes</p>
          <p className="mt-1 text-sm text-muted-foreground">Add devices, issue single-use 24 h codes and review members on the Shelly page.</p>
        </div>
      </div>
      <Button onClick={() => navigate('/shelly')} className="gap-2">Open Shelly<ExternalLink className="h-4 w-4" /></Button>
    </div>
  );
}

export default function Settings() {
  const navigate = useNavigate();
  return <div className="page-enter space-y-8"><div className="page-header"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">System configuration</p><h1 className="mt-2 text-3xl font-bold">Settings</h1><p className="mt-1 text-muted-foreground">Manage device connections and open server-backed administrative tools.</p></div></div><Card className="border-border/60"><CardContent className="p-5 sm:p-6"><ShellyShortcut /></CardContent></Card><Card className="border-border/60"><CardHeader><div className="flex gap-3"><div className="rounded-xl bg-indigo-500/10 p-3 text-indigo-500"><Cpu className="h-5 w-5" /></div><div><CardTitle>Developer AI Studio</CardTitle><CardDescription className="mt-1">Upload candidates, run smoke tests, deploy and roll back versioned models in AI Studio. Runtime status always comes from the API.</CardDescription></div></div></CardHeader><CardContent className="flex flex-col gap-4 border-t border-border/60 pt-5 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-2 text-sm text-muted-foreground"><ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" /><span>Settings never displays fabricated versions, metrics or deployment states.</span></div><Button onClick={() => navigate('/ai')} className="gap-2">Open AI Studio<ExternalLink className="h-4 w-4" /></Button></CardContent></Card></div>;
}
