import { useState, useId, useRef } from 'react';
import { validateModelUpload } from './uploadPolicy';
import { Upload, X, Loader2, AlertTriangle, CheckCircle2, AlertCircle, PlayCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ModalSurface } from '@/components/ui/modal-surface';
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
  const fieldId = useId();
  const submitting = useRef(false);
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
    if (submitting.current) return;
    const validationError = validateModelUpload(file, version);
    if (validationError || !file) {
      setError(validationError);
      return;
    }
    submitting.current = true;
    setBusy(true);
    setError(null);
    try {
      const res = await aiUploadModel(typeKey, file, version.trim(), note.trim(), skipSmoke);
      if (!res?.data || res.data.version !== version.trim() || res.data.uploadStored !== true) {
        throw new Error('The stored model could not be confirmed. Refresh the version list before trying again.');
      }
      setResult(res.data);
    } catch (e: any) {
      const errMsg = e?.message || 'Upload failed';
      // Handle [object Object] case
      setError(typeof errMsg === 'string' ? errMsg : JSON.stringify(errMsg));
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  };

  const handleClose = (switchToTest = false) => {
    if (busy) return;
    if (result) onUploaded(switchToTest);
    onClose();
  };

  // Show success result view
  if (result) {
    const hasWarnings = result.validation?.warnings && result.validation.warnings.length > 0;
    return (
      <ModalSurface label="Model upload result" onClose={() => handleClose(false)}>
        <div className="bg-background rounded-xl shadow-2xl w-full max-w-md border"
          onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-between p-4 border-b">
            <h3 className="font-semibold flex items-center gap-2">
              {result.validation?.ok ? (
                <CheckCircle2 className="w-4 h-4 text-green-600" />
              ) : (
                <AlertCircle className="w-4 h-4 text-amber-600" />
              )}
              {result.validation?.ok ? 'Upload successful' : 'Upload completed with warnings'}
            </h3>
            <button aria-label="Close upload result" onClick={() => handleClose(false)} className="min-h-11 min-w-11 text-muted-foreground hover:text-foreground">
              <X className="w-4 h-4" />
            </button>
          </div>

          <div className="p-4 space-y-3">
            <div className="rounded-md bg-green-50 border border-green-200 p-3">
              <div className="break-all text-sm font-medium text-green-800">Version: {result.version}</div>
              <div className="text-xs text-green-700 mt-1">
                Status: {result.activated ? 'Activated' : 'Stored (not activated)'}
              </div>
            </div>

            {/* Model vs Registry Features Comparison */}
            {result.modelFeatures && (
              <div className="rounded-md bg-blue-50 border border-blue-200 p-3">
                <div className="text-xs font-medium text-blue-800 mb-2">Feature information</div>
                
                <div className="grid grid-cols-2 gap-2 text-xs mb-2">
                  <div className="rounded-md bg-white/60 p-2">
                    <div className="text-muted-foreground">Model inputs</div>
                    <div className="font-medium text-blue-700">{result.modelFeatures.count ?? '?'} features</div>
                  </div>
                  <div className="rounded-md bg-white/60 p-2">
                    <div className="text-muted-foreground">Registry definition</div>
                    <div className="font-medium text-blue-700">{result.registryFeatures?.count ?? '?'} features</div>
                  </div>
                </div>
                
                {result.featureMismatch && (
                  <div className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md p-2 mb-2">
                    <AlertTriangle className="w-3 h-3 inline mr-1" />
                    Input counts do not match. Review the schema and test before deployment; missing inputs are never silently set to zero.
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
                    <div className="text-xs text-muted-foreground mb-1">Unnamed model features:</div>
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
                  <AlertTriangle className="w-3 h-3" /> Warnings
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
                <div className="font-medium">Validation errors:</div>
                <div className="mt-1">{result.validation.error}</div>
              </div>
            )}
          </div>

          <div className="flex justify-end gap-2 p-4 bg-muted/30 border-t rounded-b-xl">
            <Button variant="outline" size="sm" onClick={() => handleClose(false)}>
              Close
            </Button>
            {result.validation?.ok && (
              <Button size="sm" onClick={() => handleClose(true)}>
                <PlayCircle className="w-4 h-4 mr-2" />
                Continue to test
              </Button>
            )}
          </div>
        </div>
      </ModalSurface>
    );
  }

  return (
    <ModalSurface label={`Upload model ${typeLabel}`} busy={busy} onClose={() => handleClose(false)}>
      <div
        className="bg-background rounded-xl shadow-2xl w-full max-w-md border"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-4 border-b">
          <div>
            <h3 className="font-semibold flex items-center gap-2">
              <Upload className="w-4 h-4" /> Upload new model
            </h3>
            <p className="text-xs text-muted-foreground">{typeLabel}</p>
          </div>
          <button aria-label="Close upload" disabled={busy} onClick={() => handleClose(false)} className="min-h-11 min-w-11 text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 space-y-3">
          <div>
            <label htmlFor={`${fieldId}-file`} className="text-xs font-medium block mb-1">File model ONNX / TFLite · maximum 64 MiB</label>
            <input
              id={`${fieldId}-file`}
              type="file"
              accept=".onnx,.tflite"
              disabled={busy}
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              className="block w-full text-sm file:mr-3 file:py-2 file:px-3 file:rounded-md file:border-0 file:bg-primary file:text-primary-foreground file:text-xs file:font-semibold hover:file:bg-primary/90"
            />
            {file && (
              <div className="break-all text-xs text-muted-foreground mt-1">
                {file.name} · {(file.size / 1024).toFixed(1)} KB
              </div>
            )}
          </div>

          <div>
            <label htmlFor={`${fieldId}-version`} className="text-xs font-medium block mb-1">Version *</label>
            <input
              id={`${fieldId}-version`}
              type="text"
              disabled={busy}
              value={version}
              onChange={(e) => setVersion(e.target.value)}
              placeholder="vd: 2026.04-a"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            />
          </div>

          <div>
            <label htmlFor={`${fieldId}-note`} className="text-xs font-medium block mb-1">Notes</label>
            <textarea
              id={`${fieldId}-note`}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="optional — describe changes, dataset and metrics..."
              rows={3}
              disabled={busy}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm resize-none"
            />
          </div>

          {/* Skip smoke test toggle */}
          <label className="flex items-start gap-2 cursor-pointer rounded-md border border-border/50 p-2.5 hover:bg-muted/30 transition-colors">
            <input
              type="checkbox"
              disabled={busy}
              checked={skipSmoke}
              onChange={(e) => setSkipSmoke(e.target.checked)}
              className="mt-0.5 accent-amber-500"
            />
            <div>
              <div className="text-xs font-medium flex items-center gap-1">
                <AlertTriangle className="w-3 h-3 text-amber-500" />
                Skip smoke test
              </div>
              <div className="text-[10px] text-muted-foreground mt-0.5">
                Store an unverified version only. Test and deploy remain separate actions; it is not activated automatically.
              </div>
            </div>
          </label>

          {error && (
            <div role="alert" className="break-words text-sm rounded-md border border-red-200 bg-red-50 text-red-700 p-2">
              {error}
            </div>
          )}

          <div className="text-xs text-muted-foreground pt-2 border-t">
            {skipSmoke
              ? 'The model will be stored but unverified. The active version will not change.'
              : 'Upload → Test → Deploy. Uploading does not activate the model or change the active version.'}
          </div>
        </div>

        <div className="flex justify-end gap-2 p-4 bg-muted/30 border-t rounded-b-xl">
          <Button variant="outline" size="sm" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button size="sm" onClick={submit} disabled={busy || !file || !version.trim()}>
            {busy ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Upload className="w-4 h-4 mr-2" />}
            {busy ? 'Uploading and validating...' : 'Upload version'}
          </Button>
        </div>
      </div>
    </ModalSurface>
  );
}
