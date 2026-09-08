import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  X, Upload, RefreshCw, Layers, PlayCircle, BarChart3,
  Sparkles, Loader2,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ModalSurface } from '@/components/ui/modal-surface';
import { Badge } from '@/components/ui/badge';
// @ts-ignore
import { aiListModels, aiDeleteModel, aiDeactivateModel, aiDeployModel, aiTestVersion } from '@/api';
import { ModelTypeMeta, ModelVersion, ACCENT_CLASSES } from '../types';
import { getActiveVersion } from '../modelAvailability';
import { getModelIcon } from '../modelIcons';
import ModelVersionsList from './ModelVersionsList';
import UploadDialog from '../UploadDialog';

type Tab = 'versions' | 'test' | 'metrics';

interface Props {
  meta: ModelTypeMeta;
  isOpen: boolean;
  onClose: () => void;
  onModelChanged: () => void;
}

export default function ModelManagerDrawer({
  meta,
  isOpen,
  onClose,
  onModelChanged,
}: Props) {
  const [tab, setTab] = useState<Tab>('versions');
  const [versions, setVersions] = useState<ModelVersion[]>([]);
  const requestGeneration = useRef(0);
  const [loading, setLoading] = useState(true);
  const [isBusy, setIsBusy] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err' | 'info'; text: string } | null>(null);
  const [selectedTestVersion, setSelectedTestVersion] = useState<string | null>(null);
  const [selectedVersionForMetrics, setSelectedVersionForMetrics] = useState<string | null>(null);

  const activeVersion = getActiveVersion(meta);
  const Icon = getModelIcon(meta.icon);
  const c = ACCENT_CLASSES[meta.accent] || ACCENT_CLASSES.slate;

  const reloadVersions = useCallback(async () => {
    const request = ++requestGeneration.current;
    setLoading(true);
    try {
      const res = await aiListModels(meta.key);
      if (request !== requestGeneration.current) return;
      setVersions((res?.data?.versions ?? []) as ModelVersion[]);
    } catch (e: any) {
      if (request !== requestGeneration.current) return;
      setMessage({ type: 'err', text: e?.message || 'Không tải được danh sách version' });
    } finally {
      if (request === requestGeneration.current) setLoading(false);
    }
  }, [meta.key]);

  useEffect(() => {
    if (isOpen) {
      reloadVersions();
      setMessage(null);
    }
    return () => { requestGeneration.current++; };
  }, [isOpen, reloadVersions]);

  const sortedVersions = useMemo(
    () => [...versions].sort((a, b) => (b.uploadedAt || '').localeCompare(a.uploadedAt || '')),
    [versions]
  );

  useEffect(() => {
    if (sortedVersions.length > 0) {
      const defaultVer = sortedVersions.some(v => v.version === activeVersion) ? activeVersion! : sortedVersions[0].version;
      setSelectedTestVersion((prev) => (prev && sortedVersions.some((v) => v.version === prev) ? prev : defaultVer));
      setSelectedVersionForMetrics((prev) => (prev && sortedVersions.some((v) => v.version === prev) ? prev : defaultVer));
    } else {
      setSelectedTestVersion(null);
      setSelectedVersionForMetrics(null);
    }
  }, [activeVersion, sortedVersions]);

  if (!isOpen) return null;

  const onDelete = async (version: string) => {
    const isActive = version === activeVersion;
    const msg = isActive
      ? `Version "${version}" đang là phiên bản chính thức (ACTIVE).\nNếu xóa, chức năng dự đoán sẽ bị tạm ngắt cho đến khi chọn version mới.\n\nTiếp tục xóa?`
      : `Xóa vĩnh viễn version "${version}"?`;

    if (!confirm(msg)) return;

    setIsBusy(true);
    try {
      await aiDeleteModel(meta.key, version);
      setMessage({ type: 'ok', text: `Đã xóa version ${version}` });
      await reloadVersions();
      onModelChanged();
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Xóa thất bại' });
    } finally {
      setIsBusy(false);
    }
  };

  const onDeactivate = async () => {
    if (!confirm(`Deactivate model "${meta.label}"?\nModel sẽ không còn được nạp trong bộ nhớ runtime.`)) return;

    setIsBusy(true);
    try {
      await aiDeactivateModel(meta.key);
      setMessage({ type: 'ok', text: 'Đã deactivate model' });
      await reloadVersions();
      onModelChanged();
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Deactivate thất bại' });
    } finally {
      setIsBusy(false);
    }
  };

  const onDeploy = async (version: string) => {
    if (!confirm(`Triển khai version ${version} làm phiên bản chính thức (ACTIVE)?`)) return;

    setIsBusy(true);
    try {
      setMessage({ type: 'info', text: `Đang triển khai version ${version}...` });
      const res = await aiDeployModel(meta.key, version);
      setMessage({ type: 'ok', text: `Đã triển khai thành công ${version}: ${res?.data?.status || 'Active'}` });
      await reloadVersions();
      onModelChanged();
    } catch (e: any) {
      setMessage({ type: 'err', text: `Deploy thất bại: ${e?.message}` });
    } finally {
      setIsBusy(false);
    }
  };

  const onTestVersion = (version: string) => {
    setSelectedTestVersion(version);
    setTab('test');
    setMessage({ type: 'info', text: `Đang kiểm thử nhanh version ${version}` });
  };

  return (
    <ModalSurface label={`Quản lý model ${meta.label}`} drawer busy={isBusy} onClose={onClose}>
      <div className="relative h-full w-full max-w-2xl border-l border-white/10 bg-slate-950 p-6 text-white shadow-2xl overflow-y-auto flex flex-col justify-between">
        <div>
          {/* Header */}
          <div className="flex flex-wrap items-start justify-between gap-3 border-b border-white/10 pb-5">
            <div className="flex items-center gap-3">
              <div className={`h-11 w-11 rounded-xl flex items-center justify-center ${c.bg} ${c.text} border ${c.border}`}>
                <Icon className="h-6 w-6" />
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <h3 className="text-xl font-bold text-white">{meta.label}</h3>
                  {activeVersion ? (
                    <Badge variant="default" className="bg-emerald-600 font-mono text-[10px]">
                      ACTIVE · {activeVersion}
                    </Badge>
                  ) : (
                    <Badge variant="outline" className="text-[10px] text-amber-400 border-amber-500/30">
                      Chưa active
                    </Badge>
                  )}
                </div>
                <p className="text-xs text-slate-400 mt-0.5">Quản lý phiên bản & triển khai mô hình</p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Button
                size="sm"
                onClick={() => setUploadOpen(true)}
                disabled={isBusy}
                className="bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-semibold text-xs h-8"
              >
                <Upload className="w-3.5 h-3.5 mr-1.5" />
                Upload model
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={onClose}
                aria-label="Đóng quản lý model"
                disabled={isBusy}
                className="h-8 w-8 p-0 text-slate-400 hover:text-white hover:bg-white/10 rounded-lg"
              >
                <X className="h-5 w-5" />
              </Button>
            </div>
          </div>

          {/* Alert Message */}
          {message && (
            <div
              className={`mt-4 text-xs rounded-lg border p-3 flex items-center justify-between ${
                message.type === 'ok'
                  ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300'
                  : message.type === 'info'
                  ? 'border-blue-500/30 bg-blue-500/10 text-blue-300'
                  : 'border-red-500/30 bg-red-500/10 text-red-300'
              }`}
            >
              <span>{message.text}</span>
              <button onClick={() => setMessage(null)} className="text-xs opacity-70 hover:opacity-100">✕</button>
            </div>
          )}

          {/* Navigation Tabs */}
          <div className="flex gap-1 border-b border-white/10 mt-5">
            <button
              onClick={() => setTab('versions')}
              className={`flex items-center gap-2 px-4 py-2 text-xs font-semibold border-b-2 transition-colors ${
                tab === 'versions'
                  ? 'border-emerald-400 text-emerald-400'
                  : 'border-transparent text-slate-400 hover:text-white'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              Danh sách Versions ({versions.length})
            </button>
            <button
              onClick={() => setTab('test')}
              className={`flex items-center gap-2 px-4 py-2 text-xs font-semibold border-b-2 transition-colors ${
                tab === 'test'
                  ? 'border-emerald-400 text-emerald-400'
                  : 'border-transparent text-slate-400 hover:text-white'
              }`}
            >
              <PlayCircle className="w-3.5 h-3.5" />
              Test Version
            </button>
            <button
              onClick={() => setTab('metrics')}
              className={`flex items-center gap-2 px-4 py-2 text-xs font-semibold border-b-2 transition-colors ${
                tab === 'metrics'
                  ? 'border-emerald-400 text-emerald-400'
                  : 'border-transparent text-slate-400 hover:text-white'
              }`}
            >
              <BarChart3 className="w-3.5 h-3.5" />
              Đánh giá
            </button>
          </div>

          {/* Tab Content */}
          <div className="py-5">
            {tab === 'versions' && (
              <ModelVersionsList
                versions={sortedVersions}
                loading={loading}
                isBusy={isBusy}
                onTest={onTestVersion}
                onDeploy={onDeploy}
                onDelete={onDelete}
                onDeactivate={onDeactivate}
                onEvaluate={(v) => {
                  setSelectedVersionForMetrics(v);
                  setTab('metrics');
                }}
              />
            )}

            {tab === 'test' && (
              <DrawerTestTab
                meta={meta}
                versions={sortedVersions}
                activeVersion={activeVersion}
                selectedVersion={selectedTestVersion}
                onSelectedVersionChange={setSelectedTestVersion}
              />
            )}

            {tab === 'metrics' && (
              <DrawerMetricsTab
                versions={sortedVersions}
                selectedVersion={selectedVersionForMetrics}
                onSelectedVersionChange={setSelectedVersionForMetrics}
                activeVersion={activeVersion}
              />
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-white/10 pt-4 flex justify-between items-center text-xs text-slate-400">
          <span>{meta.phase} · {meta.useCase || meta.description}</span>
          <Button
            size="sm"
            variant="outline"
            onClick={reloadVersions}
            disabled={loading}
            className="h-8 border-white/10 hover:bg-white/10 text-white text-xs"
          >
            <RefreshCw className={`w-3.5 h-3.5 mr-1.5 ${loading ? 'animate-spin' : ''}`} />
            Làm mới
          </Button>
        </div>
      </div>

      {uploadOpen && (
        <UploadDialog
          typeKey={meta.key}
          typeLabel={meta.label}
          onClose={() => setUploadOpen(false)}
          onUploaded={() => {
            setMessage({ type: 'ok', text: 'Upload thành công! Hãy kiểm thử version trước khi Deploy.' });
            reloadVersions();
            onModelChanged();
          }}
        />
      )}
    </ModalSurface>
  );
}

// ── Test specific version tab inside drawer ─────────────────────────
function DrawerTestTab({
  meta,
  versions,
  activeVersion,
  selectedVersion,
  onSelectedVersionChange,
}: {
  meta: ModelTypeMeta;
  versions: ModelVersion[];
  activeVersion: string | null;
  selectedVersion: string | null;
  onSelectedVersionChange: (v: string) => void;
}) {
  const effectiveVersion = selectedVersion || activeVersion || versions[0]?.version;
  const sample = meta.sampleInput || {};
  const [values, setValues] = useState<Record<string, any>>(sample);
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setValues(meta.sampleInput || {});
    setResult(null);
    setError(null);
  }, [meta.sampleInput]);

  if (!effectiveVersion) {
    return (
      <div className="text-center py-10 text-slate-400 text-sm">
        Chưa có version nào để test. Hãy upload model trước.
      </div>
    );
  }

  const runTest = async () => {
    setRunning(true);
    setError(null);
    setResult(null);
    try {
      const res = await aiTestVersion(meta.key, effectiveVersion, values);
      setResult(res?.data ?? res);
    } catch (e: any) {
      setError(e?.message || 'Kiểm thử thất bại');
    } finally {
      setRunning(false);
    }
  };

  const fields = meta.visibleInputFields ?? meta.inputFields ?? [];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between bg-white/[0.03] p-3 rounded-lg border border-white/10">
        <span className="text-xs text-slate-300 font-medium">Version kiểm thử:</span>
        <select
          value={effectiveVersion}
          onChange={(e) => onSelectedVersionChange(e.target.value)}
          className="rounded-md border border-white/10 bg-slate-900 px-3 py-1.5 text-xs text-white"
        >
          {versions.map((v) => (
            <option key={v.version} value={v.version}>
              {v.version} {v.active ? '(Active)' : '(Chưa deploy)'}
            </option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-3">
        {fields.map((f) => {
          const schema = meta.inputSchema?.[f];
          const label = schema?.label || schema?.desc || f;
          return (
            <div key={f} className="space-y-1">
              <label className="text-xs text-slate-400">{label}</label>
              <input
                type={schema?.type === 'string' ? 'text' : 'number'}
                value={values[f] ?? ''}
                onChange={(e) => {
                  const val = schema?.type === 'string' ? e.target.value : parseFloat(e.target.value);
                  setValues({ ...values, [f]: isNaN(val as number) ? e.target.value : val });
                }}
                className="w-full rounded-md border border-white/10 bg-slate-900 px-3 py-1.5 text-xs text-white font-mono"
              />
            </div>
          );
        })}
      </div>

      <Button
        onClick={runTest}
        disabled={running}
        className="w-full bg-blue-600 hover:bg-blue-500 text-white font-medium text-xs h-9"
      >
        {running ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <PlayCircle className="w-4 h-4 mr-2" />}
        Chạy kiểm thử version {effectiveVersion}
      </Button>

      {error && (
        <div className="rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-xs text-red-300">
          {error}
        </div>
      )}

      {result && (
        <div className="rounded-lg border border-white/10 bg-slate-900/60 p-4 space-y-2">
          <div className="flex items-center justify-between text-xs text-slate-400">
            <span>Kết quả trả về:</span>
            <span className="font-mono text-emerald-400 font-bold text-sm">
              {result.formattedPrediction || (typeof result.prediction === 'number' ? result.prediction.toFixed(2) : String(result.prediction))}
            </span>
          </div>
          <pre className="text-[11px] font-mono text-slate-300 bg-black/30 p-2 rounded max-h-40 overflow-auto whitespace-pre-wrap">
            {JSON.stringify(result, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}

// ── Metrics tab inside drawer ───────────────────────────────────────
function DrawerMetricsTab({
  versions,
  selectedVersion,
  onSelectedVersionChange,
  activeVersion,
}: {
  versions: ModelVersion[];
  selectedVersion: string | null;
  onSelectedVersionChange: (v: string) => void;
  activeVersion: string | null;
}) {
  const inspectedVersion = selectedVersion || activeVersion || versions[0]?.version || '—';

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between bg-white/[0.03] p-3 rounded-lg border border-white/10">
        <span className="text-xs text-slate-300 font-medium">Version đánh giá:</span>
        <select
          value={inspectedVersion}
          onChange={(e) => onSelectedVersionChange(e.target.value)}
          className="rounded-md border border-white/10 bg-slate-900 px-3 py-1.5 text-xs text-white"
        >
          {versions.map((v) => (
            <option key={v.version} value={v.version}>
              {v.version} {v.active ? '(Active)' : ''}
            </option>
          ))}
        </select>
      </div>

      <div className="rounded-xl border border-white/10 bg-slate-900/50 p-4 space-y-3">
        <h4 className="text-sm font-semibold text-white flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-emerald-400" />
          Tổng quan phiên bản {inspectedVersion}
        </h4>
        <div className="grid grid-cols-2 gap-3 text-xs">
          <div className="rounded-lg bg-white/[0.02] p-2.5 border border-white/5">
            <span className="text-slate-400">Trạng thái:</span>
            <div className="font-semibold text-slate-200 mt-0.5">
              {inspectedVersion === activeVersion ? 'Đang hoạt động (ACTIVE)' : 'Lưu trữ / Sẵn sàng'}
            </div>
          </div>
          <div className="rounded-lg bg-white/[0.02] p-2.5 border border-white/5">
            <span className="text-slate-400">Kích thước:</span>
            <div className="font-semibold text-slate-200 mt-0.5">
              {versions.find((v) => v.version === inspectedVersion)?.sizeBytes
                ? `${(versions.find((v) => v.version === inspectedVersion)!.sizeBytes! / 1024).toFixed(1)} KB`
                : '—'}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
