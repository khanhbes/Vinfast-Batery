import { Upload, Settings, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ModelAvailabilityInfo } from '../modelAvailability';

interface Props {
  availability: ModelAvailabilityInfo;
  onUpload: () => void;
  onManage: () => void;
  onReloadActive?: () => void;
  loadingLoad?: boolean;
}

export default function ModelAvailabilityBanner({
  availability,
  onUpload,
  onManage,
  onReloadActive,
  loadingLoad = false,
}: Props) {
  if (availability.state === 'ready') {
    return null;
  }

  const Icon = availability.icon;

  return (
    <div className={`mt-4 rounded-xl border p-4 ${availability.bg} ${availability.borderColor}`}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-start gap-3">
          <div className={`mt-0.5 rounded-lg p-1.5 bg-black/20 ${availability.color}`}>
            <Icon className={`h-4 w-4 ${availability.state === 'deployed_not_loaded' && loadingLoad ? 'animate-spin' : ''}`} />
          </div>
          <div>
            <div className={`text-sm font-semibold ${availability.color}`}>
              {availability.label}
            </div>
            <p className="text-xs text-slate-300 mt-0.5 max-w-lg">
              {availability.description}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {availability.state === 'no_model' && (
            <Button
              size="sm"
              onClick={onUpload}
              className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
            >
              <Upload className="mr-1.5 h-3.5 w-3.5" />
              Upload model
            </Button>
          )}

          {availability.state === 'uploaded_only' && (
            <Button
              size="sm"
              onClick={onManage}
              className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
            >
              <Settings className="mr-1.5 h-3.5 w-3.5" />
              Quản lý model
            </Button>
          )}

          {availability.state === 'deployed_not_loaded' && (
            <>
              {onReloadActive && (
                <Button
                  size="sm"
                  onClick={onReloadActive}
                  disabled={loadingLoad}
                  className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
                >
                  <RefreshCw className={`mr-1.5 h-3.5 w-3.5 ${loadingLoad ? 'animate-spin' : ''}`} />
                  Nạp lại
                </Button>
              )}
              <Button
                size="sm"
                onClick={onManage}
                className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
              >
                <Settings className="mr-1.5 h-3.5 w-3.5" />
                Quản lý model
              </Button>
            </>
          )}

          {(availability.state === 'invalid' || availability.state === 'error') && (
            <>
              {onReloadActive && (
                <Button
                  size="sm"
                  onClick={onReloadActive}
                  disabled={loadingLoad}
                  className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
                >
                  <RefreshCw className={`mr-1.5 h-3.5 w-3.5 ${loadingLoad ? 'animate-spin' : ''}`} />
                  Thử lại
                </Button>
              )}
              <Button
                size="sm"
                onClick={onManage}
                className="bg-white/10 hover:bg-white/20 text-white border border-white/15 text-xs"
              >
                <Settings className="mr-1.5 h-3.5 w-3.5" />
                Quản lý model
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
