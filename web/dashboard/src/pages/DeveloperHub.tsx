import { Link } from 'react-router-dom';
import { BrainCircuit, Database, History, Settings, Wrench } from 'lucide-react';

const tools = [
  { path: '/data', label: 'App Data Explorer', description: 'Inspect paged operational records and telemetry.', icon: Database },
  { path: '/ai', label: 'AI Studio', description: 'Review models, predictions and deployments.', icon: BrainCircuit },
  { path: '/audit', label: 'Audit Log', description: 'Trace privileged changes and account actions.', icon: History },
  { path: '/settings', label: 'Integrations & settings', description: 'Review system configuration and integrations.', icon: Settings },
];

export default function DeveloperHub() {
  return <div className="space-y-7"><div className="page-header"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Technical operations</p><h1 className="mt-2 text-3xl font-bold">Developer hub</h1><p className="mt-1 text-muted-foreground">Diagnostics and technical tools are separated from everyday account and catalog work.</p></div></div><div className="grid gap-px overflow-hidden rounded-xl border border-border bg-border sm:grid-cols-2">{tools.map(({ path, label, description, icon: Icon }) => <Link key={path} to={path} className="group bg-card p-5 transition-colors hover:bg-muted"><Icon className="h-5 w-5 text-primary"/><h2 className="mt-5 font-semibold group-hover:text-primary">{label}</h2><p className="mt-1 text-sm text-muted-foreground">{description}</p></Link>)}</div><div className="border-l-2 border-primary bg-primary/5 p-4 text-sm"><div className="flex gap-3"><Wrench className="h-4 w-4 shrink-0 text-primary"/><p>Admin authorization remains enforced by the API. Develop Mode only simplifies dashboard navigation.</p></div></div></div>;
}
