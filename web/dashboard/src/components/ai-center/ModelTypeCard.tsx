import {
  BatteryCharging, Zap, UserRound, Box, ChevronRight, CheckCircle2, AlertCircle, Package,
  Gauge, Award, Navigation, BellRing, MapPin, HeartPulse, Stethoscope, Clock, Sparkles,
  XCircle,
} from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ACCENT_CLASSES, ModelTypeMeta, formatDate } from './types';

const ICONS: Record<string, any> = {
  BatteryCharging, Zap, UserRound, Gauge, Award, Navigation,
  BellRing, MapPin, HeartPulse, Stethoscope,
};

const STATUS_BADGE: Record<string, { bg: string; text: string; label: string; icon: any }> = {
  ready: { bg: 'bg-green-100', text: 'text-green-700', label: 'Đã triển khai', icon: CheckCircle2 },
  in_progress: { bg: 'bg-blue-100', text: 'text-blue-700', label: 'Đang làm', icon: Sparkles },
  planned: { bg: 'bg-slate-100', text: 'text-slate-600', label: 'Lên kế hoạch', icon: Clock },
};

interface Props {
  meta: ModelTypeMeta;
  selected: boolean;
  onSelect: () => void;
}

function getActiveVersion(meta: ModelTypeMeta) {
  return (
    meta.runtimeStatus.activeVersion ||
    meta.runtimeStatus.deploymentVersion ||
    meta.deploymentVersion ||
    meta.activeVersion ||
    null
  );
}

function isDeployed(meta: ModelTypeMeta) {
  return (
    meta.deploymentStatus === 'deployed' ||
    meta.runtimeStatus.deploymentStatus === 'deployed' ||
    Boolean(getActiveVersion(meta))
  );
}

function getStatusDisplay(meta: ModelTypeMeta) {
  const rt = meta.runtimeStatus;
  const activeVersion = getActiveVersion(meta);

  // 1. Fully loaded & predictable → best state
  if (rt.isLoaded && rt.isPredictable) {
    return {
      icon: CheckCircle2,
      text: 'Sẵn sàng test',
      color: 'text-green-600',
      bg: 'bg-green-50',
    };
  }
  // 2. Loaded but predictor validation failed
  if (rt.isLoaded && !rt.isPredictable) {
    return {
      icon: XCircle,
      text: 'Có version nhưng lỗi',
      color: 'text-red-600',
      bg: 'bg-red-50',
    };
  }
  // 3. Has a deployed/active version but not yet loaded into RAM
  //    e.g. server just restarted and hasn't warmed up yet.
  //    This MUST come before the versionsCount check so we never falsely
  //    show "Có version chưa active" for a model that IS activated.
  if (isDeployed(meta)) {
    return {
      icon: CheckCircle2,
      text: activeVersion ? 'Đã kích hoạt' : 'Đã triển khai',
      color: 'text-emerald-600',
      bg: 'bg-emerald-50',
    };
  }
  // 4. Has uploaded versions but none has been deployed yet
  if (rt.versionsCount > 0) {
    return {
      icon: AlertCircle,
      text: 'Có version chưa active',
      color: 'text-amber-600',
      bg: 'bg-amber-50',
    };
  }
  // 5. No versions at all
  return {
    icon: AlertCircle,
    text: 'Chưa có model',
    color: 'text-slate-500',
    bg: 'bg-slate-50',
  };
}

export default function ModelTypeCard({ meta, selected, onSelect }: Props) {
  const Icon = ICONS[meta.icon] || Box;
  const c = ACCENT_CLASSES[meta.accent] || ACCENT_CLASSES.slate;
  const rt = meta.runtimeStatus;
  const statusDisplay = getStatusDisplay(meta);
  const StatusIcon = statusDisplay.icon;
  const sb = STATUS_BADGE[meta.status] || STATUS_BADGE.planned;
  const PhaseIcon = sb.icon;
  const activeVersion = getActiveVersion(meta);

  return (
    <Card
      onClick={onSelect}
      className={`cursor-pointer transition-all hover:shadow-md hover:-translate-y-0.5 ${
        selected ? `ring-2 ${c.ring} shadow-md` : 'ring-1 ring-transparent'
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
          <div className={`rounded-md p-2 ${statusDisplay.bg}`}>
            <div className={`flex items-center gap-1 ${statusDisplay.color}`}>
              <StatusIcon className="w-3 h-3" />
              {statusDisplay.text}
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
