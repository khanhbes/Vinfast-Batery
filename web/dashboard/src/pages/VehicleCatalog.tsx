import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import {
  Archive,
  Check,
  ChevronRight,
  FileSearch,
  Globe2,
  ImagePlus,
  LayoutGrid,
  List,
  Loader2,
  Palette,
  Plus,
  RefreshCw,
  Rocket,
  Search,
  Sparkles,
  X,
} from 'lucide-react';
import { toast } from 'sonner';
import {
  catalogArchive,
  catalogCreate,
  catalogGet,
  catalogList,
  catalogManufacturerSave,
  catalogPublish,
  catalogResearchCreate,
  catalogResearchGet,
  catalogRestore,
  catalogUpdate,
  catalogUploadMedia,
} from '@/api';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ModalSurface } from '@/components/ui/modal-surface';
import { PortalHttpError } from '@/lib/httpClient';
import { ShowroomEditor, SpinPreview, readShowroom } from '@/components/catalog/ShowroomEditor';

type Dictionary = Record<string, unknown>;
type CatalogEntry = Dictionary & {
  catalogId: string;
  brandId?: string;
  brandName?: string;
  model?: string;
  variant?: string;
  modelYear?: number;
  market?: string;
  vehicleType?: string;
  status?: string;
  selectable?: boolean;
  revision?: number;
  battery?: Dictionary;
  charging?: Dictionary;
  performance?: Dictionary;
  appDefaults?: Dictionary;
  localized?: Record<string, Dictionary>;
  media?: Dictionary;
  sources?: Dictionary[];
  conflicts?: Dictionary[];
  updatedAt?: string;
};

const emptyDraft = (): CatalogEntry => ({
  catalogId: '',
  brandId: 'vinfast',
  brandName: 'VinFast',
  model: '',
  variant: '',
  modelYear: new Date().getFullYear(),
  market: 'VN',
  vehicleType: 'scooter',
  status: 'draft',
  aliases: [],
  localized: {
    vi: { displayName: '', tagline: '', description: '' },
    en: { displayName: '', tagline: '', description: '' },
  },
  battery: {
    chemistry: 'LFP',
    grossCapacityWh: null,
    usableCapacityWh: null,
    calculationCapacityWh: null,
    voltageV: null,
    capacityAh: null,
    packCount: 1,
    removable: false,
  },
  charging: {
    maxAcPowerW: null,
    maxDcPowerW: null,
    maxSafeChargePowerW: null,
    connector: '',
    chargeTimeMinutes: null,
  },
  performance: {
    ratedMotorPowerW: null,
    peakMotorPowerW: null,
    topSpeedKmh: null,
    rangeKm: null,
    rangeTestCycle: '',
    consumptionWhPerKm: null,
  },
  appDefaults: {
    calculationCapacityWh: null,
    defaultEfficiencyKmPerPercent: null,
    maxSafeChargePowerW: null,
  },
  dimensions: {},
  sources: [],
  conflicts: [],
});

const valueAt = (entry: CatalogEntry, group: string, field: string) =>
  (entry[group] as Dictionary | undefined)?.[field] ?? '';
const localizedAt = (entry: CatalogEntry, locale: string, field: string) =>
  entry.localized?.[locale]?.[field] ?? '';
const numberOrNull = (value: string) => (value.trim() === '' ? null : Number(value));
const fieldDomId = (path: string) => `catalog-${path.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
const displayName = (entry: CatalogEntry) =>
  String(
    localizedAt(entry, 'en', 'displayName') ||
      localizedAt(entry, 'vi', 'displayName') ||
      `${entry.brandName || ''} ${entry.model || ''}`.trim()
  );
const formatPower = (value: unknown) =>
  typeof value === 'number' && value > 0
    ? value >= 1000
      ? `${(value / 1000).toFixed(value % 1000 ? 1 : 0)} kW`
      : `${value} W`
    : '—';
const formatCapacity = (value: unknown) =>
  typeof value === 'number' && value > 0
    ? value >= 1000
      ? `${(value / 1000).toFixed(1)} kWh`
      : `${value} Wh`
    : '—';
const mediaViewUrl = (entry: CatalogEntry, kind: 'twoD' | 'threeD') => {
  const views = entry.media?.views;
  const asset = views && typeof views === 'object' ? (views as Dictionary)[kind] : null;
  if (!asset || typeof asset !== 'object') return '';
  const media = asset as Dictionary;
  const url = media.thumbnailUrl || media.heroUrl || media.mediumUrl;
  return typeof url === 'string' ? url : '';
};

function Field({
  label,
  value,
  onChange,
  type = 'text',
  required = false,
  error,
  fieldId,
}: {
  label: string;
  value: unknown;
  onChange: (value: string) => void;
  type?: string;
  required?: boolean;
  error?: string;
  fieldId?: string;
}) {
  return (
    <label className="space-y-1.5 text-sm">
      <span className="font-medium">
        {label}
        {required && <span className="text-destructive"> *</span>}
      </span>
      <Input
        id={fieldId}
        aria-invalid={Boolean(error)}
        aria-describedby={error ? `${fieldId}-error` : undefined}
        className={error ? 'border-destructive focus-visible:ring-destructive' : ''}
        type={type}
        value={value == null ? '' : String(value)}
        onChange={(event) => onChange(event.target.value)}
      />
      {error && (
        <span id={`${fieldId}-error`} className="block text-xs text-destructive">
          {error}
        </span>
      )}
    </label>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="border-l border-border pl-4">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 font-semibold tabular-nums">{value}</p>
    </div>
  );
}

function StatusBadge({ entry }: { entry: CatalogEntry }) {
  if (entry.status === 'draft')
    return (
      <Badge variant="outline" className="border-amber-500/40 text-amber-400 bg-amber-500/10">
        <span className="w-1.5 h-1.5 rounded-full bg-amber-400 mr-1.5" />
        Bản nháp
      </Badge>
    );
  if (entry.selectable === false)
    return (
      <Badge variant="outline" className="border-slate-700 text-muted-foreground">
        Đang ẩn
      </Badge>
    );
  return (
    <Badge className="gap-1.5 bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
      <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
      Đã xuất bản
    </Badge>
  );
}

function Editor({
  initial,
  onClose,
  onSaved,
  focus,
}: {
  initial: CatalogEntry;
  onClose: () => void;
  onSaved: () => Promise<void>;
  focus?: 'showroom';
}) {
  const [draft, setDraft] = useState<CatalogEntry>(initial);
  // Publishing deletes the draft document, so a published entry needs one recreated before media writes.
  const [hasDraft, setHasDraft] = useState(initial.status === 'draft');
  const showroomRef = useRef<HTMLElement>(null);
  useEffect(() => {
    if (focus !== 'showroom') return;
    const timer = window.setTimeout(
      () => showroomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }),
      320
    );
    return () => window.clearTimeout(timer);
  }, [focus]);
  const [busy, setBusy] = useState('');
  const [errors, setErrors] = useState<string[]>([]);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [errorMessage, setErrorMessage] = useState('');
  const [requestId, setRequestId] = useState('');
  const twoDFileRef = useRef<HTMLInputElement>(null);
  const threeDFileRef = useRef<HTMLInputElement>(null);
  const updateTop = (field: string, value: unknown) =>
    setDraft((current) => ({ ...current, [field]: value }));
  const updateGroup = (group: string, field: string, value: unknown) =>
    setDraft((current) => ({
      ...current,
      [group]: { ...((current[group] as Dictionary) || {}), [field]: value },
    }));
  const updateLocale = (locale: string, field: string, value: string) =>
    setDraft((current) => ({
      ...current,
      localized: {
        ...(current.localized || {}),
        [locale]: { ...((current.localized?.[locale] as Dictionary) || {}), [field]: value },
      },
    }));
  const payload = () => {
    const {
      catalogId: _catalogId,
      revision: _revision,
      status: _status,
      selectable: _selectable,
      updatedAt: _updatedAt,
      createdAt: _createdAt,
      identityKey: _identityKey,
      publishedAt: _publishedAt,
      ...editable
    } = draft;
    return editable;
  };
  const showError = (error: unknown) => {
    const portal = error instanceof PortalHttpError ? error : null;
    const data = (portal?.data || {}) as {
      validationErrors?: string[];
      fieldErrors?: Record<string, string>;
    };
    const nextFields = data.fieldErrors || {};
    setErrors(data.validationErrors || []);
    setFieldErrors(nextFields);
    setErrorMessage(portal?.message || 'Catalog validation failed');
    setRequestId(portal?.requestId || '');
    const first = Object.keys(nextFields)[0];
    if (first)
      window.setTimeout(() => document.getElementById(fieldDomId(first))?.focus(), 0);
  };
  const save = async () => {
    setBusy('save');
    setErrors([]);
    setFieldErrors({});
    setErrorMessage('');
    setRequestId('');
    try {
      const result = draft.catalogId
        ? await catalogUpdate(draft.catalogId, payload())
        : await catalogCreate(payload());
      setDraft(result.data as CatalogEntry);
      setHasDraft(true);
      setErrors(result.validationErrors || []);
      setFieldErrors(result.fieldErrors || {});
      setErrorMessage(
        result.validationErrors?.length
          ? 'Draft saved — complete these checks before publishing'
          : ''
      );
      toast.success('Đã lưu bản nháp');
      await onSaved();
    } catch (error) {
      showError(error);
    } finally {
      setBusy('');
    }
  };
  const publish = async () => {
    if (!draft.catalogId) {
      toast.error('Lưu bản nháp trước khi xuất bản');
      return;
    }
    setBusy('publish');
    setErrors([]);
    setFieldErrors({});
    setErrorMessage('');
    setRequestId('');
    try {
      await catalogPublish(draft.catalogId);
      toast.success('Đã xuất bản cấu hình xe xuống ứng dụng');
      await onSaved();
      onClose();
    } catch (error) {
      showError(error);
    } finally {
      setBusy('');
    }
  };
  const ensureDraft = async () => {
    if (hasDraft) return true;
    try {
      const result = await catalogUpdate(draft.catalogId, payload());
      setDraft(result.data as CatalogEntry);
      setHasDraft(true);
      toast.info('Đã tạo bản nháp từ bản công bố để thêm ảnh');
      await onSaved();
      return true;
    } catch (error) {
      showError(error);
      return false;
    }
  };
  const upload = async (file: File, kind: 'twoD' | 'threeD') => {
    if (!draft.catalogId) {
      toast.error('Lưu bản nháp trước khi tải ảnh');
      return;
    }
    setBusy('media');
    try {
      if (!(await ensureDraft())) return;
      const sourceUrl = window.prompt(`${kind === 'twoD' ? '2D photo' : '3D render'} source URL`) || '';
      const rightsConfirmed = window.confirm('Xác nhận bạn có quyền sử dụng hình ảnh này?');
      if (!rightsConfirmed) return;
      const result = await catalogUploadMedia(draft.catalogId, file, {
        kind,
        sourceUrl,
        rightsConfirmed,
        credit: '',
        licenseNote: 'Approved by administrator',
      });
      setDraft((current) => ({ ...current, media: result.data }));
      toast.success(`Đã tải lên ảnh ${kind === 'twoD' ? '2D' : '3D render'}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Image upload failed');
    } finally {
      setBusy('');
    }
  };
  const twoDUrl = mediaViewUrl(draft, 'twoD');
  const threeDUrl = mediaViewUrl(draft, 'threeD');

  return (
    <ModalSurface drawer label="Vehicle catalog editor" onClose={onClose} busy={Boolean(busy)}>
      <div className="min-h-full bg-slate-950 text-slate-100">
        <header className="sticky top-0 z-20 border-b border-slate-800 bg-slate-950/95 px-5 py-5 backdrop-blur sm:px-8">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[.18em] text-emerald-400">
                Bản nháp danh mục
              </p>
              <h2 className="mt-2 text-2xl font-semibold">
                {displayName(draft) || 'Thêm cấu hình xe'}
              </h2>
              <p className="mt-1 text-sm text-slate-400">
                Thông số kỹ thuật pin, động cơ và định mức an toàn sạc.
              </p>
            </div>
            <Button
              variant="ghost"
              size="icon"
              className="shrink-0 text-slate-300 hover:bg-slate-800 hover:text-white"
              onClick={onClose}
            >
              <X />
            </Button>
          </div>
          <AnimatePresence initial={false}>
            {errorMessage && (
              <motion.div
                key="catalog-review-errors"
                role="alert"
                initial={{ opacity: 0, y: -6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -4 }}
                className="mt-4 border-l-2 border-amber-400 bg-amber-400/10 px-4 py-3 text-left"
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-medium text-amber-200">{errorMessage}</p>
                    {errors.length > 0 && (
                      <ul className="mt-1.5 max-h-28 list-disc space-y-1 overflow-y-auto pl-5 text-xs text-amber-100/90">
                        {errors.map((error) => (
                          <li key={error}>{error}</li>
                        ))}
                      </ul>
                    )}
                    {requestId && (
                      <p className="mt-2 font-mono text-[11px] text-slate-400">
                        Request ID: {requestId}
                      </p>
                    )}
                  </div>
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label="Dismiss validation message"
                    className="h-8 w-8 shrink-0 text-amber-100 hover:bg-amber-400/10"
                    onClick={() => setErrorMessage('')}
                  >
                    <X className="h-4 w-4" />
                  </Button>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </header>

        <div className="space-y-9 p-5 sm:p-8">
          <section className="space-y-4">
            <h3 className="border-b border-slate-800 pb-3 font-semibold">Định danh phương tiện</h3>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field
                label="Hãng xe (Brand)"
                required
                fieldId="catalog-brandName"
                error={fieldErrors.brandName}
                value={draft.brandName}
                onChange={(value) => updateTop('brandName', value)}
              />
              <Field
                label="Mã hãng (Brand ID)"
                required
                fieldId="catalog-brandId"
                error={fieldErrors.brandId}
                value={draft.brandId}
                onChange={(value) => updateTop('brandId', value)}
              />
              <Field
                label="Dòng xe (Model)"
                required
                fieldId="catalog-model"
                error={fieldErrors.model}
                value={draft.model}
                onChange={(value) => updateTop('model', value)}
              />
              <Field
                label="Phiên bản (Variant)"
                required
                fieldId="catalog-variant"
                error={fieldErrors.variant}
                value={draft.variant}
                onChange={(value) => updateTop('variant', value)}
              />
              <Field
                label="Năm sản xuất (Model year)"
                required
                fieldId="catalog-modelYear"
                error={fieldErrors.modelYear}
                type="number"
                value={draft.modelYear}
                onChange={(value) => updateTop('modelYear', Number(value))}
              />
              <Field
                label="Thị trường (Market)"
                required
                fieldId="catalog-market"
                error={fieldErrors.market}
                value={draft.market}
                onChange={(value) => updateTop('market', value.toUpperCase())}
              />
              <label className="space-y-1.5 text-sm">
                <span className="font-medium">Loại phương tiện *</span>
                <select
                  className="min-h-10 w-full rounded-md border border-slate-700 bg-slate-900 px-3"
                  value={draft.vehicleType}
                  onChange={(event) => updateTop('vehicleType', event.target.value)}
                >
                  {['scooter', 'motorcycle', 'car', 'suv', 'pickup', 'van', 'bus', 'truck', 'other'].map(
                    (value) => (
                      <option key={value}>{value}</option>
                    )
                  )}
                </select>
              </label>
            </div>
          </section>

          <section className="space-y-4">
            <h3 className="border-b border-slate-800 pb-3 font-semibold">Tên hiển thị & Mô tả</h3>
            {['vi', 'en'].map((locale) => (
              <div key={locale} className="grid gap-4 sm:grid-cols-2">
                <Field
                  label={`Tên hiển thị (${locale.toUpperCase()})`}
                  required
                  fieldId={`catalog-localized-${locale}-displayName`}
                  error={fieldErrors[`localized.${locale}.displayName`]}
                  value={localizedAt(draft, locale, 'displayName')}
                  onChange={(value) => updateLocale(locale, 'displayName', value)}
                />
                <Field
                  label={`Tagline ngắn (${locale.toUpperCase()})`}
                  value={localizedAt(draft, locale, 'tagline')}
                  onChange={(value) => updateLocale(locale, 'tagline', value)}
                />
                <div className="sm:col-span-2">
                  <label className="space-y-1.5 text-sm">
                    <span className="font-medium">Mô tả chi tiết ({locale.toUpperCase()})</span>
                    <textarea
                      className="min-h-24 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                      value={String(localizedAt(draft, locale, 'description'))}
                      onChange={(event) => updateLocale(locale, 'description', event.target.value)}
                    />
                  </label>
                </div>
              </div>
            ))}
          </section>

          <section className="space-y-4">
            <h3 className="border-b border-slate-800 pb-3 font-semibold">Thông số Pin & Định mức tính toán</h3>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field
                label="Dung lượng tính toán (Wh)"
                required
                fieldId="catalog-appDefaults-calculationCapacityWh"
                error={fieldErrors['appDefaults.calculationCapacityWh']}
                type="number"
                value={valueAt(draft, 'appDefaults', 'calculationCapacityWh')}
                onChange={(value) =>
                  updateGroup('appDefaults', 'calculationCapacityWh', numberOrNull(value))
                }
              />
              <Field
                label="Hiệu suất mặc định (km/%)"
                required
                fieldId="catalog-appDefaults-defaultEfficiencyKmPerPercent"
                error={fieldErrors['appDefaults.defaultEfficiencyKmPerPercent']}
                type="number"
                value={valueAt(draft, 'appDefaults', 'defaultEfficiencyKmPerPercent')}
                onChange={(value) =>
                  updateGroup('appDefaults', 'defaultEfficiencyKmPerPercent', numberOrNull(value))
                }
              />
              <Field
                label="Dung lượng danh định (Wh)"
                type="number"
                value={valueAt(draft, 'battery', 'grossCapacityWh')}
                onChange={(value) =>
                  updateGroup('battery', 'grossCapacityWh', numberOrNull(value))
                }
              />
              <Field
                label="Dung lượng khả dụng (Wh)"
                type="number"
                value={valueAt(draft, 'battery', 'usableCapacityWh')}
                onChange={(value) =>
                  updateGroup('battery', 'usableCapacityWh', numberOrNull(value))
                }
              />
              <Field
                label="Công nghệ Pin (Chemistry)"
                value={valueAt(draft, 'battery', 'chemistry')}
                onChange={(value) => updateGroup('battery', 'chemistry', value)}
              />
              <Field
                label="Điện áp định mức (V)"
                type="number"
                value={valueAt(draft, 'battery', 'voltageV')}
                onChange={(value) => updateGroup('battery', 'voltageV', numberOrNull(value))}
              />
              <Field
                label="Dung lượng Ampe giờ (Ah)"
                type="number"
                value={valueAt(draft, 'battery', 'capacityAh')}
                onChange={(value) => updateGroup('battery', 'capacityAh', numberOrNull(value))}
              />
              <Field
                label="Giới hạn an toàn sạc (W)"
                type="number"
                value={valueAt(draft, 'appDefaults', 'maxSafeChargePowerW')}
                onChange={(value) =>
                  updateGroup('appDefaults', 'maxSafeChargePowerW', numberOrNull(value))
                }
              />
            </div>
          </section>

          <section className="space-y-4">
            <h3 className="border-b border-slate-800 pb-3 font-semibold">Khả năng sạc & Vận hành</h3>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field
                label="Công suất AC tối đa (W)"
                type="number"
                value={valueAt(draft, 'charging', 'maxAcPowerW')}
                onChange={(value) => updateGroup('charging', 'maxAcPowerW', numberOrNull(value))}
              />
              <Field
                label="Công suất DC tối đa (W)"
                type="number"
                value={valueAt(draft, 'charging', 'maxDcPowerW')}
                onChange={(value) => updateGroup('charging', 'maxDcPowerW', numberOrNull(value))}
              />
              <Field
                label="Chuẩn cổng sạc"
                value={valueAt(draft, 'charging', 'connector')}
                onChange={(value) => updateGroup('charging', 'connector', value)}
              />
              <Field
                label="Quãng đường công bố (km)"
                type="number"
                value={valueAt(draft, 'performance', 'rangeKm')}
                onChange={(value) => updateGroup('performance', 'rangeKm', numberOrNull(value))}
              />
              <Field
                label="Tiêu chuẩn thử nghiệm"
                value={valueAt(draft, 'performance', 'rangeTestCycle')}
                onChange={(value) => updateGroup('performance', 'rangeTestCycle', value)}
              />
              <Field
                label="Tốc độ tối đa (km/h)"
                type="number"
                value={valueAt(draft, 'performance', 'topSpeedKmh')}
                onChange={(value) =>
                  updateGroup('performance', 'topSpeedKmh', numberOrNull(value))
                }
              />
              <Field
                label="Công suất định mức động cơ (W)"
                type="number"
                value={valueAt(draft, 'performance', 'ratedMotorPowerW')}
                onChange={(value) =>
                  updateGroup('performance', 'ratedMotorPowerW', numberOrNull(value))
                }
              />
              <Field
                label="Công suất cực đại động cơ (W)"
                type="number"
                value={valueAt(draft, 'performance', 'peakMotorPowerW')}
                onChange={(value) =>
                  updateGroup('performance', 'peakMotorPowerW', numberOrNull(value))
                }
              />
            </div>
          </section>

          <section className="space-y-4">
            <div className="flex items-center justify-between border-b border-slate-800 pb-3">
              <h3 className="font-semibold">Nguồn dữ liệu kiểm chứng</h3>
              <Button
                variant="outline"
                className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"
                onClick={() =>
                  updateTop('sources', [
                    ...(draft.sources || []),
                    { url: '', publisher: draft.brandName || '', type: 'manufacturer' },
                  ])
                }
              >
                <Plus />
                Thêm nguồn
              </Button>
            </div>
            {(draft.sources || []).map((source, index) => {
              const sourcePath = `sources[${index}].url`;
              const sourceError = fieldErrors[sourcePath];
              return (
                <div key={index} className="space-y-1.5">
                  <div className="grid gap-3 sm:grid-cols-[1fr_10rem_auto]">
                    <Input
                      id={fieldDomId(sourcePath)}
                      aria-label={`Source URL ${index + 1}`}
                      aria-invalid={Boolean(sourceError)}
                      aria-describedby={sourceError ? `${fieldDomId(sourcePath)}-error` : undefined}
                      className={sourceError ? 'border-destructive focus-visible:ring-destructive' : ''}
                      placeholder="https://official-manufacturer.example/spec"
                      value={String(source.url || '')}
                      onChange={(event) => {
                        const sources = [...(draft.sources || [])];
                        sources[index] = { ...sources[index], url: event.target.value };
                        updateTop('sources', sources);
                        setFieldErrors((current) => {
                          const next = { ...current };
                          delete next[sourcePath];
                          return next;
                        });
                      }}
                    />
                    <Input
                      aria-label={`Publisher ${index + 1}`}
                      placeholder="Nhà phát hành"
                      value={String(source.publisher || '')}
                      onChange={(event) => {
                        const sources = [...(draft.sources || [])];
                        sources[index] = { ...sources[index], publisher: event.target.value };
                        updateTop('sources', sources);
                      }}
                    />
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() =>
                        updateTop(
                          'sources',
                          (draft.sources || []).filter((_, itemIndex) => itemIndex !== index)
                        )
                      }
                    >
                      <X />
                    </Button>
                  </div>
                  {sourceError && (
                    <p id={`${fieldDomId(sourcePath)}-error`} className="text-xs text-destructive">
                      {sourceError}
                    </p>
                  )}
                </div>
              );
            })}
            <input
              ref={twoDFileRef}
              className="hidden"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void upload(file, 'twoD');
                event.currentTarget.value = '';
              }}
            />
            <input
              ref={threeDFileRef}
              className="hidden"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void upload(file, 'threeD');
                event.currentTarget.value = '';
              }}
            />
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="border border-slate-800 bg-slate-900/40 p-3">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium">Ảnh chụp 2D</p>
                    <p className="text-xs text-slate-400">Ảnh mặc định hiển thị trên app.</p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"
                    disabled={!draft.catalogId || busy === 'media'}
                    onClick={() => twoDFileRef.current?.click()}
                  >
                    {busy === 'media' ? <Loader2 className="animate-spin" /> : <ImagePlus />}
                    Tải ảnh lên
                  </Button>
                </div>
                {twoDUrl && (
                  <img
                    className="mt-3 aspect-[16/9] w-full object-cover rounded-lg"
                    src={twoDUrl}
                    alt="2D vehicle"
                  />
                )}
              </div>
              <div className="border border-slate-800 bg-slate-900/40 p-3">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium">Bản dựng 3D Render</p>
                    <p className="text-xs text-slate-400">Hình ảnh 3D chia sẻ trên app.</p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"
                    disabled={!draft.catalogId || busy === 'media'}
                    onClick={() => threeDFileRef.current?.click()}
                  >
                    {busy === 'media' ? <Loader2 className="animate-spin" /> : <ImagePlus />}
                    Tải ảnh lên
                  </Button>
                </div>
                {threeDUrl && (
                  <img
                    className="mt-3 aspect-[16/9] w-full object-cover rounded-lg"
                    src={threeDUrl}
                    alt="3D vehicle render"
                  />
                )}
              </div>
            </div>
          </section>

          <section ref={showroomRef} className="scroll-mt-40 space-y-4">
            <h3 className="border-b border-slate-800 pb-3 font-semibold">Phòng trưng bày xe</h3>
            {draft.catalogId ? (
              <ShowroomEditor
                catalogId={draft.catalogId}
                media={draft.media}
                ensureDraft={ensureDraft}
                onMedia={(media) => setDraft((current) => ({ ...current, media }))}
              />
            ) : (
              <p className="text-sm text-slate-400">
                Lưu bản nháp trước để thêm ảnh theo màu và góc xoay.
              </p>
            )}
          </section>
        </div>

        <footer className="sticky bottom-0 flex flex-wrap justify-end gap-3 border-t border-slate-800 bg-slate-950/95 px-5 py-4 backdrop-blur sm:px-8">
          <Button
            variant="outline"
            className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"
            onClick={onClose}
          >
            Hủy
          </Button>
          <Button variant="secondary" disabled={Boolean(busy)} onClick={() => void save()}>
            {busy === 'save' && <Loader2 className="animate-spin" />}
            Lưu bản nháp
          </Button>
          <Button
            disabled={Boolean(busy) || !draft.catalogId}
            onClick={() => void publish()}
            className="bg-emerald-500 hover:bg-emerald-600 text-white font-semibold"
          >
            {busy === 'publish' && <Loader2 className="animate-spin" />}
            Xem xét & Xuất bản
          </Button>
        </footer>
      </div>
    </ModalSurface>
  );
}

function ResearchWizard({
  onClose,
  onCandidate,
}: {
  onClose: () => void;
  onCandidate: (entry: CatalogEntry) => void;
}) {
  const [mode, setMode] = useState<'url' | 'search'>('url');
  const [brand, setBrand] = useState('VinFast');
  const [brandId, setBrandId] = useState('vinfast');
  const [domain, setDomain] = useState('vinfastauto.com');
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [job, setJob] = useState<Dictionary | null>(null);

  const poll = useCallback(
    async (jobId: string) => {
      for (let count = 0; count < 40; count += 1) {
        const response = await catalogResearchGet(jobId);
        const current = response.data as Dictionary;
        setJob(current);
        if (['needs_review', 'failed'].includes(String(current.status))) {
          const result = current.result as Dictionary | undefined;
          if (current.status === 'needs_review' && result?.candidate) {
            onCandidate({
              ...emptyDraft(),
              ...(result.candidate as CatalogEntry),
              brandId,
              brandName: brand,
              sources: (result.sources as Dictionary[]) || [],
              conflicts: (result.conflicts as Dictionary[]) || [],
            });
          }
          return;
        }
        await new Promise((resolve) => setTimeout(resolve, 1500));
      }
    },
    [brand, brandId, onCandidate]
  );

  const run = async () => {
    setBusy(true);
    try {
      await catalogManufacturerSave(brandId, { name: brand, officialDomains: [domain] });
      const response = await catalogResearchCreate({
        mode,
        brandId,
        brandName: brand,
        market: 'VN',
        urls: mode === 'url' ? [input] : undefined,
        query: mode === 'search' ? input : undefined,
      });
      const created = response.data as Dictionary;
      setJob(created);
      await poll(String(created.jobId));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Research failed');
    } finally {
      setBusy(false);
    }
  };

  return (
    <ModalSurface label="Tra cứu mẫu xe" onClose={onClose} busy={busy}>
      <div className="rounded-xl bg-card p-6 sm:p-8">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[.18em] text-primary">
              AI Tra cứu nguồn chính thức
            </p>
            <h2 className="mt-2 text-2xl font-semibold">Tạo bản nháp từ thông số hãng</h2>
            <p className="mt-2 max-w-lg text-sm text-muted-foreground">
              Dữ liệu trích xuất từ tài liệu công bố và trang web chính thức của nhà sản xuất.
            </p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose}>
            <X />
          </Button>
        </div>
        <div className="mt-7 grid gap-4 sm:grid-cols-2">
          <Field label="Hãng xe" value={brand} onChange={setBrand} />
          <Field label="Mã định danh hãng" value={brandId} onChange={setBrandId} />
          <Field label="Tên miền chính thức" value={domain} onChange={setDomain} />
          <label className="space-y-1.5 text-sm">
            <span className="font-medium">Chế độ tra cứu</span>
            <select
              className="min-h-10 w-full rounded-md border bg-background px-3"
              value={mode}
              onChange={(event) => setMode(event.target.value as 'url' | 'search')}
            >
              <option value="url">URL tài liệu / PDF chính thức</option>
              <option value="search">Gemini Tìm kiếm đối chiếu</option>
            </select>
          </label>
          <div className="sm:col-span-2">
            <Field
              label={mode === 'url' ? 'Đường dẫn HTTPS chính thức' : 'Dòng xe, phiên bản, năm'}
              value={input}
              onChange={setInput}
            />
          </div>
        </div>
        {job && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            className="mt-5 flex items-center gap-3 border-l-2 border-primary bg-primary/5 p-4"
          >
            <Loader2
              className={`h-4 w-4 ${['pending', 'running'].includes(String(job.status)) ? 'animate-spin' : ''}`}
            />
            <div>
              <p className="text-sm font-medium">{String(job.status).replace('_', ' ')}</p>
              {Boolean(job.error) && <p className="text-xs text-destructive">{String(job.error)}</p>}
            </div>
          </motion.div>
        )}
        <div className="mt-7 flex justify-end gap-3">
          <Button variant="outline" onClick={onClose}>
            Hủy
          </Button>
          <Button disabled={busy || !input || !brandId || !domain} onClick={() => void run()}>
            {busy ? <Loader2 className="animate-spin" /> : <Sparkles />}
            Bắt đầu tra cứu
          </Button>
        </div>
      </div>
    </ModalSurface>
  );
}

function ShowroomSummary({ entry, onManage }: { entry: CatalogEntry; onManage: () => void }) {
  const showroom = readShowroom(entry.media);
  const [colorId, setColorId] = useState(showroom?.defaultColorId || '');
  const color = showroom?.colors.find((item) => item.id === colorId) || showroom?.colors[0];
  const angles = showroom?.colors.reduce((sum, item) => sum + item.angles.length, 0) || 0;

  return (
    <div className="mt-8 border-t border-slate-800 pt-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="flex items-center gap-2 font-semibold">
            <ImagePlus className="h-4 w-4 text-emerald-400" />
            Phòng trưng bày xe
          </h3>
          <p className="mt-1 text-sm text-slate-400">
            {showroom
              ? `${showroom.colors.length} màu · ${angles} ảnh · ${
                  color && color.angles.length >= 12
                    ? 'xoay 360° trên app'
                    : 'hiển thị 2.5D (cần 12 góc để xoay 360°)'
                }`
              : 'Chưa có ảnh chính chủ — app đang dùng hình minh họa 2D.'}
          </p>
        </div>
        <Button onClick={onManage}>
          <ImagePlus />
          {showroom ? 'Quản lý ảnh & 360°' : 'Thêm ảnh xe & 360°'}
        </Button>
      </div>
      {showroom && color && (
        <div className="mt-4 space-y-3">
          <SpinPreview key={color.id} angles={color.angles} />
          {showroom.colors.length > 1 && (
            <div className="flex flex-wrap gap-2">
              {showroom.colors.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => setColorId(item.id)}
                  className={`flex min-h-9 items-center gap-2 rounded-full border px-3 text-sm ${
                    item.id === color.id
                      ? 'border-emerald-400 text-white'
                      : 'border-slate-700 text-slate-300'
                  }`}
                >
                  <span
                    className="h-4 w-4 rounded-full border border-white/20"
                    style={{ background: item.swatchHex }}
                  />
                  {item.name}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function VehicleCatalog() {
  const [entries, setEntries] = useState<CatalogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [type] = useState('all');
  const [brand, setBrand] = useState('all');
  const [selected, setSelected] = useState<CatalogEntry | null>(null);
  const [editor, setEditor] = useState<CatalogEntry | null>(null);
  const [editorFocus, setEditorFocus] = useState<'showroom' | undefined>();
  const [research, setResearch] = useState(false);
  const [, setHistory] = useState<Dictionary[]>([]);
  const [viewMode, setViewMode] = useState<'grid' | 'table'>('grid');

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError('');
    try {
      const response = await catalogList();
      setEntries(response.data || []);
      setLoaded(true);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Catalog could not be loaded';
      setLoadError(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const brands = useMemo(
    () => [...new Set(entries.map((entry) => entry.brandName).filter(Boolean) as string[])].sort(),
    [entries]
  );

  const filtered = useMemo(
    () =>
      entries.filter((entry) => {
        const haystack = `${displayName(entry)} ${entry.brandName || ''} ${entry.model || ''} ${entry.variant || ''}`.toLowerCase();
        const matchesStatus =
          status === 'all'
            ? true
            : status === 'archived'
              ? entry.selectable === false
              : entry.status === status;
        return (
          haystack.includes(query.toLowerCase()) &&
          matchesStatus &&
          (type === 'all' || entry.vehicleType === type) &&
          (brand === 'all' || entry.brandName === brand)
        );
      }),
    [entries, query, status, type, brand]
  );

  const open = async (entry: CatalogEntry) => {
    setSelected(entry);
    try {
      const response = await catalogGet(entry.catalogId);
      setHistory(response.data?.history || []);
    } catch {
      setHistory([]);
    }
  };

  const counts = useMemo(
    () => ({
      all: entries.length,
      published: entries.filter((item) => item.status === 'published' && item.selectable !== false)
        .length,
      draft: entries.filter((item) => item.status === 'draft').length,
      archived: entries.filter((item) => item.selectable === false).length,
    }),
    [entries]
  );

  const toggleArchive = async (entry: CatalogEntry) => {
    try {
      if (entry.selectable === false) {
        await catalogRestore(entry.catalogId);
      } else {
        await catalogArchive(entry.catalogId);
      }
      toast.success(entry.selectable === false ? 'Đã khôi phục cấu hình' : 'Đã lưu trữ cấu hình');
      setSelected(null);
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Status change failed');
    }
  };

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-[22px] font-semibold tracking-tight text-foreground">
          Danh mục xe
        </h1>
        <div className="flex items-center gap-2">
          {counts.draft > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                const draftEntry = entries.find((e) => e.status === 'draft');
                if (draftEntry) setEditor(draftEntry);
              }}
              className="h-9 gap-2 text-xs border-indigo-500/30 text-indigo-400 hover:bg-indigo-500/10"
            >
              <Rocket className="h-3.5 w-3.5" />
              Xuất bản {counts.draft} thay đổi
            </Button>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setResearch(true)}
            className="h-9 gap-2 text-xs"
          >
            <FileSearch className="h-3.5 w-3.5" />
            Tra cứu
          </Button>
          <Button
            size="sm"
            onClick={() => setEditor(emptyDraft())}
            className="h-9 gap-2 text-xs bg-indigo-600 hover:bg-indigo-700 text-white font-medium"
          >
            <Plus className="h-4 w-4" />
            Thêm xe
          </Button>
        </div>
      </div>

      {/* Filter Row & View Mode Toggle (Matches Image 1) */}
      <div className="flex flex-wrap items-center justify-between gap-3 p-2 rounded-xl bg-surface border border-border/60">
        <div className="flex flex-wrap items-center gap-2 flex-1 min-w-[280px]">
          {/* Search Input */}
          <div className="relative flex-1 min-w-[220px] max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Tìm hãng xe, dòng xe, phiên bản..."
              className="h-9 pl-9 pr-3 text-xs bg-canvas border-border/60"
            />
          </div>

          {/* Status Tabs */}
          <div className="flex items-center gap-1 rounded-lg border border-border/60 bg-canvas p-1">
            {[
              { id: 'all', label: 'Tất cả', count: counts.all },
              { id: 'published', label: 'Đã xuất bản', count: counts.published },
              { id: 'draft', label: 'Bản nháp', count: counts.draft },
              { id: 'archived', label: 'Đang ẩn', count: counts.archived },
            ].map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setStatus(tab.id)}
                className={`flex items-center gap-1.5 px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                  status === tab.id
                    ? 'bg-elevated text-foreground font-semibold shadow-xs'
                    : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                <span>{tab.label}</span>
                <span className="text-[11px] font-mono tabular-nums opacity-75">{tab.count}</span>
              </button>
            ))}
          </div>

          {/* Brand Filter */}
          {brands.length > 1 && (
            <select
              aria-label="Hãng xe"
              className="h-9 rounded-lg border border-border/60 bg-canvas px-3 text-xs text-foreground focus:outline-none"
              value={brand}
              onChange={(e) => setBrand(e.target.value)}
            >
              <option value="all">Tất cả hãng</option>
              {brands.map((b) => (
                <option key={b} value={b}>
                  {b}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* Right: View Mode Toggle [ Lưới ] / [ Bảng ] */}
        <div className="flex items-center gap-1 rounded-lg border border-border/60 bg-canvas p-1">
          <button
            type="button"
            onClick={() => setViewMode('grid')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
              viewMode === 'grid'
                ? 'bg-elevated text-foreground font-semibold shadow-xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <LayoutGrid className="h-3.5 w-3.5" />
            <span>Lưới</span>
          </button>
          <button
            type="button"
            onClick={() => setViewMode('table')}
            className={`flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors ${
              viewMode === 'table'
                ? 'bg-elevated text-foreground font-semibold shadow-xs'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <List className="h-3.5 w-3.5" />
            <span>Bảng</span>
          </button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => void load()}
            className="h-7 w-7 text-muted-foreground hover:text-foreground ml-1"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
      </div>

      {loadError && !loading && (
        <div
          role="alert"
          className="flex flex-wrap items-center justify-between gap-4 border border-destructive/25 bg-destructive/5 px-4 py-3 rounded-xl text-xs"
        >
          <div>
            <p className="font-semibold text-foreground">Chưa thể tải danh mục xe</p>
            <p className="text-muted-foreground">{loadError}</p>
          </div>
          <Button variant="outline" size="sm" onClick={() => void load()}>
            Tải lại
          </Button>
        </div>
      )}

      {/* Main Content: GRID VIEW (Matches Image 1) */}
      {viewMode === 'grid' ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map((entry) => {
            const imgUrl =
              mediaViewUrl(entry, 'twoD') ||
              mediaViewUrl(entry, 'threeD') ||
              (entry.media?.thumbnailUrl as string) ||
              (entry.media?.heroUrl as string);
            const showroom = readShowroom(entry.media);
            const cap = formatCapacity(valueAt(entry, 'appDefaults', 'calculationCapacityWh'));
            const range = valueAt(entry, 'performance', 'rangeKm')
              ? `${valueAt(entry, 'performance', 'rangeKm')} km`
              : '—';
            const power = formatPower(
              valueAt(entry, 'performance', 'peakMotorPowerW') ||
                valueAt(entry, 'performance', 'ratedMotorPowerW')
            );

            return (
              <div
                key={entry.catalogId}
                className="group rounded-2xl border border-border/60 bg-surface/50 overflow-hidden flex flex-col justify-between transition-all duration-200 hover:border-border-strong hover:shadow-lg"
              >
                {/* Top Studio Vehicle Image Canvas */}
                <div className="relative aspect-[16/9] w-full bg-gradient-to-b from-[#131720] to-[#0A0D13] p-4 flex items-center justify-center overflow-hidden">
                  {imgUrl ? (
                    <img
                      src={imgUrl}
                      alt={displayName(entry)}
                      className="max-h-full max-w-full object-contain filter drop-shadow-[0_15px_15px_rgba(0,0,0,0.6)] transition-transform duration-300 group-hover:scale-105"
                    />
                  ) : (
                    /* Elegant SVG Silhouette Fallback matching Image 1 vehicle shape */
                    <div className="w-full h-full flex flex-col items-center justify-center relative">
                      <svg
                        viewBox="0 0 320 120"
                        className="w-4/5 h-auto text-emerald-500/80 drop-shadow-[0_10px_10px_rgba(0,0,0,0.5)] transition-transform duration-300 group-hover:scale-105"
                        fill="currentColor"
                      >
                        <path d="M 30,85 C 45,85 55,75 75,75 C 95,75 120,40 160,35 C 200,30 240,40 265,55 C 285,65 295,75 300,85 C 295,95 285,95 280,95 C 280,82 265,72 250,72 C 235,72 220,82 220,95 L 105,95 C 105,82 90,72 75,72 C 60,72 45,82 45,95 L 30,95 Z" />
                        <circle cx="75" cy="95" r="14" fill="#171B24" stroke="#475569" strokeWidth="4" />
                        <circle cx="250" cy="95" r="14" fill="#171B24" stroke="#475569" strokeWidth="4" />
                        <path d="M 125,48 L 160,42 L 195,42 L 235,58 L 125,58 Z" fill="#0B0D12" opacity="0.6" />
                      </svg>
                    </div>
                  )}
                </div>

                {/* Card Body */}
                <div className="p-4 space-y-3 flex-1 flex flex-col justify-between">
                  <div className="space-y-1">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-bold text-base text-foreground leading-tight">
                        {displayName(entry)}
                      </h3>
                      <StatusBadge entry={entry} />
                    </div>
                    <p className="text-xs text-muted-foreground truncate">
                      {entry.brandName || 'VinFast'} · {entry.variant || 'Phiên bản EV'} ·{' '}
                      {entry.vehicleType || 'scooter'}
                    </p>
                  </div>

                  {/* Specs & Color Palette Row */}
                  <div className="pt-2 border-t border-border/40 flex items-center justify-between">
                    <span className="font-mono text-xs text-foreground/90 font-medium">
                      {cap} · {range} · {power}
                    </span>

                    {/* Color Swatch Dots */}
                    <div className="flex items-center -space-x-1">
                      {showroom && showroom.colors.length > 0 ? (
                        showroom.colors.slice(0, 4).map((c) => (
                          <span
                            key={c.id}
                            className="w-3.5 h-3.5 rounded-full border border-canvas shadow-xs"
                            style={{ backgroundColor: c.swatchHex }}
                            title={c.name}
                          />
                        ))
                      ) : (
                        <>
                          <span className="w-3.5 h-3.5 rounded-full bg-blue-500 border border-canvas shadow-xs" />
                          <span className="w-3.5 h-3.5 rounded-full bg-slate-100 border border-canvas shadow-xs" />
                          <span className="w-3.5 h-3.5 rounded-full bg-rose-500 border border-canvas shadow-xs" />
                        </>
                      )}
                    </div>
                  </div>

                  {/* Card Actions Bottom */}
                  <div className="pt-3 border-t border-border/40 flex items-center justify-between">
                    <button
                      type="button"
                      onClick={() => {
                        setEditorFocus('showroom');
                        setEditor(entry);
                      }}
                      className="flex items-center gap-1.5 text-xs font-medium text-indigo-400 hover:text-indigo-300 transition-colors"
                    >
                      <Palette className="h-3.5 w-3.5" />
                      <span>Mở Studio & Thông số</span>
                    </button>

                    <div className="flex items-center gap-1">
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          setEditorFocus(undefined);
                          setEditor(entry);
                        }}
                        className="h-7 px-2 text-xs text-muted-foreground hover:text-foreground"
                      >
                        Sửa
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => void open(entry)}
                        className="h-7 w-7 p-0 text-muted-foreground hover:text-foreground"
                      >
                        <ChevronRight className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}

          {loaded && !loadError && !loading && filtered.length === 0 && (
            <div className="col-span-full py-16 text-center rounded-2xl border border-dashed border-border/60 bg-surface/30">
              <Globe2 className="mx-auto mb-3 h-8 w-8 text-muted-foreground/60" />
              <p className="font-semibold text-foreground text-sm">Không có cấu hình phù hợp</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Tạo xe mới hoặc thay đổi bộ lọc tìm kiếm.
              </p>
            </div>
          )}
        </div>
      ) : (
        /* TABLE VIEW */
        <div className="rounded-xl border border-border/60 bg-surface/50 overflow-hidden shadow-xs">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[940px] text-xs">
              <thead>
                <tr className="border-b border-border/60 bg-canvas/40 text-left text-muted-foreground">
                  <th className="py-2.5 px-3 font-medium">Cấu hình xe</th>
                  <th className="py-2.5 px-3 font-medium">Loại / Thị trường</th>
                  <th className="py-2.5 px-3 font-medium">Dung lượng Pin</th>
                  <th className="py-2.5 px-3 font-medium">Quãng đường</th>
                  <th className="py-2.5 px-3 font-medium">Công suất</th>
                  <th className="py-2.5 px-3 font-medium">Trạng thái</th>
                  <th className="py-2.5 px-3 text-right font-medium">Thao tác</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/40">
                {filtered.map((entry) => (
                  <tr
                    key={entry.catalogId}
                    className="hover:bg-muted/30 transition-colors cursor-pointer"
                    onClick={() => void open(entry)}
                  >
                    <td className="py-2.5 px-3">
                      <div className="flex items-center gap-3">
                        {entry.media?.thumbnailUrl ? (
                          <img
                            className="h-9 w-12 rounded object-cover"
                            src={String(entry.media.thumbnailUrl)}
                            alt=""
                          />
                        ) : (
                          <div className="grid h-9 w-12 place-items-center rounded bg-canvas border border-border/60">
                            <Globe2 className="h-4 w-4 text-muted-foreground" />
                          </div>
                        )}
                        <div>
                          <p className="font-semibold text-foreground">{displayName(entry)}</p>
                          <p className="text-[11px] text-muted-foreground">
                            {entry.brandName} · {entry.variant} · {entry.modelYear}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="py-2.5 px-3 capitalize text-muted-foreground">
                      {entry.vehicleType} · {entry.market}
                    </td>
                    <td className="py-2.5 px-3 font-mono text-foreground/90">
                      {formatCapacity(valueAt(entry, 'appDefaults', 'calculationCapacityWh'))}
                    </td>
                    <td className="py-2.5 px-3 font-mono text-foreground/90">
                      {valueAt(entry, 'performance', 'rangeKm')
                        ? `${valueAt(entry, 'performance', 'rangeKm')} km`
                        : '—'}
                    </td>
                    <td className="py-2.5 px-3 font-mono text-foreground/90">
                      {formatPower(
                        valueAt(entry, 'performance', 'peakMotorPowerW') ||
                          valueAt(entry, 'performance', 'ratedMotorPowerW')
                      )}
                    </td>
                    <td className="py-2.5 px-3">
                      <StatusBadge entry={entry} />
                    </td>
                    <td className="py-2.5 px-3 text-right">
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={(e) => {
                          e.stopPropagation();
                          void open(entry);
                        }}
                        className="h-7 text-xs text-muted-foreground hover:text-foreground"
                      >
                        Chi tiết &rarr;
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Detail Drawer (Preserves all safety assertions) */}
      {selected && (
        <ModalSurface drawer label="Chi tiết cấu hình xe" onClose={() => setSelected(null)}>
          <div className="min-h-full bg-slate-950 p-6 text-slate-100 sm:p-8">
            <div className="flex items-start justify-between border-b border-slate-800 pb-5">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[.18em] text-emerald-400">
                  {selected.brandName} · {selected.market}
                </p>
                <h2 className="mt-2 text-2xl font-semibold">{displayName(selected)}</h2>
                <div className="mt-3">
                  <StatusBadge entry={selected} />
                </div>
              </div>
              <Button
                variant="ghost"
                size="icon"
                className="text-slate-300 hover:bg-slate-800 hover:text-white"
                onClick={() => setSelected(null)}
              >
                <X />
              </Button>
            </div>

            {Boolean(selected.media?.heroUrl) && (
              <motion.img
                layoutId={`vehicle-${selected.catalogId}`}
                className="mt-6 aspect-[16/7] w-full rounded-2xl object-cover"
                src={String(selected.media?.heroUrl)}
                alt={displayName(selected)}
              />
            )}

            <div className="mt-6 grid gap-3 sm:grid-cols-2">
              {(['twoD', 'threeD'] as const).map((kind) => {
                const url = mediaViewUrl(selected, kind);
                return (
                  url && (
                    <figure
                      key={kind}
                      className="overflow-hidden border border-slate-800 bg-slate-900/40 rounded-lg"
                    >
                      <img
                        className="aspect-[16/9] w-full object-cover"
                        src={url}
                        alt={`${displayName(selected)} ${kind === 'twoD' ? '2D photo' : '3D render'}`}
                      />
                      <figcaption className="px-3 py-2 text-xs text-slate-400">
                        {kind === 'twoD' ? 'Ảnh 2D ứng dụng' : 'Bản dựng 3D chia sẻ'}
                      </figcaption>
                    </figure>
                  )
                );
              })}
            </div>

            <div className="mt-7 grid grid-cols-2 gap-5">
              <Metric
                label="Pin tính toán"
                value={formatCapacity(valueAt(selected, 'appDefaults', 'calculationCapacityWh'))}
              />
              <Metric
                label="Công suất sạc an toàn"
                value={formatPower(valueAt(selected, 'appDefaults', 'maxSafeChargePowerW'))}
              />
              <Metric
                label="Quãng đường công bố"
                value={
                  valueAt(selected, 'performance', 'rangeKm')
                    ? `${valueAt(selected, 'performance', 'rangeKm')} km`
                    : '—'
                }
              />
              <Metric
                label="Tốc độ tối đa"
                value={
                  valueAt(selected, 'performance', 'topSpeedKmh')
                    ? `${valueAt(selected, 'performance', 'topSpeedKmh')} km/h`
                    : '—'
                }
              />
            </div>

            <ShowroomSummary key={selected.catalogId}
              entry={selected}
              onManage={() => {
                setEditorFocus('showroom');
                setEditor(selected);
                setSelected(null);
              }}
            />

            <div className="mt-8 flex flex-wrap gap-3">
              <Button
                onClick={() => {
                  setEditorFocus(undefined);
                  setEditor(selected);
                  setSelected(null);
                }}
              >
                Sửa thông số & ảnh
              </Button>
              {selected.status === 'published' && (
                <Button
                  variant="outline"
                  className="border-slate-700 bg-transparent text-slate-100 hover:bg-slate-900"
                  onClick={() => void toggleArchive(selected)}
                >
                  {selected.selectable === false ? <Check /> : <Archive />}
                  {selected.selectable === false ? 'Khôi phục' : 'Ẩn khỏi catalog'}
                </Button>
              )}
            </div>
          </div>
        </ModalSurface>
      )}

      {editor && (
        <Editor
          initial={editor}
          focus={editorFocus}
          onClose={() => {
            setEditor(null);
            setEditorFocus(undefined);
          }}
          onSaved={load}
        />
      )}

      {research && (
        <ResearchWizard
          onClose={() => setResearch(false)}
          onCandidate={(candidate) => {
            setResearch(false);
            setEditor(candidate);
          }}
        />
      )}
    </div>
  );
}
