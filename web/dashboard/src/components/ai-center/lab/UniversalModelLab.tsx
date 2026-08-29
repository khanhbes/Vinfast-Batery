import { useState, useEffect, useCallback } from 'react';
import { Route, Loader2, Settings, Upload, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
// @ts-ignore
import { aiQuickPredict, aiLoadActiveModel } from '@/api';
import { ModelTypeMeta, PredictionResponse } from '../types';
import { getModelAvailability, isModelPredictable } from '../modelAvailability';
import { buildPredictionPayload } from './modelLabUtils';
import ModelLabHeader from './ModelLabHeader';
import ModelAvailabilityBanner from './ModelAvailabilityBanner';
import ModelInputPanel from './ModelInputPanel';
import ModelResultPanel from './ModelResultPanel';
import ModelManagerDrawer from '../management/ModelManagerDrawer';
import UploadDialog from '../UploadDialog';

interface Props {
  meta: ModelTypeMeta;
  onModelChanged: () => void;
}

export default function UniversalModelLab({ meta, onModelChanged }: Props) {
  const [inputState, setInputState] = useState<Record<string, any>>({});
  const [result, setResult] = useState<PredictionResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadingLoad, setLoadingLoad] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);

  // Initialize inputs from sampleInput or defaults when meta.key changes
  useEffect(() => {
    const fields = meta.visibleInputFields ?? meta.inputFields ?? [];
    const sample = meta.sampleInput || {};
    const initial: Record<string, any> = {};

    for (const f of fields) {
      if (f in sample) {
        initial[f] = sample[f];
      } else {
        const schema = meta.inputSchema?.[f];
        if (schema?.min !== undefined) {
          initial[f] = schema.min;
        } else {
          initial[f] = 0;
        }
      }
    }

    setInputState(initial);
    setResult(null);
    setError(null);
  }, [meta.key, meta.sampleInput, meta.inputFields, meta.visibleInputFields, meta.inputSchema]);

  const availability = getModelAvailability(meta);
  const canPredict = isModelPredictable(meta);

  // Try to load active model into memory if deployed but not yet loaded
  const handleReloadActive = useCallback(async () => {
    setLoadingLoad(true);
    setError(null);
    try {
      await aiLoadActiveModel(meta.key);
      onModelChanged();
    } catch (e: any) {
      setError(e?.message || 'Không thể nạp model vào bộ nhớ');
    } finally {
      setLoadingLoad(false);
    }
  }, [meta.key, onModelChanged]);

  const handleInputChange = (field: string, value: any) => {
    setInputState((prev) => ({
      ...prev,
      [field]: value,
    }));
  };

  const runPrediction = async () => {
    if (!canPredict) return;
    setLoading(true);
    setError(null);
    try {
      const payload = buildPredictionPayload(meta, inputState);
      const res = await aiQuickPredict(meta.key, payload);
      setResult(res?.data ?? res);
    } catch (e: any) {
      setError(e?.message || 'Không thể chạy dự đoán. Model không phản hồi hoặc dữ liệu chưa hợp lệ.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <section className="overflow-hidden rounded-2xl border border-slate-800 bg-slate-950 text-white shadow-xl">
      <div className="grid lg:grid-cols-[1.1fr_.9fr]">
        {/* Left Column: Header, Availability, Inputs, Actions */}
        <div className="p-6 lg:p-8 flex flex-col justify-between">
          <div>
            <ModelLabHeader meta={meta} accent={meta.accent} />

            <ModelAvailabilityBanner
              availability={availability}
              onUpload={() => setUploadOpen(true)}
              onManage={() => setDrawerOpen(true)}
              onReloadActive={handleReloadActive}
              loadingLoad={loadingLoad}
            />

            <ModelInputPanel
              meta={meta}
              inputState={inputState}
              onChange={handleInputChange}
              accent={meta.accent}
              disabled={!canPredict || loading}
            />
          </div>

          {/* Action Buttons */}
          <div className="mt-8 pt-4 border-t border-white/10">
            <div className="flex flex-wrap items-center gap-3">
              <Button
                onClick={runPrediction}
                disabled={!canPredict || loading}
                className="bg-emerald-400 text-slate-950 hover:bg-emerald-300 font-semibold px-5 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {loading ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Đang dự đoán...
                  </>
                ) : (
                  <>
                    <Route className="mr-2 h-4 w-4" />
                    Chạy dự đoán
                  </>
                )}
              </Button>

              <Button
                variant="outline"
                onClick={() => setDrawerOpen(true)}
                className="border-white/15 bg-white/5 hover:bg-white/10 text-white text-xs"
              >
                <Settings className="mr-1.5 h-3.5 w-3.5" />
                Quản lý model
              </Button>

              {availability.state === 'no_model' && (
                <Button
                  variant="outline"
                  onClick={() => setUploadOpen(true)}
                  className="border-white/15 bg-white/5 hover:bg-white/10 text-white text-xs"
                >
                  <Upload className="mr-1.5 h-3.5 w-3.5" />
                  Upload model
                </Button>
              )}
            </div>

            {error && (
              <div className="mt-3 flex items-center justify-between rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-xs text-red-300">
                <span>{error}</span>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={runPrediction}
                  className="h-6 text-xs text-red-200 hover:text-white"
                >
                  <RefreshCw className="w-3 h-3 mr-1" /> Thử lại
                </Button>
              </div>
            )}
          </div>
        </div>

        {/* Right Column: Results Panel */}
        <ModelResultPanel
          meta={meta}
          result={result}
          loading={loading}
          accent={meta.accent}
          inputState={inputState}
        />
      </div>

      {/* Model Manager Drawer */}
      <ModelManagerDrawer
        meta={meta}
        isOpen={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        onModelChanged={onModelChanged}
      />

      {/* Direct Upload Dialog */}
      {uploadOpen && (
        <UploadDialog
          typeKey={meta.key}
          typeLabel={meta.label}
          onClose={() => setUploadOpen(false)}
          onUploaded={() => {
            onModelChanged();
          }}
        />
      )}
    </section>
  );
}
