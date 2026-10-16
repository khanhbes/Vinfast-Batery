import { useMemo, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, ImagePlus, Loader2, RotateCw, Star, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { catalogUpdateShowroom, catalogUploadMedia } from '@/api';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';

type Dictionary = Record<string, unknown>;
type Angle = { thumbnailUrl?: string; mediumUrl?: string; heroUrl?: string; checksum?: string; backgroundRemoved?: boolean };
type ShowroomColor = { id: string; name: string; swatchHex: string; angles: Angle[] };
type Showroom = { defaultColorId: string; colors: ShowroomColor[] };

const SPIN_MIN = 12;
const MAX_ANGLES = 36;
const MAX_COLORS = 8;
const DEFAULT_CREDIT = '© VinFast Trading and Production JSC';

const slug = (value: string) => value
  .normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd')
  .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);

export const readShowroom = (media: Dictionary | undefined): Showroom | null => {
  const raw = media?.showroom;
  if (!raw || typeof raw !== 'object') return null;
  const data = raw as Dictionary;
  const colors = Array.isArray(data.colors) ? (data.colors as ShowroomColor[]).filter(c => c && c.id && Array.isArray(c.angles)) : [];
  if (!colors.length) return null;
  return { defaultColorId: String(data.defaultColorId || colors[0].id), colors };
};

/** Turntable preview: drag across the image (or use the slider) to spin. */
export function SpinPreview({ angles }: { angles: Angle[] }) {
  const [index, setIndex] = useState(0);
  const start = useRef<{ x: number; index: number } | null>(null);
  if (!angles.length) return null;
  const current = angles[Math.min(index, angles.length - 1)];
  const spin = angles.length >= SPIN_MIN;
  return <div className="space-y-2">
    <div
      className="relative grid aspect-[16/10] w-full cursor-grab touch-none select-none place-items-center overflow-hidden rounded-xl bg-[radial-gradient(ellipse_at_top,#2a2c30_0%,#0b0c0e_70%)] active:cursor-grabbing"
      onPointerDown={event => { start.current = { x: event.clientX, index }; (event.target as Element).setPointerCapture?.(event.pointerId); }}
      onPointerMove={event => {
        if (!start.current || !spin) return;
        const width = (event.currentTarget as HTMLDivElement).clientWidth || 1;
        const step = Math.round(-(event.clientX - start.current.x) / (width * 1.4 / angles.length));
        setIndex(((start.current.index + step) % angles.length + angles.length) % angles.length);
      }}
      onPointerUp={() => { start.current = null; }}
    >
      <img className="max-h-full max-w-full object-contain" src={current.mediumUrl || current.heroUrl || current.thumbnailUrl} alt="" draggable={false} />
      <span className="absolute right-3 top-3 rounded-full border border-white/10 bg-black/60 px-2.5 py-1 text-xs tabular-nums text-slate-200">
        {spin ? `360° · ${index + 1}/${angles.length}` : `2.5D · ${angles.length} ảnh (cần ${SPIN_MIN} góc để xoay 360°)`}
      </span>
    </div>
    {spin && <input aria-label="Góc xem" className="w-full accent-emerald-400" type="range" min={0} max={angles.length - 1} value={index} onChange={event => setIndex(Number(event.target.value))} />}
  </div>;
}

export function ShowroomEditor({ catalogId, media, onMedia, ensureDraft }: {
  catalogId: string; media: Dictionary | undefined; onMedia: (media: Dictionary) => void;
  /** Published entries have no draft document; create one before writing media. */
  ensureDraft?: () => Promise<boolean>;
}) {
  const saved = useMemo(() => readShowroom(media), [media]);
  const [local, setLocal] = useState<Showroom | null>(saved);
  const [dirty, setDirty] = useState(false);
  const [rights, setRights] = useState(false);
  const [credit, setCredit] = useState(DEFAULT_CREDIT);
  const [sourceUrl, setSourceUrl] = useState('https://vinfastauto.com/');
  const [removeBackground, setRemoveBackground] = useState(true);
  const [newColor, setNewColor] = useState({ name: '', swatchHex: '#C8102E' });
  const [progress, setProgress] = useState<{ colorId: string; done: number; total: number } | null>(null);
  const [selected, setSelected] = useState<string>(saved?.defaultColorId || '');
  const fileRef = useRef<HTMLInputElement>(null);
  const uploadTarget = useRef<{ id: string; name: string; swatchHex: string } | null>(null);
  const showroom = dirty ? local : saved;
  const active = showroom?.colors.find(c => c.id === selected) || showroom?.colors[0];

  const startUpload = (target: { id: string; name: string; swatchHex: string }) => {
    if (!catalogId) { toast.error('Lưu bản nháp trước khi tải ảnh'); return; }
    if (!rights) { toast.error('Hãy xác nhận quyền sử dụng ảnh trước'); return; }
    if (!target.id) { toast.error('Nhập tên màu'); return; }
    if (dirty) { toast.error('Lưu thay đổi thứ tự/màu trước khi tải thêm ảnh'); return; }
    uploadTarget.current = target;
    fileRef.current?.click();
  };

  const uploadFiles = async (files: File[]) => {
    const target = uploadTarget.current;
    if (!target || !files.length) return;
    if (ensureDraft && !(await ensureDraft())) return;
    const existing = saved?.colors.find(c => c.id === target.id)?.angles.length || 0;
    const room = MAX_ANGLES - existing;
    const sorted = [...files].sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true })).slice(0, Math.max(0, room));
    if (sorted.length < files.length) toast.warning(`Chỉ nhận tối đa ${MAX_ANGLES} góc mỗi màu`);
    let latest: Dictionary | null = null;
    setProgress({ colorId: target.id, done: 0, total: sorted.length });
    try {
      for (let i = 0; i < sorted.length; i += 1) {
        const result = await catalogUploadMedia(catalogId, sorted[i], {
          kind: 'angle', colorId: target.id, colorName: target.name, swatchHex: target.swatchHex,
          sourceUrl, credit, licenseNote: 'Ảnh chính thức, quản trị viên xác nhận quyền sử dụng',
          rightsConfirmed: true, removeBackground,
        });
        latest = result.data as Dictionary;
        setProgress({ colorId: target.id, done: i + 1, total: sorted.length });
      }
      toast.success(`Đã tải ${sorted.length} ảnh cho màu ${target.name}`, { description: 'Bấm "Review & publish" để app nhận ảnh mới.' });
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Tải ảnh thất bại');
    } finally {
      setProgress(null);
      if (latest) { onMedia(latest); setSelected(target.id); }
    }
  };

  const edit = (mutate: (draft: Showroom) => void) => {
    const base = structuredClone(showroom) as Showroom | null;
    if (!base) return;
    mutate(base);
    setLocal(base); setDirty(true);
  };

  const saveChanges = async () => {
    if (!local) return;
    if (ensureDraft && !(await ensureDraft())) return;
    try {
      const result = await catalogUpdateShowroom(catalogId, {
        defaultColorId: local.defaultColorId,
        colors: local.colors.map(c => ({ id: c.id, name: c.name, swatchHex: c.swatchHex, angleChecksums: c.angles.map(a => a.checksum) })),
      });
      onMedia(result.data as Dictionary); setDirty(false); toast.success('Đã lưu phòng trưng bày');
    } catch (error) { toast.error(error instanceof Error ? error.message : 'Không lưu được'); }
  };

  return <div className="space-y-4 border border-slate-800 bg-slate-900/40 p-4">
    <input ref={fileRef} className="hidden" type="file" multiple accept="image/jpeg,image/png,image/webp" onChange={event => { const files = Array.from(event.target.files || []); event.currentTarget.value = ''; void uploadFiles(files); }} />
    <div>
      <p className="font-medium">Phòng trưng bày (2.5D / 360°)</p>
      <p className="mt-1 text-xs text-slate-400">Mỗi màu một chuỗi ảnh chụp quanh xe, đặt tên file theo thứ tự góc (01, 02…). Từ {SPIN_MIN} góc trở lên app tự bật xoay 360°; ít hơn sẽ hiển thị dạng 2.5D. Nền trắng/xám sáng được tách tự động.</p>
      <p className="mt-1 text-xs text-emerald-300/90">Ảnh được lưu vào bản nháp; app chỉ nhận sau khi bấm "Review & publish".</p>
    </div>
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="space-y-1.5 text-sm"><span className="font-medium">Ghi nguồn (credit)</span><Input value={credit} onChange={event => setCredit(event.target.value)} /></label>
      <label className="space-y-1.5 text-sm"><span className="font-medium">Link trang nguồn chính thức</span><Input value={sourceUrl} onChange={event => setSourceUrl(event.target.value)} /></label>
    </div>
    <div className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
      <label className="flex items-center gap-2"><input type="checkbox" checked={rights} onChange={event => setRights(event.target.checked)} />Tôi xác nhận có quyền sử dụng và lưu trữ các ảnh này</label>
      <label className="flex items-center gap-2"><input type="checkbox" checked={removeBackground} onChange={event => setRemoveBackground(event.target.checked)} />Tự tách nền trắng</label>
    </div>

    {showroom && <div className="flex flex-wrap gap-2">{showroom.colors.map(color => <button key={color.id} type="button" onClick={() => setSelected(color.id)} className={`flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm ${active?.id === color.id ? 'border-emerald-400 text-white' : 'border-slate-700 text-slate-300'}`}>
      <span className="h-4 w-4 rounded-full border border-white/20" style={{ background: color.swatchHex }} />{color.name}<span className="text-xs text-slate-500">{color.angles.length}</span>{showroom.defaultColorId === color.id && <Star className="h-3.5 w-3.5 text-emerald-400" />}
    </button>)}</div>}

    {active && <div className="space-y-3">
      <SpinPreview key={active.id + active.angles.length} angles={active.angles} />
      <div className="grid gap-3 sm:grid-cols-[1fr_8rem_auto]">
        <Input aria-label="Tên màu" value={active.name} onChange={event => edit(d => { const c = d.colors.find(x => x.id === active.id); if (c) c.name = event.target.value; })} />
        <Input aria-label="Mã màu swatch" type="color" value={active.swatchHex} onChange={event => edit(d => { const c = d.colors.find(x => x.id === active.id); if (c) c.swatchHex = event.target.value.toUpperCase(); })} />
        <div className="flex gap-2">
          <Button type="button" variant="outline" className="border-slate-700 bg-transparent text-slate-100" onClick={() => edit(d => { d.defaultColorId = active.id; })}><Star />Mặc định</Button>
          <Button type="button" variant="outline" className="border-slate-700 bg-transparent text-slate-100" disabled={Boolean(progress)} onClick={() => startUpload(active)}>{progress?.colorId === active.id ? <Loader2 className="animate-spin" /> : <ImagePlus />}Thêm góc</Button>
        </div>
      </div>
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">{active.angles.map((angle, index) => <figure key={angle.checksum || index} className="group relative overflow-hidden rounded-lg border border-slate-800 bg-slate-950">
        <img className="aspect-[16/10] w-full object-contain" src={angle.thumbnailUrl || angle.mediumUrl} alt={`Góc ${index + 1}`} />
        <figcaption className="flex items-center justify-between px-1.5 py-1 text-[11px] text-slate-400"><span>#{index + 1}{angle.backgroundRemoved ? ' · tách nền' : ''}</span>
          <span className="flex gap-0.5">
            <button type="button" aria-label="Lên" disabled={index === 0} className="rounded p-0.5 hover:bg-slate-800 disabled:opacity-30" onClick={() => edit(d => { const a = d.colors.find(x => x.id === active.id)!.angles; [a[index - 1], a[index]] = [a[index], a[index - 1]]; })}><ArrowUp className="h-3 w-3" /></button>
            <button type="button" aria-label="Xuống" disabled={index === active.angles.length - 1} className="rounded p-0.5 hover:bg-slate-800 disabled:opacity-30" onClick={() => edit(d => { const a = d.colors.find(x => x.id === active.id)!.angles; [a[index + 1], a[index]] = [a[index], a[index + 1]]; })}><ArrowDown className="h-3 w-3" /></button>
            <button type="button" aria-label="Xóa góc" className="rounded p-0.5 text-rose-300 hover:bg-slate-800" onClick={() => edit(d => { const c = d.colors.find(x => x.id === active.id)!; c.angles.splice(index, 1); })}><Trash2 className="h-3 w-3" /></button>
          </span>
        </figcaption>
      </figure>)}</div>
    </div>}

    {progress && <div className="space-y-1"><div className="h-1.5 overflow-hidden rounded-full bg-slate-800"><div className="h-full bg-emerald-400 transition-all" style={{ width: `${(progress.done / Math.max(1, progress.total)) * 100}%` }} /></div><p className="text-xs text-slate-400">Đang tải và tách nền {progress.done}/{progress.total}…</p></div>}

    {dirty && <div className="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm"><span>Có thay đổi chưa lưu (tên, màu, thứ tự, xóa).</span><span className="flex gap-2"><Button type="button" variant="ghost" onClick={() => { setDirty(false); setLocal(saved); }}><RotateCw />Hoàn tác</Button><Button type="button" onClick={() => void saveChanges()}>Lưu</Button></span></div>}

    {(showroom?.colors.length || 0) < MAX_COLORS && <div className="grid gap-3 border-t border-slate-800 pt-4 sm:grid-cols-[1fr_8rem_auto]">
      <Input aria-label="Tên màu mới" placeholder="Tên màu mới (vd. Đỏ tươi)" value={newColor.name} onChange={event => setNewColor(c => ({ ...c, name: event.target.value }))} />
      <Input aria-label="Swatch màu mới" type="color" value={newColor.swatchHex} onChange={event => setNewColor(c => ({ ...c, swatchHex: event.target.value.toUpperCase() }))} />
      <Button type="button" variant="outline" className="border-slate-700 bg-transparent text-slate-100" disabled={!newColor.name.trim() || Boolean(progress)} onClick={() => startUpload({ id: slug(newColor.name), name: newColor.name.trim(), swatchHex: newColor.swatchHex })}><ImagePlus />Thêm màu & tải ảnh</Button>
    </div>}
  </div>;
}
