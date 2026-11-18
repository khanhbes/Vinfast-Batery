import { ChevronRight, Package, Clock, Sparkles } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ResponsiveText } from '@/components/ui/ResponsiveText';
import { ACCENT_CLASSES, ModelTypeMeta, formatDate } from './types';
import { getModelAvailability, getActiveVersion } from './modelAvailability';
import { getModelIcon } from './modelIcons';

const STATUS_BADGE: Record<string, { bg: string; text: string; label: string; icon: any }> = {
  ready: { bg: 'bg-emerald-500/15 border border-emerald-500/30', text: 'text-emerald-300', label: 'Deployed', icon: Sparkles },
  in_progress: { bg: 'bg-sky-500/15 border border-sky-500/30', text: 'text-sky-300', label: 'In progress', icon: Sparkles },
  planned: { bg: 'bg-[var(--bg-elevated)] border border-[var(--border-hairline)]', text: 'text-[var(--text-secondary)]', label: 'Planned', icon: Clock },
};

interface Props {
  meta: ModelTypeMeta;
  selected: boolean;
  onSelect: () => void;
}

export default function ModelTypeCard({ meta, selected, onSelect }: Props) {
  const Icon = getModelIcon(meta.icon);
  const c = ACCENT_CLASSES[meta.accent] || ACCENT_CLASSES.slate;
  const rt = meta.runtimeStatus;
  const availability = getModelAvailability(meta);
  const StatusIcon = availability.icon;
  const sb = STATUS_BADGE[meta.status] || STATUS_BADGE.planned;
  const PhaseIcon = sb.icon;
  const activeVersion = getActiveVersion(meta);

  return (
    <Card
      onClick={onSelect}
      role="button"
      tabIndex={0}
      aria-expanded={selected}
      aria-label={`Open ${meta.label} lab`}
      onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(); } }}
      className={`hover-lift cursor-pointer bg-[var(--bg-surface)] ${
        selected ? `ring-2 ${c.ring} shadow-md border-primary/50` : 'border-[var(--border-hairline)]'
      } ${meta.status === 'planned' ? 'opacity-90' : ''}`}
    >
      <div className="p-5 flex flex-col h-full">
        <div className="flex items-start justify-between gap-2">
          <div className={`w-11 h-11 rounded-xl border ${c.border} flex items-center justify-center ${c.bg} ${c.text} shrink-0`}>
            <Icon className="w-5 h-5" />
          </div>
          <div className="flex flex-col gap-1 items-end">
            <Badge variant="secondary" className={`text-[10px] ${sb.bg} ${sb.text}`}>
              <PhaseIcon className="w-3 h-3 mr-1" />
              {sb.label}
            </Badge>
            <Badge variant="outline" className="text-[10px] font-mono">{meta.phase}</Badge>
          </div>
        </div>

        <div className="mt-3">
          <h3 className="font-semibold text-base leading-tight">{meta.label}</h3>
          {meta.shortName && (
            <div className="text-[11px] text-muted-foreground font-mono">{meta.shortName}</div>
          )}
        </div>
        <p className="text-xs text-muted-foreground mt-2 line-clamp-2">{meta.description}</p>

        <div className="mt-4 grid grid-cols-2 gap-3 text-xs">
          <div className={`rounded-md border p-2 ${availability.state === 'ready' ? 'bg-emerald-500/10 border-emerald-500/25 text-emerald-300' : availability.state === 'invalid' ? 'bg-rose-500/10 border-rose-500/25 text-rose-300' : availability.state === 'uploaded_only' ? 'bg-amber-500/10 border-amber-500/25 text-amber-300' : 'bg-[var(--bg-elevated)] border-[var(--border-hairline)] text-[var(--text-secondary)]'}`}>
            <div className="flex items-center gap-1 font-medium">
              <StatusIcon className="w-3 h-3" />
              {availability.label}
            </div>
            <div className="font-mono font-medium mt-0.5 text-muted-foreground">
              <ResponsiveText strategy="monoId" className="text-xs" alwaysTooltip>{activeVersion || (rt.versionsCount > 0 ? `${rt.versionsCount} versions` : '—')}</ResponsiveText>
            </div>
          </div>
          <div>
            <div className="text-muted-foreground flex items-center gap-1">
              <Package className="w-3 h-3" /> Features
            </div>
            <div className="font-medium mt-0.5">{meta.inputFields?.length || 0}</div>
            {rt.predictorKind && (
              <div className="text-[10px] text-muted-foreground font-mono mt-0.5">{rt.predictorKind}</div>
            )}
          </div>
        </div>

        <div className="mt-4 pt-3 border-t flex items-center justify-between text-xs text-muted-foreground">
          <ResponsiveText strategy="auto" className="text-xs text-muted-foreground">{`Load: ${formatDate(rt.lastLoadAt)}`}</ResponsiveText>
          <ChevronRight className="w-4 h-4 shrink-0" />
        </div>
      </div>
    </Card>
  );
}
