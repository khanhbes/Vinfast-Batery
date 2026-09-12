import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { Archive, BookOpenCheck, Check, ChevronRight, FileSearch, Globe2, ImagePlus, Loader2, Plus, RefreshCw, Search, Sparkles, X } from 'lucide-react';
import { toast } from 'sonner';
import {
  catalogArchive, catalogCreate, catalogGet, catalogList, catalogManufacturerSave,
  catalogPublish, catalogResearchCreate, catalogResearchGet, catalogRestore,
  catalogUpdate, catalogUploadMedia,
} from '@/api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ModalSurface } from '@/components/ui/modal-surface';

type Dictionary = Record<string, unknown>;
type CatalogEntry = Dictionary & {
  catalogId: string; brandId?: string; brandName?: string; model?: string; variant?: string;
  modelYear?: number; market?: string; vehicleType?: string; status?: string; selectable?: boolean;
  revision?: number; battery?: Dictionary; charging?: Dictionary; performance?: Dictionary;
  appDefaults?: Dictionary; localized?: Record<string, Dictionary>; media?: Dictionary;
  sources?: Dictionary[]; conflicts?: Dictionary[]; updatedAt?: string;
};

const emptyDraft = (): CatalogEntry => ({
  catalogId: '', brandId: '', brandName: '', model: '', variant: '', modelYear: new Date().getFullYear(),
  market: 'VN', vehicleType: 'scooter', status: 'draft', aliases: [],
  localized: { vi: { displayName: '', tagline: '', description: '' }, en: { displayName: '', tagline: '', description: '' } },
  battery: { chemistry: '', grossCapacityWh: null, usableCapacityWh: null, calculationCapacityWh: null, voltageV: null, capacityAh: null, packCount: 1, removable: false },
  charging: { maxAcPowerW: null, maxDcPowerW: null, maxSafeChargePowerW: null, connector: '', chargeTimeMinutes: null },
  performance: { ratedMotorPowerW: null, peakMotorPowerW: null, topSpeedKmh: null, rangeKm: null, rangeTestCycle: '', consumptionWhPerKm: null },
  appDefaults: { calculationCapacityWh: null, defaultEfficiencyKmPerPercent: null, maxSafeChargePowerW: null },
  dimensions: {}, sources: [], conflicts: [],
});

const valueAt = (entry: CatalogEntry, group: string, field: string) => (entry[group] as Dictionary | undefined)?.[field] ?? '';
const localizedAt = (entry: CatalogEntry, locale: string, field: string) => entry.localized?.[locale]?.[field] ?? '';
const numberOrNull = (value: string) => value.trim() === '' ? null : Number(value);
const displayName = (entry: CatalogEntry) => String(localizedAt(entry, 'en', 'displayName') || localizedAt(entry, 'vi', 'displayName') || `${entry.brandName || ''} ${entry.model || ''}`.trim());
const formatPower = (value: unknown) => typeof value === 'number' && value > 0 ? value >= 1000 ? `${(value / 1000).toFixed(value % 1000 ? 1 : 0)} kW` : `${value} W` : '—';
const formatCapacity = (value: unknown) => typeof value === 'number' && value > 0 ? value >= 1000 ? `${(value / 1000).toFixed(2)} kWh` : `${value} Wh` : '—';
const evidenceQuality = (entry: CatalogEntry) => (entry.conflicts || []).some(conflict => !conflict.resolved)
  ? 'conflicting'
  : (entry.sources || []).length > 0 ? 'sourced' : 'missing';

function Field({ label, value, onChange, type = 'text', required = false }: { label: string; value: unknown; onChange: (value: string) => void; type?: string; required?: boolean }) {
  return <label className="space-y-1.5 text-sm"><span className="font-medium">{label}{required && <span className="text-destructive"> *</span>}</span><Input type={type} value={value == null ? '' : String(value)} onChange={event => onChange(event.target.value)} /></label>;
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="border-l border-border pl-4"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 font-semibold tabular-nums">{value}</p></div>;
}

function StatusBadge({ entry }: { entry: CatalogEntry }) {
  if (entry.status === 'draft') return <Badge variant="outline" className="border-amber-500/40 text-amber-700 dark:text-amber-300">Draft</Badge>;
  if (entry.selectable === false) return <Badge variant="outline">Archived</Badge>;
  return <Badge className="gap-1"><Check className="h-3 w-3" />Published</Badge>;
}

function Editor({ initial, onClose, onSaved }: { initial: CatalogEntry; onClose: () => void; onSaved: () => Promise<void> }) {
  const [draft, setDraft] = useState<CatalogEntry>(initial);
  const [busy, setBusy] = useState('');
  const [errors, setErrors] = useState<string[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const updateTop = (field: string, value: unknown) => setDraft(current => ({ ...current, [field]: value }));
  const updateGroup = (group: string, field: string, value: unknown) => setDraft(current => ({ ...current, [group]: { ...(current[group] as Dictionary || {}), [field]: value } }));
  const updateLocale = (locale: string, field: string, value: string) => setDraft(current => ({ ...current, localized: { ...(current.localized || {}), [locale]: { ...(current.localized?.[locale] || {}), [field]: value } } }));
  const save = async () => {
    setBusy('save'); setErrors([]);
    try {
      const result = draft.catalogId ? await catalogUpdate(draft.catalogId, draft) : await catalogCreate(draft);
      setDraft(result.data as CatalogEntry);
      setErrors(result.validationErrors || []);
      toast.success('Draft saved');
      await onSaved();
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Could not save draft'); }
    finally { setBusy(''); }
  };
  const publish = async () => {
    if (!draft.catalogId) { toast.error('Save the draft before publishing'); return; }
    setBusy('publish'); setErrors([]);
    try { await catalogPublish(draft.catalogId); toast.success('Catalog configuration published'); await onSaved(); onClose(); }
    catch (error) {
      const value = error as Error & { data?: { validationErrors?: string[] } };
      setErrors(value.data?.validationErrors || []); toast.error(value.message || 'Publish failed');
    } finally { setBusy(''); }
  };
  const upload = async (file: File) => {
    if (!draft.catalogId) { toast.error('Save the draft before uploading media'); return; }
    setBusy('media');
    try {
      const sourceUrl = window.prompt('Official image source URL') || '';
      const rightsConfirmed = window.confirm('Confirm that you have the right to use and store this image?');
      if (!rightsConfirmed) return;
      const result = await catalogUploadMedia(draft.catalogId, file, { sourceUrl, rightsConfirmed, credit: '', licenseNote: 'Approved by administrator' });
      setDraft(current => ({ ...current, media: result.data })); toast.success('Optimized catalog images uploaded');
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Image upload failed'); }
    finally { setBusy(''); }
  };
  return <ModalSurface drawer label="Vehicle catalog editor" onClose={onClose} busy={Boolean(busy)}>
    <div className="min-h-full bg-slate-950 text-slate-100">
      <header className="sticky top-0 z-10 flex items-start justify-between border-b border-slate-800 bg-slate-950/95 px-5 py-5 backdrop-blur sm:px-8">
        <div><p className="text-xs font-semibold uppercase tracking-[.18em] text-emerald-400">Catalog draft</p><h2 className="mt-2 text-2xl font-semibold">{displayName(draft) || 'New configuration'}</h2><p className="mt-1 text-sm text-slate-400">Technical fields remain server-managed after publication.</p></div>
        <Button variant="ghost" size="icon" className="text-slate-300 hover:bg-slate-800 hover:text-white" onClick={onClose}><X /></Button>
      </header>
      <div className="space-y-9 p-5 sm:p-8">
        <section className="space-y-4"><h3 className="border-b border-slate-800 pb-3 font-semibold">Identity</h3><div className="grid gap-4 sm:grid-cols-2">
          <Field label="Brand" required value={draft.brandName} onChange={value => updateTop('brandName', value)} />
          <Field label="Brand ID" required value={draft.brandId} onChange={value => updateTop('brandId', value)} />
          <Field label="Model" required value={draft.model} onChange={value => updateTop('model', value)} />
          <Field label="Variant" required value={draft.variant} onChange={value => updateTop('variant', value)} />
          <Field label="Model year" required type="number" value={draft.modelYear} onChange={value => updateTop('modelYear', Number(value))} />
          <Field label="Market (ISO-2)" required value={draft.market} onChange={value => updateTop('market', value.toUpperCase())} />
          <label className="space-y-1.5 text-sm"><span className="font-medium">Vehicle type *</span><select className="min-h-10 w-full rounded-md border border-slate-700 bg-slate-900 px-3" value={draft.vehicleType} onChange={event => updateTop('vehicleType', event.target.value)}>{['scooter','motorcycle','car','suv','pickup','van','bus','truck','other'].map(value => <option key={value}>{value}</option>)}</select></label>
        </div></section>
        <section className="space-y-4"><h3 className="border-b border-slate-800 pb-3 font-semibold">Localized content</h3>{['vi','en'].map(locale => <div key={locale} className="grid gap-4 sm:grid-cols-2"><Field label={`${locale.toUpperCase()} display name`} required value={localizedAt(draft, locale, 'displayName')} onChange={value => updateLocale(locale, 'displayName', value)} /><Field label={`${locale.toUpperCase()} tagline`} value={localizedAt(draft, locale, 'tagline')} onChange={value => updateLocale(locale, 'tagline', value)} /></div>)}</section>
        <section className="space-y-4"><h3 className="border-b border-slate-800 pb-3 font-semibold">Battery & app defaults</h3><div className="grid gap-4 sm:grid-cols-2">
          <Field label="Calculation capacity (Wh)" required type="number" value={valueAt(draft,'appDefaults','calculationCapacityWh')} onChange={value => updateGroup('appDefaults','calculationCapacityWh',numberOrNull(value))} />
          <Field label="Default efficiency (km/%)" required type="number" value={valueAt(draft,'appDefaults','defaultEfficiencyKmPerPercent')} onChange={value => updateGroup('appDefaults','defaultEfficiencyKmPerPercent',numberOrNull(value))} />
          <Field label="Gross capacity (Wh)" type="number" value={valueAt(draft,'battery','grossCapacityWh')} onChange={value => updateGroup('battery','grossCapacityWh',numberOrNull(value))} />
          <Field label="Usable capacity (Wh)" type="number" value={valueAt(draft,'battery','usableCapacityWh')} onChange={value => updateGroup('battery','usableCapacityWh',numberOrNull(value))} />
          <Field label="Chemistry" value={valueAt(draft,'battery','chemistry')} onChange={value => updateGroup('battery','chemistry',value)} />
          <Field label="Nominal voltage (V)" type="number" value={valueAt(draft,'battery','voltageV')} onChange={value => updateGroup('battery','voltageV',numberOrNull(value))} />
          <Field label="Capacity (Ah)" type="number" value={valueAt(draft,'battery','capacityAh')} onChange={value => updateGroup('battery','capacityAh',numberOrNull(value))} />
          <Field label="Safe charge limit (W)" type="number" value={valueAt(draft,'appDefaults','maxSafeChargePowerW')} onChange={value => updateGroup('appDefaults','maxSafeChargePowerW',numberOrNull(value))} />
        </div></section>
        <section className="space-y-4"><h3 className="border-b border-slate-800 pb-3 font-semibold">Charging & performance</h3><div className="grid gap-4 sm:grid-cols-2">
          <Field label="Maximum AC power (W)" type="number" value={valueAt(draft,'charging','maxAcPowerW')} onChange={value => updateGroup('charging','maxAcPowerW',numberOrNull(value))} />
          <Field label="Maximum DC power (W)" type="number" value={valueAt(draft,'charging','maxDcPowerW')} onChange={value => updateGroup('charging','maxDcPowerW',numberOrNull(value))} />
          <Field label="Connector" value={valueAt(draft,'charging','connector')} onChange={value => updateGroup('charging','connector',value)} />
          <Field label="Published range (km)" type="number" value={valueAt(draft,'performance','rangeKm')} onChange={value => updateGroup('performance','rangeKm',numberOrNull(value))} />
          <Field label="Range test cycle" value={valueAt(draft,'performance','rangeTestCycle')} onChange={value => updateGroup('performance','rangeTestCycle',value)} />
          <Field label="Top speed (km/h)" type="number" value={valueAt(draft,'performance','topSpeedKmh')} onChange={value => updateGroup('performance','topSpeedKmh',numberOrNull(value))} />
          <Field label="Rated motor power (W)" type="number" value={valueAt(draft,'performance','ratedMotorPowerW')} onChange={value => updateGroup('performance','ratedMotorPowerW',numberOrNull(value))} />
          <Field label="Peak motor power (W)" type="number" value={valueAt(draft,'performance','peakMotorPowerW')} onChange={value => updateGroup('performance','peakMotorPowerW',numberOrNull(value))} />
        </div></section>
        <section className="space-y-4"><div className="flex items-center justify-between border-b border-slate-800 pb-3"><h3 className="font-semibold">Official evidence</h3><Button variant="outline" className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900" onClick={() => updateTop('sources',[...(draft.sources || []),{url:'',publisher:draft.brandName || '',type:'manufacturer'}])}><Plus />Source</Button></div>
          {(draft.sources || []).map((source,index) => <div key={index} className="grid gap-3 sm:grid-cols-[1fr_10rem_auto]"><Input aria-label={`Source URL ${index + 1}`} placeholder="https://official.example/spec" value={String(source.url || '')} onChange={event => { const sources=[...(draft.sources || [])]; sources[index]={...sources[index],url:event.target.value}; updateTop('sources',sources); }} /><Input aria-label={`Publisher ${index + 1}`} placeholder="Publisher" value={String(source.publisher || '')} onChange={event => { const sources=[...(draft.sources || [])]; sources[index]={...sources[index],publisher:event.target.value}; updateTop('sources',sources); }} /><Button variant="ghost" size="icon" onClick={() => updateTop('sources',(draft.sources || []).filter((_,itemIndex)=>itemIndex!==index))}><X /></Button></div>)}
          <input ref={fileRef} className="hidden" type="file" accept="image/jpeg,image/png,image/webp" onChange={event => { const file=event.target.files?.[0]; if(file) void upload(file); }} />
          <Button variant="outline" className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900" disabled={!draft.catalogId || busy === 'media'} onClick={() => fileRef.current?.click()}>{busy === 'media' ? <Loader2 className="animate-spin" /> : <ImagePlus />}Upload approved image</Button>
        </section>
        {errors.length > 0 && <div role="alert" className="border-l-2 border-amber-400 bg-amber-400/5 p-4"><p className="font-medium text-amber-300">Publish checks</p><ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-amber-100">{errors.map(error => <li key={error}>{error}</li>)}</ul></div>}
      </div>
      <footer className="sticky bottom-0 flex flex-wrap justify-end gap-3 border-t border-slate-800 bg-slate-950/95 px-5 py-4 backdrop-blur sm:px-8"><Button variant="outline" className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900" onClick={onClose}>Cancel</Button><Button variant="secondary" disabled={Boolean(busy)} onClick={() => void save()}>{busy === 'save' && <Loader2 className="animate-spin" />}Save draft</Button><Button disabled={Boolean(busy) || !draft.catalogId} onClick={() => void publish()}>{busy === 'publish' && <Loader2 className="animate-spin" />}Review & publish</Button></footer>
    </div>
  </ModalSurface>;
}

function ResearchWizard({ onClose, onCandidate }: { onClose: () => void; onCandidate: (entry: CatalogEntry) => void }) {
  const [mode,setMode]=useState<'url'|'search'>('url'); const [brand,setBrand]=useState('VinFast'); const [brandId,setBrandId]=useState('vinfast'); const [domain,setDomain]=useState('vinfastauto.com'); const [input,setInput]=useState(''); const [busy,setBusy]=useState(false); const [job,setJob]=useState<Dictionary | null>(null);
  const poll = useCallback(async (jobId: string) => { for(let count=0;count<40;count+=1){ const response=await catalogResearchGet(jobId); const current=response.data as Dictionary; setJob(current); if(['needs_review','failed'].includes(String(current.status))){ const result=current.result as Dictionary | undefined; if(current.status==='needs_review' && result?.candidate){ onCandidate({ ...emptyDraft(), ...(result.candidate as CatalogEntry), brandId, brandName:brand, sources:(result.sources as Dictionary[]) || [], conflicts:(result.conflicts as Dictionary[]) || [] }); } return; } await new Promise(resolve=>setTimeout(resolve,1500)); } },[brand,brandId,onCandidate]);
  const run = async () => { setBusy(true); try { await catalogManufacturerSave(brandId,{name:brand,officialDomains:[domain]}); const response=await catalogResearchCreate({mode,brandId,brandName:brand,market:'VN',urls:mode==='url'?[input]:undefined,query:mode==='search'?input:undefined}); const created=response.data as Dictionary; setJob(created); await poll(String(created.jobId)); } catch(error){toast.error(error instanceof Error?error.message:'Research failed');} finally{setBusy(false);} };
  return <ModalSurface label="Research vehicle" onClose={onClose} busy={busy}><div className="rounded-xl bg-card p-6 sm:p-8"><div className="flex items-start justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Official-source research</p><h2 className="mt-2 text-2xl font-semibold">Build a reviewed draft</h2><p className="mt-2 max-w-lg text-sm text-muted-foreground">Extraction never publishes automatically. Technical values remain empty when the source is unclear.</p></div><Button variant="ghost" size="icon" onClick={onClose}><X /></Button></div><div className="mt-7 grid gap-4 sm:grid-cols-2"><Field label="Manufacturer" value={brand} onChange={setBrand}/><Field label="Brand ID" value={brandId} onChange={setBrandId}/><Field label="Official domain" value={domain} onChange={setDomain}/><label className="space-y-1.5 text-sm"><span className="font-medium">Research mode</span><select className="min-h-10 w-full rounded-md border bg-background px-3" value={mode} onChange={event=>setMode(event.target.value as 'url'|'search')}><option value="url">Official URL / PDF</option><option value="search">Gemini grounded search</option></select></label><div className="sm:col-span-2"><Field label={mode==='url'?'Official HTTPS URL':'Exact model, variant, year and market'} value={input} onChange={setInput}/></div></div>{job && <motion.div initial={{opacity:0,y:8}} animate={{opacity:1,y:0}} className="mt-5 flex items-center gap-3 border-l-2 border-primary bg-primary/5 p-4"><Loader2 className={`h-4 w-4 ${['pending','running'].includes(String(job.status))?'animate-spin':''}`}/><div><p className="text-sm font-medium">{String(job.status).replace('_',' ')}</p>{Boolean(job.error) && <p className="text-xs text-destructive">{String(job.error)}</p>}</div></motion.div>}<div className="mt-7 flex justify-end gap-3"><Button variant="outline" onClick={onClose}>Cancel</Button><Button disabled={busy || !input || !brandId || !domain} onClick={()=>void run()}>{busy?<Loader2 className="animate-spin"/>:<Sparkles/>}Start research</Button></div></div></ModalSurface>;
}

export default function VehicleCatalog() {
  const [entries,setEntries]=useState<CatalogEntry[]>([]); const [loading,setLoading]=useState(true); const [query,setQuery]=useState(''); const [status,setStatus]=useState('all'); const [type,setType]=useState('all'); const [brand,setBrand]=useState('all'); const [market,setMarket]=useState('all'); const [year,setYear]=useState('all'); const [quality,setQuality]=useState('all'); const [selected,setSelected]=useState<CatalogEntry|null>(null); const [editor,setEditor]=useState<CatalogEntry|null>(null); const [research,setResearch]=useState(false); const [history,setHistory]=useState<Dictionary[]>([]);
  const load=useCallback(async()=>{setLoading(true);try{const response=await catalogList();setEntries(response.data||[]);}catch(error){toast.error(error instanceof Error?error.message:'Catalog could not be loaded');}finally{setLoading(false);}},[]);
  useEffect(()=>{void load();},[load]);
  const brands=useMemo(()=>[...new Set(entries.map(entry=>entry.brandName).filter(Boolean) as string[])].sort(),[entries]);
  const markets=useMemo(()=>[...new Set(entries.map(entry=>entry.market).filter(Boolean) as string[])].sort(),[entries]);
  const years=useMemo(()=>[...new Set(entries.map(entry=>entry.modelYear).filter(Boolean) as number[])].sort((a,b)=>b-a),[entries]);
  const filtered=useMemo(()=>entries.filter(entry=>{const haystack=`${displayName(entry)} ${entry.brandName||''} ${entry.model||''} ${entry.variant||''}`.toLowerCase(); const matchesStatus=status==='all'||(status==='archived'?entry.selectable===false:entry.status===status); return haystack.includes(query.toLowerCase())&&matchesStatus&&(type==='all'||entry.vehicleType===type)&&(brand==='all'||entry.brandName===brand)&&(market==='all'||entry.market===market)&&(year==='all'||String(entry.modelYear)===year)&&(quality==='all'||evidenceQuality(entry)===quality);}),[entries,query,status,type,brand,market,year,quality]);
  const open=async(entry:CatalogEntry)=>{setSelected(entry);try{const response=await catalogGet(entry.catalogId);setHistory(response.data?.history||[]);}catch{setHistory([]);}};
  const counts={published:entries.filter(item=>item.status==='published'&&item.selectable!==false).length,draft:entries.filter(item=>item.status==='draft').length,archived:entries.filter(item=>item.selectable===false).length,review:entries.filter(item=>(item.conflicts||[]).some(conflict=>!conflict.resolved)).length};
  const toggleArchive=async(entry:CatalogEntry)=>{try{entry.selectable===false?await catalogRestore(entry.catalogId):await catalogArchive(entry.catalogId);toast.success(entry.selectable===false?'Configuration restored':'Configuration archived');setSelected(null);await load();}catch(error){toast.error(error instanceof Error?error.message:'Status change failed');}};
  return <div className="space-y-6"><div className="page-header"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">Global EV reference data</p><h1 className="mt-2 text-3xl font-bold">Vehicle catalog</h1><p className="mt-1 max-w-3xl text-muted-foreground">Review manufacturer specifications once, then synchronize safe defaults to every app installation.</p></div><div className="flex gap-2"><Button variant="outline" onClick={()=>setResearch(true)}><FileSearch/>Research vehicle</Button><Button onClick={()=>setEditor(emptyDraft())}><Plus/>New configuration</Button></div></div>
    <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border bg-border sm:grid-cols-4">{[['Published',counts.published],['Drafts',counts.draft],['Archived',counts.archived],['Needs review',counts.review]].map(([label,value])=><button key={String(label)} className="bg-card px-5 py-4 text-left transition-colors hover:bg-muted" onClick={()=>setStatus(label==='Published'?'published':label==='Drafts'?'draft':label==='Archived'?'archived':'all')}><p className="text-2xl font-semibold tabular-nums">{value}</p><p className="mt-1 text-xs text-muted-foreground">{label}</p></button>)}</div>
    <div className="flex flex-wrap gap-3 border-b pb-5"><div className="relative min-w-64 flex-1"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"/><Input aria-label="Search vehicle catalog" className="pl-10" placeholder="Search brand, model or variant" value={query} onChange={event=>setQuery(event.target.value)}/></div><select aria-label="Catalog status" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={status} onChange={event=>setStatus(event.target.value)}><option value="all">All statuses</option><option value="published">Published</option><option value="draft">Draft</option><option value="archived">Archived</option></select><select aria-label="Manufacturer" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={brand} onChange={event=>setBrand(event.target.value)}><option value="all">All brands</option>{brands.map(value=><option key={value}>{value}</option>)}</select><select aria-label="Vehicle type" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={type} onChange={event=>setType(event.target.value)}><option value="all">All vehicle types</option>{['scooter','motorcycle','car','suv','pickup','van','bus','truck','other'].map(value=><option key={value}>{value}</option>)}</select><select aria-label="Market" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={market} onChange={event=>setMarket(event.target.value)}><option value="all">All markets</option>{markets.map(value=><option key={value}>{value}</option>)}</select><select aria-label="Model year" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={year} onChange={event=>setYear(event.target.value)}><option value="all">All years</option>{years.map(value=><option key={value}>{value}</option>)}</select><select aria-label="Evidence quality" className="min-h-10 rounded-md border bg-background px-3 text-sm" value={quality} onChange={event=>setQuality(event.target.value)}><option value="all">All evidence</option><option value="sourced">Officially sourced</option><option value="conflicting">Conflicting</option><option value="missing">Missing source</option></select><Button variant="ghost" size="icon" title="Refresh catalog" onClick={()=>void load()}><RefreshCw className={loading?'animate-spin':''}/></Button></div>
    <div className="overflow-x-auto"><table className="w-full min-w-[1040px] text-sm"><thead><tr className="border-b text-left text-xs text-muted-foreground"><th className="py-3 pr-3 font-medium">Configuration</th><th className="px-3 py-3 font-medium">Type / market</th><th className="px-3 py-3 font-medium">Battery</th><th className="px-3 py-3 font-medium">Range</th><th className="px-3 py-3 font-medium">Evidence</th><th className="px-3 py-3 font-medium">Revision</th><th className="px-3 py-3 font-medium">Status</th><th className="py-3 pl-3 text-right font-medium">Open</th></tr></thead><tbody><AnimatePresence initial={false}>{filtered.map((entry,index)=><motion.tr layout key={`${entry.catalogId}:${entry.status}`} initial={{opacity:0,y:6}} animate={{opacity:1,y:0}} exit={{opacity:0}} transition={{delay:Math.min(index*.025,.2)}} className="border-b border-border/60 hover:bg-muted/45"><td className="py-3 pr-3"><div className="flex items-center gap-3">{entry.media?.thumbnailUrl?<img className="h-12 w-16 rounded-lg object-cover" src={String(entry.media.thumbnailUrl)} alt=""/>:<div className="grid h-12 w-16 place-items-center rounded-lg bg-muted"><Globe2 className="h-5 w-5 text-muted-foreground"/></div>}<div><p className="font-semibold">{displayName(entry)}</p><p className="text-xs text-muted-foreground">{entry.brandName} · {entry.variant} · {entry.modelYear}</p></div></div></td><td className="px-3 py-3 capitalize">{entry.vehicleType} · {entry.market}</td><td className="px-3 py-3 tabular-nums">{formatCapacity(valueAt(entry,'appDefaults','calculationCapacityWh'))}</td><td className="px-3 py-3 tabular-nums">{valueAt(entry,'performance','rangeKm')?`${valueAt(entry,'performance','rangeKm')} km`:'—'}</td><td className="px-3 py-3 capitalize">{evidenceQuality(entry).replace('_',' ')}</td><td className="px-3 py-3 tabular-nums">v{entry.revision||0}</td><td className="px-3 py-3"><StatusBadge entry={entry}/></td><td className="py-3 pl-3 text-right"><Button variant="ghost" size="sm" onClick={()=>void open(entry)}>Inspect<ChevronRight/></Button></td></motion.tr>)}</AnimatePresence></tbody></table>{!loading&&filtered.length===0&&<div className="grid min-h-64 place-items-center text-center"><div><Globe2 className="mx-auto h-8 w-8 text-muted-foreground"/><p className="mt-3 font-medium">No matching configurations</p><p className="mt-1 text-sm text-muted-foreground">Create a draft or adjust the filters.</p></div></div>}</div>
    {selected&&<ModalSurface drawer label="Catalog configuration details" onClose={()=>setSelected(null)}><div className="min-h-full bg-slate-950 p-6 text-slate-100 sm:p-8"><div className="flex items-start justify-between border-b border-slate-800 pb-5"><div><p className="text-xs font-semibold uppercase tracking-[.18em] text-emerald-400">{selected.brandName} · {selected.market}</p><h2 className="mt-2 text-2xl font-semibold">{displayName(selected)}</h2><div className="mt-3"><StatusBadge entry={selected}/></div></div><Button variant="ghost" size="icon" className="text-slate-300 hover:bg-slate-800 hover:text-white" onClick={()=>setSelected(null)}><X/></Button></div>{Boolean(selected.media?.heroUrl)&&<motion.img layoutId={`vehicle-${selected.catalogId}`} className="mt-6 aspect-[16/7] w-full rounded-2xl object-cover" src={String(selected.media?.heroUrl)} alt={displayName(selected)}/>}<div className="mt-7 grid grid-cols-2 gap-5"><Metric label="Calculation battery" value={formatCapacity(valueAt(selected,'appDefaults','calculationCapacityWh'))}/><Metric label="Safe charge power" value={formatPower(valueAt(selected,'appDefaults','maxSafeChargePowerW'))}/><Metric label="Published range" value={valueAt(selected,'performance','rangeKm')?`${valueAt(selected,'performance','rangeKm')} km`:'—'}/><Metric label="Top speed" value={valueAt(selected,'performance','topSpeedKmh')?`${valueAt(selected,'performance','topSpeedKmh')} km/h`:'—'}/></div><div className="mt-8 border-t border-slate-800 pt-6"><h3 className="flex items-center gap-2 font-semibold"><BookOpenCheck className="h-4 w-4 text-emerald-400"/>Evidence</h3><div className="mt-3 space-y-3">{(selected.sources||[]).map((source,index)=><a key={index} className="block break-all text-sm text-emerald-300 hover:underline" href={String(source.url)} target="_blank" rel="noreferrer">{String(source.publisher||'Official source')} · {String(source.url)}</a>)}{!(selected.sources||[]).length&&<p className="text-sm text-slate-400">No sources attached.</p>}</div></div><div className="mt-8 border-t border-slate-800 pt-6"><h3 className="font-semibold">Revision history</h3><div className="mt-3 divide-y divide-slate-800">{history.map((revision,index)=><div key={index} className="flex justify-between py-3 text-sm"><span>Revision {String(revision.revision||'—')}</span><span className="text-slate-400">{String(revision.publishedAt||'')}</span></div>)}</div></div><div className="mt-8 flex flex-wrap gap-3"><Button onClick={()=>{setEditor(selected);setSelected(null);}}>Edit draft</Button>{selected.status==='published'&&<Button variant="outline" className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900" onClick={()=>void toggleArchive(selected)}>{selected.selectable===false?<Check/>:<Archive/>}{selected.selectable===false?'Restore':'Archive'}</Button>}</div></div></ModalSurface>}
    {editor&&<Editor initial={editor} onClose={()=>setEditor(null)} onSaved={load}/>} {research&&<ResearchWizard onClose={()=>setResearch(false)} onCandidate={candidate=>{setResearch(false);setEditor(candidate);}}/>}
  </div>;
}
