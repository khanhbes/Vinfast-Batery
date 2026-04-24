import { useState } from 'react';
import { Upload, X, Loader2, AlertTriangle, CheckCircle2, AlertCircle, PlayCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
// @ts-ignore
import { aiUploadModel } from '@/api';

interface ValidationResult {
  ok: boolean;
  predictorKind?: string;
  featureCount?: number;
  warnings?: string[];
  error?: string;
}

interface ModelFeatures {
  count: number | null;
  names: string[] | null;
}

interface RegistryFeatures {
  count: number | null;
  fields: string[];
}

interface Props {
  typeKey: string;
  typeLabel: string;
  onClose: () => void;
  onUploaded: (switchToTest?: boolean) => void;
}

export default function UploadDialog({ typeKey, typeLabel, onClose, onUploaded }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [version, setVersion] = useState('');
  const [note, setNote] = useState('');
  const [skipSmoke, setSkipSmoke] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{
    version: string;
    activated: boolean;
    validation: ValidationResult;
    modelFeatures?: ModelFeatures;
    registryFeatures?: RegistryFeatures;
    featureMismatch?: boolean | null;
  } | null>(null);

  const submit = async () => {
    if (!file || !version.trim()) {
      setError('Chọn file model và nhập version');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await aiUploadModel(typeKey, file, version.trim(), note.trim(), skipSmoke);
      setResult(res?.data);
    } catch (e: any) {
      const errMsg = e?.message || 'Upload thất bại';
      // Handle [object Object] case
      setError(typeof errMsg === 'string' ? errMsg : JSON.stringify(errMsg));
    } finally {
      setBusy(false);
    }
  };

  const handleClose = (switchToTest = false) => {
    onUploaded(switchToTest);
    onClose();
  };

  // Show success result view
  if (result) {
    const hasWarnings = result.validation?.warnings && result.validation.warnings.length > 0;
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4"
        onClick={() => handleClose(false)}>
        <div className="bg-background rounded-xl shadow-2xl w-full max-w-md border"
          onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-between p-4 border-b">
            <h3 className="font-semibold flex items-center gap-2">
              {result.validation?.ok ? (
                <CheckCircle2 className="w-4 h-4 text-green-600" />
              ) : (
                <AlertCircle className="w-4 h-4 text-amber-600" />
              )}
              {result.validation?.ok ? 'Upload thành công' : 'Upload hoàn tất (có cảnh báo)'}
            </h3>
            <button onClick={() => handleClose(false)} className="text-muted-foreground hover:text-foreground">
              <X className="w-4 h-4" />
            </button>
          </div>

          <div className="p-4 space-y-3">
            <div className="rounded-md bg-green-50 border border-green-200 p-3">
              <div className="text-sm font-medium text-green-800">Version: {result.version}</div>
              <div className="text-xs text-green-700 mt-1">
                Trạng thái: {result.activated ? 'Đã kích hoạt' : 'Đã lưu (chưa kích hoạt)'}
              </div>
            </div>

            {/* Model vs Registry Features Comparison */}
            {result.modelFeatures && (
              <div className="rounded-md bg-blue-50 border border-blue-200 p-3">
                <div className="text-xs font-medium text-blue-800 mb-2">Thông tin features</div>
                
                <div className="grid grid-cols-2 gap-2 text-xs mb-2">
                  <div className="rounded-md bg-white/60 p-2">
                    <div className="text-muted-foreground">Model có</div>
                    <div className="font-medium text-blue-700">{result.modelFeatures.count ?? '?'} features</div>
                  </div>
                  <div className="rounded-md bg-white/60 p-2">
                    <div className="text-muted-foreground">Registry định nghĩa</div>
                    <div className="font-medium text-blue-700">{result.registryFeatures?.count ?? '?'} features</div>
                  </div>
                </div>
                
                {result.featureMismatch && (
                  <div className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md p-2 mb-2">
                    <AlertTriangle className="w-3 h-3 inline mr-1" />
                    Số features không khớp! Khi chạy prediction sẽ tự động thêm features = 0.
                  </div>
                )}
                
                {result.modelFeatures.names && result.modelFeatures.names.length > 0 && (
                  <div className="mt-2">
                    <div className="text-xs text-muted-foreground mb-1">Features trong model:</div>
                    <div className="flex flex-wrap gap-1">
                      {result.modelFeatures.names.map((name, i) => (
                        <span key={i} className="text-[10px] bg-blue-100 text-blue-800 px-1.5 py-0.5 rounded">
                          {name}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
                
                {!result.modelFeatures.names && result.modelFeatures.count && (
                  <div className="mt-2">
                    <div className="text-xs text-muted-foreground mb-1">Features trong model (không có tên):</div>
                    <div className="flex flex-wrap gap-1">
                      {Array.from({ length: Math.min(result.modelFeatures.count, 16) }, (_, i) => (
                        <span key={i} className="text-[10px] bg-gray-100 text-gray-700 px-1.5 py-0.5 rounded">
                          f{i}
                        </span>
                      ))}
                      {result.modelFeatures.count > 16 && (
                        <span className="text-[10px] text-muted-foreground">+{result.modelFeatures.count - 16}...</span>
                      )}
                    </div>
                  </div>
                )}
              </div>
            )}

            {hasWarnings && (
              <div className="rounded-md bg-amber-50 border border-amber-200 p-3">
                <div className="text-xs font-medium text-amber-800 flex items-center gap-1">
                  <AlertTriangle className="w-3 h-3" /> Cảnh báo
                </div>
                <ul className="text-xs text-amber-700 mt-1 space-y-0.5">
                  {result.validation?.warnings?.map((w: string, i: number) => (
                    <li key={i}>• {w}</li>
                  ))}
                </ul>
              </div>
            )}

            {!result.validation?.ok && result.validation?.error && (
              <div className="rounded-md bg-red-50 border border-red-200 p-3 text-xs text-red-700">
                <div className="font-medium">Lỗi validation:</div>
                <div className="mt-1">{result.validation.error}</div>
              </div>
            )}
          </div>

          <div className="flex justify-end gap-2 p-4 bg-muted/30 border-t rounded-b-xl">
            <Button variant="outline" size="sm" onClick={() => handleClose(false)}>
              Đóng
            </Button>
            {result.activated && (
              <Button size="sm" onClick={() => handleClose(true)}>
                <PlayCircle className="w-4 h-4 mr-2" />
                Chuyển đến Test
              </Button>
            )}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4"
      onClick={onClose}>
      <div
        className="bg-background rounded-xl shadow-2xl w-full max-w-md border"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-4 border-b">
          <div>
            <h3 className="font-semibold flex items-center gap-2">
              <Upload className="w-4 h-4" /> Upload model mới
            </h3>
            <p className="text-xs text-muted-foreground">{typeLabel}</p>
          </div>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 space-y-3">
          <div>
            <label className="text-xs font-medium block mb-1">File model (.pkl, .h5, .pt, .onnx, ...)</label>
            <input
              type="file"
              accept=".pkl,.h5,.hdf5,.pt,.pth,.onnx,.joblib,.cbm,.bin,.pmml,.pb,.tflite,.safetensors"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              className="block w-full text-sm file:mr-3 file:py-2 file:px-3 file:rounded-md file:border-0 file:bg-primary file:text-primary-foreground file:text-xs file:font-semibold hover:file:bg-primary/90"
            />
            {file && (
              <div className="text-xs text-muted-foreground mt-1">
                {file.name} · {(file.size / 1024).toFixed(1)} KB
              </div>
            )}
          </div>

          <div>
            <label className="text-xs font-medium block mb-1">Version *</label>
            <input
              type="text"
              value={version}
              onChange={(e) => setVersion(e.target.value)}
              placeholder="vd: 2026.04-a"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label className="text-xs font-medium block mb-1">Ghi chú</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="tùy chọn — mô tả thay đổi, dataset, metric..."
              rows={3}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm resize-none"
            />
          </div>

          {/* Skip smoke test toggle */}
          <label className="flex items-start gap-2 cursor-pointer rounded-md border border-border/50 p-2.5 hover:bg-muted/30 transition-colors">
            <input
              type="checkbox"
              checked={skipSmoke}
              onChange={(e) => setSkipSmoke(e.target.checked)}
              className="mt-0.5 accent-amber-500"
            />
            <div>
              <div className="text-xs font-medium flex items-center gap-1">
                <AlertTriangle className="w-3 h-3 text-amber-500" />
                Bỏ qua smoke test
              </div>
              <div className="text-[10px] text-muted-foreground mt-0.5">
                Dùng khi model có custom class hoặc dependency đặc biệt. Model sẽ được lưu & activate mà không kiểm tra predict.
              </div>
            </div>
          </label>

          {error && (
            <div className="text-sm rounded-md border border-red-200 bg-red-50 text-red-700 p-2">
              {error}
            </div>
          )}

          <div className="text-xs text-muted-foreground pt-2 border-t">
            {skipSmoke
              ? '⚠️ Model sẽ được lưu và activate trực tiếp, không kiểm tra predict.'
              : 'Model sẽ được nạp thử (smoke test) trước khi activate. Nếu fail, model đang active được giữ nguyên.'}
          </div>
        </div>

        <div className="flex justify-end gap-2 p-4 bg-muted/30 border-t rounded-b-xl">
          <Button variant="outline" size="sm" onClick={onClose} disabled={busy}>
            Hủy
          </Button>
          <Button size="sm" onClick={submit} disabled={busy || !file || !version.trim()}>
            {busy ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Upload className="w-4 h-4 mr-2" />}
            {busy ? 'Đang validate...' : 'Upload & kích hoạt'}
          </Button>
        </div>
      </div>
    </div>
  );
}
