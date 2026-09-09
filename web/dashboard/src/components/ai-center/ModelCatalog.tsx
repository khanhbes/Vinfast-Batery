import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  RefreshCw, Sparkles, Database, CheckCircle2, Rocket,
  Shield, Bot, HeartPulse, Clock,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
// @ts-ignore
import { aiListTypes } from '@/api';
import { ModelGroupMeta, ModelTypeMeta, ModelGroup } from './types';
import { isModelDeployed } from './modelAvailability';
import ModelTypeCard from './ModelTypeCard';
import UniversalModelLab from './lab/UniversalModelLab';

const GROUP_META: Record<ModelGroup, { icon: any; gradient: string; text: string }> = {
  survival: { icon: Shield, gradient: 'from-emerald-50 to-emerald-100/40', text: 'text-emerald-800' },
  assistant: { icon: Bot, gradient: 'from-violet-50 to-violet-100/40', text: 'text-violet-800' },
  health: { icon: HeartPulse, gradient: 'from-rose-50 to-rose-100/40', text: 'text-rose-800' },
};

export default function ModelCatalog() {
  const [types, setTypes] = useState<ModelTypeMeta[]>([]);
  const [groups, setGroups] = useState<ModelGroupMeta[]>([]);
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const request = useRef(0);

  const reload = useCallback(async () => {
    const id = ++request.current;
    setLoading(true);
    setError(null);
    try {
      const res = await aiListTypes();
      if (id !== request.current) return;
      const list = (res?.data?.types ?? []) as ModelTypeMeta[];
      const grs = (res?.data?.groups ?? []) as ModelGroupMeta[];
      setTypes(list);
      setGroups(grs);
    } catch (e: any) {
      if (id !== request.current) return;
      setError(e?.message || 'Could not load the model catalog');
    } finally {
      if (id === request.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    reload();
    return () => { request.current++; };
  }, [reload]);

  const selected = types.find((t) => t.key === selectedKey) || null;

  // Bucket types by group
  const byGroup = useMemo(() => {
    const m: Record<string, ModelTypeMeta[]> = {};
    for (const t of types) {
      (m[t.group] ||= []).push(t);
    }
    return m;
  }, [types]);
  const displayGroups = useMemo(() => {
    const result = [...groups];
    for (const key of Object.keys(byGroup)) {
      if (!result.some(g => g.key === key)) {
        result.push({ key: key as ModelGroup, label: key, subtitle: 'Models provided by the server', phase: '', order: result.length });
      }
    }
    return result;
  }, [groups, byGroup]);

  // Aggregate KPIs
  const readyCount = types.filter(isModelDeployed).length;
  const loadedCount = types.filter((t) => t.runtimeStatus?.isLoaded).length;
  const totalVersions = types.reduce((a, t) => a + (t.runtimeStatus?.versionsCount || 0), 0);
  const plannedCount = types.filter((t) => t.status === 'planned').length;

  return (
    <div className="space-y-6">
      {/* Header / KPIs */}
      <div className="rounded-xl border bg-gradient-to-br from-card via-card to-muted/40 p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="flex items-center gap-2 text-xs font-medium uppercase text-muted-foreground">
              <Sparkles className="w-3.5 h-3.5" /> AI Model Hub · Roadmap
            </div>
            <h2 className="text-2xl font-bold mt-1">AI model operations</h2>
            <p className="text-sm text-muted-foreground max-w-2xl">
              {types.length > 0 ? `${types.length} AI models` : 'AI models'} across the three-stage roadmap. Upload, hot-swap and smoke-test directly from the dashboard.
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={reload} disabled={loading}>
            <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
        </div>

        <div className="mt-5 grid grid-cols-2 md:grid-cols-4 gap-3">
          <KpiTile icon={<Database className="w-4 h-4" />} label="Total models" value={String(types.length)} hint={`${plannedCount} planned`} />
          <KpiTile icon={<CheckCircle2 className="w-4 h-4 text-green-600" />} label="Deployed" value={`${readyCount}/${types.length}`} />
          <KpiTile icon={<Rocket className="w-4 h-4 text-blue-600" />} label="Models loaded" value={`${loadedCount}/${readyCount}`} hint="Loaded in memory" />
          <KpiTile icon={<Database className="w-4 h-4 text-violet-600" />} label="Total versions" value={String(totalVersions)} />
        </div>

        <div className="mt-4 text-xs text-muted-foreground flex flex-wrap gap-3">
          <Legend color="bg-green-500" label="Deployed" />
          <Legend color="bg-blue-500" label="In progress" />
          <Legend color="bg-slate-400" label="Planned" />
        </div>
      </div>

      {error && (
        <div role="alert" className="text-sm rounded-md border border-red-200 bg-red-50 text-red-700 p-3">
          {error}
        </div>
      )}

      {/* Groups */}
      {loading && types.length === 0 ? (
        <div className="text-center py-10 text-muted-foreground text-sm">Loading model catalog...</div>
      ) : (
        displayGroups.map((g) => {
          const groupTypes = byGroup[g.key] || [];
          if (groupTypes.length === 0) return null;
          const gm = GROUP_META[g.key] || GROUP_META.survival;
          const GIcon = gm.icon;
          const isGroupSelected = selected && selected.group === g.key;

          return (
            <section key={g.key} className="space-y-4">
              <div className={`rounded-lg border bg-gradient-to-r ${gm.gradient} px-4 py-3`}>
                <div className="flex items-center justify-between gap-3 flex-wrap">
                  <div className="flex items-center gap-3">
                    <div className={`w-9 h-9 rounded-lg bg-white flex items-center justify-center ${gm.text}`}>
                      <GIcon className="w-5 h-5" />
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className={`font-semibold ${gm.text}`}>{g.label}</h3>
                        <span className="text-[10px] font-mono bg-white/70 rounded px-1.5 py-0.5 text-foreground/70">
                          {g.phase}
                        </span>
                      </div>
                      <p className="text-xs text-muted-foreground">{g.subtitle}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Clock className="w-3.5 h-3.5" /> {groupTypes.length} models
                  </div>
                </div>
              </div>

              {/* Model Cards Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                {groupTypes.map((t) => (
                  <ModelTypeCard
                    key={t.key}
                    meta={t}
                    selected={selectedKey === t.key}
                    onSelect={() => {
                      setSelectedKey((prev) => (prev === t.key ? null : t.key));
                    }}
                  />
                ))}
              </div>

              {/* Inline Universal Model Lab (opens directly below the selected group) */}
              {isGroupSelected && selected && (
                <div className="mt-4 animate-in fade-in slide-in-from-top-2 duration-300">
                  <UniversalModelLab
                    key={selected.key}
                    meta={selected}
                    onModelChanged={reload}
                  />
                </div>
              )}
            </section>
          );
        })
      )}
      {!loading && !error && types.length === 0 && <p role="status" className="rounded-xl border border-dashed p-8 text-center text-muted-foreground">No models are available in the server catalog.</p>}
    </div>
  );
}

function KpiTile({ icon, label, value, hint }: {
  icon: React.ReactNode; label: string; value: string; hint?: string;
}) {
  return (
    <div className="rounded-lg border bg-card p-3">
      <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {icon} {label}
      </div>
      <div className="mt-1 text-xl font-bold">{value}</div>
      {hint && <div className="text-[10px] text-muted-foreground mt-0.5">{hint}</div>}
    </div>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={`w-2 h-2 rounded-full ${color}`} /> {label}
    </span>
  );
}
