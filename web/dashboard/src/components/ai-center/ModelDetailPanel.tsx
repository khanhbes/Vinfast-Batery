import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  RefreshCw, Upload, Trash2, PlayCircle, CheckCircle2, AlertCircle,
  History, FlaskConical, BarChart3, Loader2, Copy, PackageX, PowerOff, TrendingUp,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
// @ts-ignore
import { aiListModels, aiDeleteModel, aiQuickPredict, aiLoadActiveModel, aiDeactivateModel, aiTestVersion, aiDeployModel } from '@/api';
import { ACCENT_CLASSES, ModelTypeMeta, ModelVersion, formatBytes, formatDate, PredictionResponse } from './types';
import UploadDialog from './UploadDialog';
import PredictionResultChart from './PredictionResultChart';

type Tab = 'versions' | 'test' | 'metrics';

interface Props {
  meta: ModelTypeMeta;
  onAfterChange: () => void;
}

export default function ModelDetailPanel({ meta, onAfterChange }: Props) {
  const c = ACCENT_CLASSES[meta.accent] || ACCENT_CLASSES.slate;
  const [tab, setTab] = useState<Tab>('test');
  const [versions, setVersions] = useState<ModelVersion[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'err' | 'info'; text: string } | null>(null);
  const [loadingModel, setLoadingModel] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [selectedTestVersion, setSelectedTestVersion] = useState<string | null>(null);
  const [selectedVersionForMetrics, setSelectedVersionForMetrics] = useState<string | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const res = await aiListModels(meta.key);
      setVersions((res?.data?.versions ?? []) as ModelVersion[]);
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Không tải được danh sách' });
    } finally {
      setLoading(false);
    }
  }, [meta.key]);

  const sorted = useMemo(
    () => [...versions].sort((a, b) => (b.uploadedAt || '').localeCompare(a.uploadedAt || '')),
    [versions]
  );
  const activeVersion = meta.runtimeStatus.activeVersion ?? null;
  const hasVersions = sorted.length > 0;

  // When switching model, default to Test tab + try to load the active model
  useEffect(() => {
    reload();
    setTab('test');
    setMessage(null);
    setLoadError(null);
    setSelectedTestVersion(null);
    setSelectedVersionForMetrics(null);

    // Only load from runtime when there is an active version.
    if (!activeVersion) {
      setLoadingModel(false);
      return;
    }

    setLoadingModel(true);
    aiLoadActiveModel(meta.key)
      .then(() => setLoadError(null))
      .catch((e: any) => setLoadError(e?.message || 'Không thể nạp model'))
      .finally(() => setLoadingModel(false));
  }, [activeVersion, meta.key, reload]);

  useEffect(() => {
    if (!sorted.length) {
      setSelectedTestVersion(null);
      setSelectedVersionForMetrics(null);
      return;
    }

    const defaultVersion = activeVersion || sorted[0]?.version || null;
    setSelectedTestVersion((prev) =>
      prev && sorted.some((v) => v.version === prev) ? prev : defaultVersion
    );
    setSelectedVersionForMetrics((prev) =>
      prev && sorted.some((v) => v.version === prev) ? prev : defaultVersion
    );
  }, [activeVersion, sorted]);

  const onDelete = async (v: string) => {
    const isActive = v === meta.runtimeStatus.activeVersion;
    const msg = isActive
      ? `Version "${v}" đang được active. Xóa sẽ deactivate model này.\n\nTiếp tục?`
      : `Xóa vĩnh viễn version "${v}"?`;
    if (!confirm(msg)) return;
    try {
      await aiDeleteModel(meta.key, v);
      setMessage({ type: 'ok', text: `Đã xóa ${v}${isActive ? ' và deactivate' : ''}` });
      await reload();
      onAfterChange();
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Xóa thất bại' });
    }
  };

  const onDeactivate = async () => {
    if (!confirm(`Deactivate model "${meta.label}"?\n\nModel sẽ không còn được nạp trong bộ nhớ.`)) return;
    try {
      await aiDeactivateModel(meta.key);
      setMessage({ type: 'ok', text: 'Đã deactivate model' });
      await reload();
      onAfterChange();
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Deactivate thất bại' });
    }
  };

  // ── PLAN1: Test version chưa deploy ────────────────────────────────
  const onTestVersion = (version: string) => {
    setSelectedTestVersion(version);
    setTab('test');
    setMessage({ type: 'info', text: `Đã chọn version ${version} để test nhanh` });
  };

  // ── PLAN1: Deploy version chính thức ───────────────────────────────
  const onDeploy = async (version: string) => {
    if (!confirm(`Triển khai model "${meta.label}" version ${version}?\n\nModel sẽ được active và sẵn sàng cho app.`)) return;
    try {
      setMessage({ type: 'ok', text: `Đang deploy ${version}...` });
      const res = await aiDeployModel(meta.key, version);
      setMessage({ type: 'ok', text: `Đã triển khai ${version}: ${res?.data?.status || 'OK'}` });
      await reload();
      onAfterChange();
    } catch (e: any) {
      setMessage({ type: 'err', text: `Deploy thất bại: ${e?.message}` });
    }
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4 border-b">
        <div>
          <CardTitle className="flex items-center gap-2">
            <span className={`inline-block w-2 h-2 rounded-full ${c.dot}`} />
            {meta.label}
            {meta.runtimeStatus.activeVersion && (
              <Badge variant="secondary" className="font-mono text-xs ml-2">
                {meta.runtimeStatus.activeVersion}
              </Badge>
            )}
            <Badge variant="outline" className="text-[10px] font-mono ml-1">{meta.phase}</Badge>
          </CardTitle>
          <CardDescription className="mt-1">{meta.description}</CardDescription>
        </div>
        <div className="flex gap-2">
          {meta.runtimeStatus.activeVersion && (
            <Button variant="outline" size="sm" onClick={onDeactivate} className="text-amber-600 hover:text-amber-700">
              <PowerOff className="w-4 h-4 mr-1" />
              Deactivate
            </Button>
          )}
          <Button variant="outline" size="sm" onClick={reload} disabled={loading}>
            <RefreshCw className={`w-4 h-4 mr-1 ${loading ? 'animate-spin' : ''}`} />
            Làm mới
          </Button>
          <Button size="sm" onClick={() => setUploadOpen(true)}>
            <Upload className="w-4 h-4 mr-1" />
            Upload model
          </Button>
        </div>
      </CardHeader>

      {/* Use case banner */}
      {(meta.useCase || meta.outputDescription) && (
        <div className={`px-5 py-3 border-b ${c.bg}`}>
          {meta.useCase && (
            <div className="text-sm">
              <span className={`font-semibold ${c.text}`}>Bài toán: </span>
              <span className="text-foreground/80">{meta.useCase}</span>
            </div>
          )}
          {meta.outputDescription && (
            <div className="text-xs text-muted-foreground mt-1">
              <span className="font-medium">Output: </span>{meta.outputDescription}
            </div>
          )}
        </div>
      )}

      {/* Tabs */}
      <div className="flex gap-1 px-4 border-b bg-muted/20">
        <TabButton active={tab === 'test'} onClick={() => setTab('test')} icon={<FlaskConical className="w-4 h-4" />} label="Test nhanh" />
        <TabButton active={tab === 'versions'} onClick={() => setTab('versions')} icon={<History className="w-4 h-4" />} label="Versions" count={versions.length} />
        <TabButton active={tab === 'metrics'} onClick={() => setTab('metrics')} icon={<BarChart3 className="w-4 h-4" />} label="Đánh giá" />
      </div>

      <CardContent className="p-4">
        {message && (
          <div
            className={`mb-3 text-sm rounded-md border p-2 ${
              message.type === 'ok'
                ? 'border-green-200 bg-green-50 text-green-700'
                : message.type === 'info'
                ? 'border-blue-200 bg-blue-50 text-blue-700'
                : 'border-red-200 bg-red-50 text-red-700'
            }`}
          >
            {message.text}
          </div>
        )}

        {tab === 'test' && (
          loadingModel ? (
            <div className="text-center py-10 text-muted-foreground">
              <Loader2 className="w-8 h-8 mx-auto mb-2 animate-spin opacity-40" />
              <div className="text-sm">Đang nạp model…</div>
            </div>
          ) : !hasVersions ? (
            <NoModelState
              typeKey={meta.key}
              label={meta.label}
              hasVersions={hasVersions}
              error={loadError}
              onUpload={() => setUploadOpen(true)}
            />
          ) : activeVersion && loadError ? (
            <NoModelState
              typeKey={meta.key}
              label={meta.label}
              hasVersions={hasVersions}
              error={loadError}
              onUpload={() => setUploadOpen(true)}
            />
          ) : (
            <TestTab
              typeKey={meta.key}
              versions={sorted}
              activeVersion={activeVersion}
              selectedVersion={selectedTestVersion}
              onSelectedVersionChange={setSelectedTestVersion}
              inputFields={meta.inputFields}
              visibleInputFields={meta.visibleInputFields}
              derivedFields={meta.derivedFields}
              displayUnit={meta.displayUnit}
              sampleInput={meta.sampleInput}
              inputSchema={meta.inputSchema}
              outputUnit={meta.outputUnit}
              outputMeaning={meta.outputMeaning}
              accent={meta.accent}
            />
          )
        )}
        {tab === 'versions' && (
          <VersionsTab
            versions={sorted}
            loading={loading}
            onDelete={onDelete}
            onTest={onTestVersion}
            onDeploy={onDeploy}
            onEvaluate={(v) => {
              setSelectedVersionForMetrics(v);
              setTab('metrics');
            }}
          />
        )}
        {tab === 'metrics' && <MetricsTabEnhanced meta={meta} versions={sorted} selectedVersion={selectedVersionForMetrics} onSelectedVersionChange={setSelectedVersionForMetrics} activeVersion={activeVersion} />}
      </CardContent>

      {uploadOpen && (
        <UploadDialog
          typeKey={meta.key}
          typeLabel={meta.label}
          onClose={() => setUploadOpen(false)}
          onUploaded={(switchToTest = false) => {
            setMessage({ type: 'ok', text: 'Upload thành công — Chọn version để Test và Deploy' });
            setLoadError(null);
            reload();
            onAfterChange();
            if (switchToTest) {
              setTab('test');
            }
          }}
        />
      )}
    </Card>
  );
}

// ── "No model" empty state ─────────────────────────────────────
function NoModelState({ typeKey, label, hasVersions, error, onUpload }: {
  typeKey: string; label: string; hasVersions: boolean; error: string | null;
  onUpload: () => void;
}) {
  return (
    <div className="text-center py-12 space-y-3">
      <PackageX className="w-12 h-12 mx-auto text-muted-foreground/30" />
      <div className="text-lg font-semibold text-foreground">Chưa có model này</div>
      <div className="text-sm text-muted-foreground max-w-md mx-auto">
        {error ? (
          <span className="text-red-600">{error}</span>
        ) : hasVersions ? (
          <>Model <span className="font-mono text-xs bg-muted rounded px-1">{typeKey}</span> đã có version nhưng chưa được triển khai. Vào tab <strong>Versions</strong> để Test → Đánh giá → Deploy.</>
        ) : (
          <>Model <span className="font-mono text-xs bg-muted rounded px-1">{label}</span> chưa được upload. Nhấn nút bên dưới để upload file model đã train.</>
        )}
      </div>
      <Button onClick={onUpload} className="mt-2">
        <Upload className="w-4 h-4 mr-2" />
        Upload model
      </Button>
    </div>
  );
}

// ── Tab button ─────────────────────────────────────────────────────
function TabButton({ active, onClick, icon, label, count }: {
  active: boolean; onClick: () => void; icon: React.ReactNode; label: string; count?: number;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-2 px-3 py-2.5 text-sm font-medium border-b-2 transition-colors ${
        active
          ? 'border-primary text-foreground'
          : 'border-transparent text-muted-foreground hover:text-foreground'
      }`}
    >
      {icon}
      {label}
      {typeof count === 'number' && count > 0 && (
        <span className="text-xs bg-muted rounded-full px-1.5 py-0.5">{count}</span>
      )}
    </button>
  );
}

// ── Versions tab ───────────────────────────────────────────────────
function VersionsTab({ versions, loading, onDelete, onTest, onDeploy, onEvaluate }: {
  versions: ModelVersion[]; loading: boolean;
  onDelete: (v: string) => void;
  onTest?: (v: string) => void;
  onDeploy?: (v: string) => void;
  onEvaluate?: (v: string) => void;
}) {
  if (loading) return <div className="text-sm text-muted-foreground py-6 text-center">Đang tải...</div>;
  if (versions.length === 0) {
    return (
      <div className="text-center py-10 text-muted-foreground">
        <Upload className="w-8 h-8 mx-auto mb-2 opacity-30" />
        <div className="text-sm">Chưa có version nào.</div>
        <div className="text-xs">Nhấn "Upload model" để thêm version đầu tiên.</div>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-xs uppercase text-muted-foreground border-b">
          <tr>
            <th className="text-left py-2">Version</th>
            <th className="text-left py-2">Uploaded</th>
            <th className="text-left py-2">Size</th>
            <th className="text-left py-2">Ghi chú</th>
            <th className="text-right py-2">Thao tác</th>
          </tr>
        </thead>
        <tbody>
          {versions.map((v) => (
            <tr key={v.version} className={`border-b last:border-0 ${v.active ? 'bg-green-50/50' : ''}`}>
              <td className="py-2 font-mono">
                {v.version}
                {v.active && <Badge variant="default" className="ml-2 bg-green-600">active</Badge>}
              </td>
              <td className="py-2 text-muted-foreground">{formatDate(v.uploadedAt)}</td>
              <td className="py-2 text-muted-foreground">{formatBytes(v.sizeBytes)}</td>
              <td className="py-2 text-muted-foreground truncate max-w-[240px]" title={v.note || ''}>
                {v.note || '—'}
              </td>
              <td className="py-2 text-right">
                <div className="inline-flex gap-1">
                  {/* PLAN1: Evaluate version - chuyển sang tab Đánh giá */}
                  {onEvaluate && (
                    <Button size="sm" variant="outline" onClick={() => onEvaluate(v.version)}>
                      <BarChart3 className="w-3.5 h-3.5 mr-1" /> Đánh giá
                    </Button>
                  )}
                  {/* PLAN1: Test version chưa deploy */}
                  {!v.active && onTest && (
                    <Button size="sm" variant="outline" onClick={() => onTest(v.version)}>
                      <PlayCircle className="w-3.5 h-3.5 mr-1" /> Test
                    </Button>
                  )}
                  {/* Deploy version chính thức */}
                  {!v.active && onDeploy && (
                    <Button size="sm" variant="default" onClick={() => onDeploy(v.version)} className="bg-blue-600 hover:bg-blue-700">
                      <CheckCircle2 className="w-3.5 h-3.5 mr-1" /> Deploy
                    </Button>
                  )}
                  {!v.active && (
                    <Button size="sm" variant="ghost" onClick={() => onDelete(v.version)}
                      className="text-red-600 hover:text-red-700">
                      <Trash2 className="w-3.5 h-3.5" />
                    </Button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Test tab ───────────────────────────────────────────────────────
function TestTab({ 
  typeKey, 
  versions,
  activeVersion,
  selectedVersion,
  onSelectedVersionChange,
  inputFields, 
  visibleInputFields,
  derivedFields: _derivedFields,
  displayUnit: _displayUnit,
  sampleInput, 
  inputSchema, 
  outputUnit, 
  outputMeaning, 
  accent 
}: {
  typeKey: string;
  versions: ModelVersion[];
  activeVersion: string | null;
  selectedVersion: string | null;
  onSelectedVersionChange: (version: string) => void;
  inputFields: string[]; 
  visibleInputFields?: string[];
  derivedFields?: Record<string, { from?: string[]; formula?: string; default?: number }>;
  displayUnit?: 'time' | 'percentage' | 'distance' | 'scalar';
  sampleInput?: Record<string, any>;
  inputSchema?: Record<string, any>;
  outputUnit?: string;
  outputMeaning?: string;
  accent: ModelTypeMeta['accent'];
}) {
  // Use visible fields if available, otherwise fall back to all input fields
  const displayFields = visibleInputFields && visibleInputFields.length > 0 
    ? visibleInputFields 
    : inputFields;
  
  // Use sampleInput from backend if available, otherwise fall back to zeros
  const defaults = sampleInput && Object.keys(sampleInput).length > 0
    ? sampleInput
    : Object.fromEntries(displayFields.map((f) => [f, 0]));

  const [values, setValues] = useState<Record<string, any>>(defaults);
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<PredictionResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const effectiveSelectedVersion = selectedVersion || activeVersion || versions[0]?.version || '';

  // Reset form when model type changes  
  useEffect(() => {
    const newDefaults = sampleInput && Object.keys(sampleInput).length > 0
      ? sampleInput
      : Object.fromEntries(displayFields.map((f) => [f, 0]));
    setValues(newDefaults);
    setResult(null);
    setError(null);
  }, [typeKey, sampleInput, displayFields]);

  const normalizeValue = (_key: string, raw: string) => {
    // Keep string fields as strings, convert numeric-looking values to numbers
    const num = Number(raw);
    if (raw === '' || isNaN(num)) return raw;
    return num;
  };

  const run = async () => {
    if (!effectiveSelectedVersion) {
      setError('Chưa có version để test');
      return;
    }
    setRunning(true);
    setResult(null);
    setError(null);
    try {
      // Normalize values before sending
      const payload: Record<string, any> = {};
      for (const [k, v] of Object.entries(values)) {
        payload[k] = typeof v === 'string' ? normalizeValue(k, v) : v;
      }
      
      // If testing non-active version, use aiTestVersion
      const isTestingActiveVersion = effectiveSelectedVersion === activeVersion;
      let res;
      if (isTestingActiveVersion) {
        res = await aiQuickPredict(typeKey, payload);
      } else {
        // Test specific version without deploying
        res = await aiTestVersion(typeKey, effectiveSelectedVersion, payload);
      }
      setResult(res?.data ?? res);
    } catch (e: any) {
      setError(e?.message || 'Predict lỗi');
    } finally {
      setRunning(false);
    }
  };

  const reset = () => setValues(defaults);

  const hasWarnings = result?.warnings && result.warnings.length > 0;

  return (
    <div className="grid md:grid-cols-2 gap-4">
      <div>
        {/* Version selector - cho phép chọn version để test */}
        <div className="flex items-center justify-between mb-3">
          <div className="text-sm font-medium">Test version</div>
          <select 
            value={effectiveSelectedVersion} 
            onChange={(e) => onSelectedVersionChange(e.target.value)}
            className="text-xs border rounded px-2 py-1 bg-background"
          >
            {versions.map((v) => (
              <option key={v.version} value={v.version}>
                {v.version} {v.active ? '(active)' : '(chưa deploy)'}
              </option>
            ))}
          </select>
        </div>
        <div className="flex items-center justify-between mb-2">
          <div className="text-sm font-medium">Input features</div>
          <Button size="sm" variant="ghost" onClick={reset} className="text-xs">Reset</Button>
        </div>
        <div className="space-y-2">
          {displayFields.map((f) => {
            const schema = inputSchema?.[f];
            const desc = schema?.desc || f;
            const unit = schema?.unit;
            const enumLabels = schema?.enumLabels;
            const value = values[f] ?? '';
            // Show label for enum values
            const displayLabel = enumLabels && schema?.enum
              ? enumLabels[schema.enum.indexOf(value)] || value
              : null;
            return (
              <div key={f} className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <label className="text-xs w-32 text-muted-foreground truncate" title={desc}>
                    {desc}
                  </label>
                  <input
                    value={value}
                    onChange={(e) => setValues({ ...values, [f]: normalizeValue(f, e.target.value) })}
                    className="flex-1 rounded-md border border-input bg-background px-2 py-1 text-xs font-mono"
                  />
                  {unit && <span className="text-xs text-muted-foreground w-12">{unit}</span>}
                </div>
                {displayLabel && (
                  <div className="text-xs text-muted-foreground ml-32 pl-2">
                    → {displayLabel}
                  </div>
                )}
                {schema?.min !== undefined && schema?.max !== undefined && (
                  <div className="text-[10px] text-muted-foreground ml-32 pl-2">
                    Giá trị: {schema.min} - {schema.max}
                  </div>
                )}
              </div>
            );
          })}
        </div>
        <Button onClick={run} disabled={running} className="mt-3 w-full">
          {running ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <PlayCircle className="w-4 h-4 mr-2" />}
          Chạy prediction
        </Button>

        {/* Processed input section */}
        {result?.processedInput && (
          <div className="mt-4">
            <div className="text-sm font-medium mb-1 text-muted-foreground">Input đã xử lý</div>
            <div className="rounded-md border bg-muted/10 p-2 text-xs font-mono overflow-auto max-h-[100px]">
              <pre className="whitespace-pre-wrap break-words">{JSON.stringify(result.processedInput, null, 2)}</pre>
            </div>
          </div>
        )}
      </div>

      <div>
        {/* Warnings */}
        {hasWarnings && (
          <div className="mb-3 rounded-md border border-amber-200 bg-amber-50 p-2">
            <div className="flex items-center gap-1 text-xs text-amber-700 font-medium mb-1">
              <AlertCircle className="w-3 h-3" /> Cảnh báo
            </div>
            <ul className="text-xs text-amber-700 space-y-0.5">
              {result.warnings.map((w, i) => (
                <li key={i} className="flex items-start gap-1">
                  <span className="text-amber-500">•</span> {w}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Chart */}
        {result?.chartData && (
          <PredictionResultChart
            chartData={result.chartData}
            height={180}
            accent={accent}
          />
        )}

        {/* Raw output section */}
        <div className="mt-4">
          <div className="text-sm font-medium mb-2 flex items-center justify-between">
            <span>Output JSON</span>
            {result && (
              <Button size="sm" variant="ghost" className="text-xs"
                onClick={() => navigator.clipboard?.writeText(JSON.stringify(result, null, 2))}>
                <Copy className="w-3 h-3 mr-1" /> Copy JSON
              </Button>
            )}
          </div>
          <div className="rounded-md border bg-muted/20 p-3 text-xs font-mono overflow-auto max-h-[200px]">
            {error && <div className="text-red-600">{error}</div>}
            {result ? (
              <>
                {'prediction' in result && (
                  <div className="mb-3">
                    <div className="text-sm text-muted-foreground mb-1">Kết quả dự đoán:</div>
                    {/* Formatted time output for charging_time */}
                    {result.formattedPrediction ? (
                      <div className="space-y-1">
                        <div className="flex items-baseline gap-2">
                          <span className="text-2xl font-bold text-primary">
                            {result.formattedPrediction}
                          </span>
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {result.predictionSeconds !== undefined && (
                            <span>Model output: {result.predictionSeconds.toFixed(1)} giây → {result.predictionMinutes?.toFixed(1)} phút</span>
                          )}
                        </div>
                      </div>
                    ) : (
                      <div className="flex items-baseline gap-2">
                        <span className="text-2xl font-bold">
                          {typeof result.prediction === 'number' 
                            ? result.prediction.toFixed(2) 
                            : String(result.prediction)}
                        </span>
                        {outputUnit && (
                          <span className="text-lg text-muted-foreground">{outputUnit}</span>
                        )}
                      </div>
                    )}
                    {outputMeaning && (
                      <div className="text-sm text-muted-foreground mt-1">{outputMeaning}</div>
                    )}
                  </div>
                )}
                {'modelVersion' in result && (
                  <div className="mb-2 text-xs text-muted-foreground">
                    Model version: <span className="font-mono">{result.modelVersion}</span>
                  </div>
                )}
                <pre className="whitespace-pre-wrap break-words">{JSON.stringify(result, null, 2)}</pre>
              </>
            ) : !error ? (
              <div className="text-muted-foreground">Chạy prediction để xem kết quả</div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Helper: extract numeric prediction from API response (generic) ─────
function extractPrediction(res: any): number | null {
  const data = res?.data ?? res;
  if (data == null) return null;
  // Try common keys in priority order
  const candidates = [
    data.predictionMinutes, data.prediction, data.value,
    data.result, data.output, data.score,
  ];
  for (const c of candidates) {
    if (typeof c === 'number' && Number.isFinite(c)) return c;
    if (Array.isArray(c) && typeof c[0] === 'number') return c[0];
  }
  return null;
}

// ── Enhanced Metrics tab ────────────────────────────────────────────────
function MetricsTabEnhanced({ meta, versions, selectedVersion, onSelectedVersionChange, activeVersion }: {
  meta: ModelTypeMeta;
  versions: ModelVersion[];
  selectedVersion: string | null;
  onSelectedVersionChange: (v: string) => void;
  activeVersion: string | null;
}) {
  const [evaluationMode, setEvaluationMode] = useState<'select' | 'input' | 'results'>('select');
  const [testInputs, setTestInputs] = useState<Record<string, any>>({});
  const [evaluationResults, setEvaluationResults] = useState<any>(null);
  const [isEvaluating, setIsEvaluating] = useState(false);
  const [evalError, setEvalError] = useState<string | null>(null);

  const inspectedVersion = selectedVersion || activeVersion || versions[0]?.version || '—';
  const inspectedMeta = versions.find((v) => v.version === inspectedVersion);
  const isActiveVersion = inspectedVersion === activeVersion;

  // Use sampleInput from registry if available, else fall back to zeros
  const visibleFields = (meta.visibleInputFields && meta.visibleInputFields.length > 0)
    ? meta.visibleInputFields
    : meta.inputFields || [];

  // Initialize test inputs from sampleInput / inputSchema defaults
  const initializeInputs = () => {
    const defaults: Record<string, any> = {};
    visibleFields.forEach(field => {
      const sample = meta.sampleInput?.[field];
      const schema = meta.inputSchema?.[field];
      if (sample !== undefined) {
        defaults[field] = sample;
      } else if (schema?.min !== undefined && schema?.max !== undefined) {
        defaults[field] = (Number(schema.min) + Number(schema.max)) / 2;
      } else {
        defaults[field] = 0;
      }
    });
    setTestInputs(defaults);
    setEvalError(null);
    setEvaluationMode('input');
  };

  // Build test cases by varying each field across low/mid/high
  const buildTestCases = (base: Record<string, any>) => {
    const cases: { label: string; payload: Record<string, any> }[] = [
      { label: 'Baseline (giá trị nhập)', payload: { ...base } },
    ];
    visibleFields.forEach(field => {
      const schema = meta.inputSchema?.[field];
      if (schema?.min !== undefined && schema?.max !== undefined) {
        const min = Number(schema.min);
        const max = Number(schema.max);
        const desc = schema.desc || field;
        cases.push({
          label: `${desc} thấp (${min}${schema.unit || ''})`,
          payload: { ...base, [field]: min },
        });
        cases.push({
          label: `${desc} cao (${max}${schema.unit || ''})`,
          payload: { ...base, [field]: max },
        });
      }
    });
    // Cap at 8 cases to keep evaluation fast
    return cases.slice(0, 8);
  };

  const runEvaluation = async () => {
    setIsEvaluating(true);
    setEvalError(null);
    try {
      const testCases = buildTestCases(testInputs);
      const results: any[] = [];

      for (const tc of testCases) {
        try {
          const res = isActiveVersion
            ? await aiQuickPredict(meta.key, tc.payload)
            : await aiTestVersion(meta.key, inspectedVersion, tc.payload);
          const data = res?.data ?? res;
          const prediction = extractPrediction(res);
          results.push({
            label: tc.label,
            payload: tc.payload,
            prediction,
            formattedPrediction: data?.formattedPrediction,
            ok: prediction !== null,
            error: null,
            raw: data,
          });
        } catch (e: any) {
          results.push({
            label: tc.label,
            payload: tc.payload,
            prediction: null,
            ok: false,
            error: e?.message || 'Predict lỗi',
          });
        }
      }

      const okResults = results.filter(r => r.ok && typeof r.prediction === 'number');
      const successRate = results.length ? (okResults.length / results.length) * 100 : 0;

      // Compute simple stats from real predictions
      const values = okResults.map(r => r.prediction as number);
      const avg = values.length ? values.reduce((s, v) => s + v, 0) / values.length : 0;
      const min = values.length ? Math.min(...values) : 0;
      const max = values.length ? Math.max(...values) : 0;
      const range = max - min;

      setEvaluationResults({
        testCases: results,
        averagePrediction: avg,
        minPrediction: min,
        maxPrediction: max,
        rangePrediction: range,
        successRate,
        totalCases: results.length,
        successCases: okResults.length,
        outputUnit: meta.outputUnit || '',
        modelVersion: inspectedVersion,
        evaluatedAt: new Date().toISOString(),
      });
      setEvaluationMode('results');
    } catch (error: any) {
      setEvalError(error?.message || 'Đánh giá thất bại');
    } finally {
      setIsEvaluating(false);
    }
  };

  if (evaluationMode === 'select') {
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="text-sm font-medium">Đánh giá model</div>
          <select
            value={inspectedVersion}
            onChange={(e) => onSelectedVersionChange(e.target.value)}
            className="text-xs border rounded px-2 py-1 bg-background"
          >
            {versions.map((v) => (
              <option key={v.version} value={v.version}>
                {v.version} {v.active ? '(active)' : ''}
              </option>
            ))}
          </select>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <BarChart3 className="w-5 h-5" />
              Đánh giá mô hình AI
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Chạy đánh giá tổng quan về model {meta.label} version {inspectedVersion}
              </p>
              
              <div className="grid grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="font-medium">Version:</span> {inspectedVersion}
                </div>
                <div>
                  <span className="font-medium">Upload:</span> {formatDate(inspectedMeta?.uploadedAt)}
                </div>
                <div>
                  <span className="font-medium">Size:</span> {formatBytes(inspectedMeta?.sizeBytes)}
                </div>
                <div>
                  <span className="font-medium">Features:</span> {meta.inputFields?.length || 0}
                </div>
              </div>

              <Button onClick={initializeInputs} className="w-full">
                <PlayCircle className="w-4 h-4 mr-2" />
                Bắt đầu đánh giá
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (evaluationMode === 'input') {
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="text-sm font-medium">Nhập dữ liệu test</div>
          <Button variant="outline" size="sm" onClick={() => setEvaluationMode('select')}>
            Quay lại
          </Button>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Nhập features cho test case baseline</CardTitle>
            <CardDescription className="text-xs">
              Hệ thống sẽ chạy nhiều test case dựa trên giá trị này (varying min/max của mỗi feature)
              và gọi API thật để lấy prediction.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {visibleFields.map((field) => {
                const schema = meta.inputSchema?.[field];
                const desc = schema?.desc || field;
                const unit = schema?.unit;
                return (
                  <div key={field} className="flex items-center gap-2">
                    <label className="text-xs w-40 text-muted-foreground truncate" title={desc}>{desc}</label>
                    <input
                      type="number"
                      value={testInputs[field] ?? 0}
                      onChange={(e) => setTestInputs({ ...testInputs, [field]: parseFloat(e.target.value) || 0 })}
                      className="flex-1 border rounded px-2 py-1 text-xs font-mono"
                    />
                    {unit && <span className="text-xs text-muted-foreground w-12">{unit}</span>}
                  </div>
                );
              })}

              {evalError && (
                <div className="text-xs rounded-md border border-red-200 bg-red-50 text-red-700 p-2 flex items-start gap-2">
                  <AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
                  <div>{evalError}</div>
                </div>
              )}

              <div className="flex gap-2 pt-2">
                <Button onClick={runEvaluation} disabled={isEvaluating} className="flex-1">
                  {isEvaluating ? (
                    <><Loader2 className="w-4 h-4 mr-2 animate-spin" /> Đang chạy {buildTestCases(testInputs).length} test cases...</>
                  ) : (
                    <><TrendingUp className="w-4 h-4 mr-2" /> Chạy đánh giá</>
                  )}
                </Button>
                <Button variant="outline" onClick={() => setEvaluationMode('select')} disabled={isEvaluating}>
                  Hủy
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  if (evaluationMode === 'results' && evaluationResults) {
    const er = evaluationResults;
    const unit = er.outputUnit || '';
    const maxPred = er.maxPrediction || 1;
    const successColor = er.successRate >= 90 ? 'text-green-600' : er.successRate >= 70 ? 'text-amber-600' : 'text-red-600';

    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div className="text-sm font-medium">Kết quả đánh giá (dữ liệu thật từ model)</div>
          <Button variant="outline" size="sm" onClick={() => setEvaluationMode('select')}>
            Đánh giá mới
          </Button>
        </div>

        {/* Summary Cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Card>
            <CardContent className="p-3">
              <div className="flex items-center gap-2">
                <TrendingUp className="w-4 h-4 text-blue-500" />
                <div>
                  <div className="text-xs text-muted-foreground">Trung bình</div>
                  <div className="text-base font-bold">{er.averagePrediction.toFixed(2)} {unit}</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-3">
              <div className="flex items-center gap-2">
                <CheckCircle2 className={`w-4 h-4 ${successColor}`} />
                <div>
                  <div className="text-xs text-muted-foreground">Tỷ lệ predict OK</div>
                  <div className={`text-base font-bold ${successColor}`}>{er.successRate.toFixed(0)}% ({er.successCases}/{er.totalCases})</div>
                </div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-3">
              <div>
                <div className="text-xs text-muted-foreground">Min — Max</div>
                <div className="text-base font-bold">{er.minPrediction.toFixed(2)} — {er.maxPrediction.toFixed(2)}</div>
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="p-3">
              <div>
                <div className="text-xs text-muted-foreground">Biên độ (range)</div>
                <div className="text-base font-bold">{er.rangePrediction.toFixed(2)} {unit}</div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Bar chart */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Biểu đồ dự đoán theo test case</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {er.testCases.map((tc: any, i: number) => {
                const widthPct = tc.ok && maxPred > 0 ? Math.max(2, (tc.prediction / maxPred) * 100) : 0;
                return (
                  <div key={i} className="text-xs">
                    <div className="flex justify-between mb-1">
                      <span className="truncate max-w-[60%]" title={tc.label}>{tc.label}</span>
                      <span className={`font-mono ${tc.ok ? '' : 'text-red-600'}`}>
                        {tc.ok ? `${tc.formattedPrediction || `${(tc.prediction as number).toFixed(2)} ${unit}`}` : `❌ ${tc.error || 'lỗi'}`}
                      </span>
                    </div>
                    <div className="h-3 bg-muted rounded overflow-hidden">
                      {tc.ok && (
                        <div
                          className="h-full bg-blue-500 transition-all"
                          style={{ width: `${widthPct}%` }}
                        />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* Detailed Results */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Chi tiết các test case</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {er.testCases.map((result: any, index: number) => (
                <div key={index} className={`border rounded p-2 text-xs ${result.ok ? '' : 'border-red-200 bg-red-50'}`}>
                  <div className="flex justify-between items-start mb-1">
                    <div className="font-medium">{result.label}</div>
                    <div className={`font-mono ${result.ok ? 'text-foreground' : 'text-red-600'}`}>
                      {result.ok
                        ? (result.formattedPrediction || `${(result.prediction as number).toFixed(2)} ${unit}`)
                        : `❌ ${result.error}`}
                    </div>
                  </div>
                  <div className="text-muted-foreground font-mono break-all">
                    Input: {JSON.stringify(result.payload)}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Model Info */}
        <Card>
          <CardContent className="p-3">
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div><span className="font-medium">Version:</span> <span className="font-mono">{er.modelVersion}</span></div>
              <div><span className="font-medium">Đánh giá lúc:</span> {new Date(er.evaluatedAt).toLocaleString('vi-VN')}</div>
            </div>
          </CardContent>
        </Card>
      </div>
    );
  }

  return null;
}
