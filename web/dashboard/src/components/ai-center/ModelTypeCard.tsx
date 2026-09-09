import { ChevronRight, Package, Clock, Sparkles } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { LIGHT_ACCENT_CLASSES, ModelTypeMeta, formatDate } from './types';
import { getModelAvailability, getActiveVersion } from './modelAvailability';
import { getModelIcon } from './modelIcons';

const STATUS_BADGE: Record<string, { bg: string; text: string; label: string; icon: any }> = {
  ready: { bg: 'bg-green-100', text: 'text-green-700', label: 'Deployed', icon: Sparkles },
  in_progress: { bg: 'bg-blue-100', text: 'text-blue-700', label: 'In progress', icon: Sparkles },
  planned: { bg: 'bg-slate-100', text: 'text-slate-600', label: 'Planned', icon: Clock },
};

interface Props {
  meta: ModelTypeMeta;
  selected: boolean;
  onSelect: () => void;
}

export default function ModelTypeCard({ meta, selected, onSelect }: Props) {
  const Icon = getModelIcon(meta.icon);
  const c = LIGHT_ACCENT_CLASSES[meta.accent] || LIGHT_ACCENT_CLASSES.slate;
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
      className={`cursor-pointer transition-all hover:shadow-md hover:-translate-y-0.5 ${
        selected ? `ring-2 ${c.ring} shadow-md border-primary/50` : 'ring-1 ring-transparent'
      } ${meta.status === 'planned' ? 'opacity-90' : ''}`}
    >
      <div className="p-5 flex flex-col h-full">
        <div className="flex items-start justify-between gap-2">
          <div className={`w-11 h-11 rounded-xl flex items-center justify-center ${c.bg} ${c.text} shrink-0`}>
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
          <div className={`rounded-md p-2 ${availability.state === 'ready' ? 'bg-emerald-50 text-emerald-700' : availability.state === 'invalid' ? 'bg-red-50 text-red-700' : availability.state === 'uploaded_only' ? 'bg-amber-50 text-amber-700' : 'bg-slate-50 text-slate-700'}`}>
            <div className="flex items-center gap-1 font-medium">
              <StatusIcon className="w-3 h-3" />
              {availability.label}
            </div>
            <div className="font-mono font-medium truncate mt-0.5 text-muted-foreground">
              {activeVersion || (rt.versionsCount > 0 ? `${rt.versionsCount} versions` : '—')}
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
          <span className="truncate">Load: {formatDate(rt.lastLoadAt)}</span>
          <ChevronRight className="w-4 h-4 shrink-0" />
        </div>
      </div>
    </Card>
  );
}
