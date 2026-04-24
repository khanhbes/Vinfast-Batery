import { useCallback, useEffect, useState } from 'react';
import {
  RefreshCw, Upload, Rewind, Trash2, PlayCircle, CheckCircle2, AlertCircle,
  History, FlaskConical, BarChart3, Loader2, Copy, PackageX, PowerOff,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
// @ts-ignore
import { aiListModels, aiRollbackModel, aiDeleteModel, aiQuickPredict, aiLoadActiveModel, aiDeactivateModel, aiValidateVersion } from '@/api';
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

  // When switching model, default to Test tab + try to load the active model
  useEffect(() => {
    reload();
    setTab('test');
    setMessage(null);
    setLoadError(null);

    // Try to ensure the model is loaded
    setLoadingModel(true);
    aiLoadActiveModel(meta.key)
      .then(() => setLoadError(null))
      .catch((e: any) => setLoadError(e?.message || 'Không thể nạp model'))
      .finally(() => setLoadingModel(false));
  }, [meta.key, reload]);

  const onRollback = async (v: string) => {
    // First validate the version
    setMessage({ type: 'info', text: `Đang kiểm tra version "${v}"...` });
    try {
      const validation = await aiValidateVersion(meta.key, v);
      if (!validation?.data?.valid) {
        const err = validation?.data?.error || validation?.data?.validation?.error || 'Validation failed';
        setMessage({ type: 'err', text: `Version "${v}" không hợp lệ: ${err}` });
        return;
      }
      // Validation passed, proceed with rollback
      if (!confirm(`Version "${v}" đã kiểm tra OK.\n\nKích hoạt ngay?`)) return;
      await aiRollbackModel(meta.key, v);
      setMessage({ type: 'ok', text: `Đã activate ${v}` });
      await reload();
      onAfterChange();
    } catch (e: any) {
      setMessage({ type: 'err', text: e?.message || 'Rollback thất bại' });
    }
  };

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

  const sorted = [...versions].sort((a, b) => (b.uploadedAt || '').localeCompare(a.uploadedAt || ''));

  // Determine model availability state
  const hasActiveVersion = !!meta.runtimeStatus.activeVersion;
  const hasVersions = meta.runtimeStatus.versionsCount > 0;

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
          ) : !hasActiveVersion || loadError ? (
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
            onRollback={onRollback}
            onDelete={onDelete}
          />
        )}
        {tab === 'metrics' && <MetricsTab meta={meta} />}
      </CardContent>

      {uploadOpen && (
        <UploadDialog
          typeKey={meta.key}
          typeLabel={meta.label}
          onClose={() => setUploadOpen(false)}
          onUploaded={(switchToTest = false) => {
            setMessage({ type: 'ok', text: 'Upload & activate thành công' });
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
          <>Model <span className="font-mono text-xs bg-muted rounded px-1">{typeKey}</span> có version nhưng chưa active hoặc không load được. Vào tab <strong>Versions</strong> để activate, hoặc upload lại.</>
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
function VersionsTab({ versions, loading, onRollback, onDelete }: {
  versions: ModelVersion[]; loading: boolean;
  onRollback: (v: string) => void; onDelete: (v: string) => void;
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
                  {!v.active && (
                    <Button size="sm" variant="outline" onClick={() => onRollback(v.version)}>
                      <Rewind className="w-3.5 h-3.5 mr-1" /> Activate
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
    setRunning(true);
    setResult(null);
    setError(null);
    try {
      // Normalize values before sending
      const payload: Record<string, any> = {};
      for (const [k, v] of Object.entries(values)) {
        payload[k] = typeof v === 'string' ? normalizeValue(k, v) : v;
      }
      const res = await aiQuickPredict(typeKey, payload);
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

// ── Metrics tab ────────────────────────────────────────────────────
function MetricsTab({ meta }: { meta: ModelTypeMeta }) {
  const s = meta.runtimeStatus;
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <StatBox label="Trạng thái" value={s.isLoaded ? 'Loaded' : 'Chưa nạp'} accent={s.isLoaded ? 'ok' : 'warn'} />
        <StatBox label="Có thể predict" value={s.isPredictable ? 'Có' : 'Không'} accent={s.isPredictable ? 'ok' : 'warn'} />
        <StatBox label="Active version" value={s.activeVersion || '—'} mono />
        <StatBox label="Tổng versions" value={String(s.versionsCount)} />
        <StatBox label="Loại predictor" value={s.predictorKind || '—'} mono />
        <StatBox label="Số features" value={s.featureCount != null ? String(s.featureCount) : '—'} />
        <StatBox label="Last load" value={formatDate(s.lastLoadAt)} small />
        <StatBox label="Output kind" value={meta.outputKind || 'scalar'} />
      </div>
      {s.validationError ? (
        <div className="text-sm rounded-md border border-red-200 bg-red-50 text-red-700 p-3 flex items-start gap-2">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
          <div>
            <div className="font-medium">Lỗi validation</div>
            <div className="mt-1 font-mono text-xs break-words">{s.validationError}</div>
          </div>
        </div>
      ) : s.lastError ? (
        <div className="text-sm rounded-md border border-red-200 bg-red-50 text-red-700 p-3 flex items-start gap-2">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
          <div>
            <div className="font-medium">Lỗi gần nhất</div>
            <div className="mt-1 font-mono text-xs break-words">{s.lastError}</div>
          </div>
        </div>
      ) : (
        <div className="text-sm rounded-md border border-green-200 bg-green-50 text-green-700 p-3 flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4" />
          Không có lỗi gần đây
        </div>
      )}
      <div className="text-xs text-muted-foreground pt-2 border-t">
        💡 Dashboard metrics chi tiết (accuracy/loss/MAE) sẽ được bổ sung khi dataset chuẩn được cấu hình cho từng model type.
      </div>
    </div>
  );
}

function StatBox({ label, value, accent, mono, small }: {
  label: string; value: string; accent?: 'ok' | 'warn'; mono?: boolean; small?: boolean;
}) {
  const accentClass = accent === 'ok' ? 'text-green-700' : accent === 'warn' ? 'text-amber-700' : '';
  return (
    <div className="rounded-md border bg-card p-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className={`mt-1 ${small ? 'text-xs' : 'text-sm'} ${mono ? 'font-mono' : 'font-semibold'} ${accentClass} truncate`} title={value}>
        {value}
      </div>
    </div>
  );
}
