import { PlayCircle, CheckCircle2, Trash2, PowerOff, BarChart3 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ModelVersion } from '../types';

interface Props {
  version: ModelVersion;
  isBusy?: boolean;
  onTest?: (version: string) => void;
  onDeploy?: (version: string) => void;
  onDelete?: (version: string) => void;
  onDeactivate?: () => void;
  onEvaluate?: (version: string) => void;
}

export default function ModelVersionActions({
  version,
  isBusy = false,
  onTest,
  onDeploy,
  onDelete,
  onDeactivate,
  onEvaluate,
}: Props) {
  return (
    <div className="inline-flex items-center gap-1.5">
      {onEvaluate && (
        <Button
          size="sm"
          variant="outline"
          disabled={isBusy}
          onClick={() => onEvaluate(version.version)}
          className="text-xs h-8 px-2.5 text-slate-200 border-white/10 hover:bg-white/10"
        >
          <BarChart3 className="w-3.5 h-3.5 mr-1" />
          Đánh giá
        </Button>
      )}

      {!version.active && onTest && (
        <Button
          size="sm"
          variant="outline"
          disabled={isBusy}
          onClick={() => onTest(version.version)}
          className="text-xs h-8 px-2.5 text-slate-200 border-white/10 hover:bg-white/10"
        >
          <PlayCircle className="w-3.5 h-3.5 mr-1" />
          Test
        </Button>
      )}

      {!version.active && onDeploy && (
        <Button
          size="sm"
          disabled={isBusy}
          onClick={() => onDeploy(version.version)}
          className="text-xs h-8 px-2.5 bg-blue-600 hover:bg-blue-500 text-white"
        >
          <CheckCircle2 className="w-3.5 h-3.5 mr-1" />
          Deploy
        </Button>
      )}

      {version.active && onDeactivate && (
        <Button
          size="sm"
          variant="outline"
          disabled={isBusy}
          onClick={onDeactivate}
          className="text-xs h-8 px-2.5 text-amber-400 border-amber-500/30 hover:bg-amber-500/10"
        >
          <PowerOff className="w-3.5 h-3.5 mr-1" />
          Deactivate
        </Button>
      )}

      {!version.active && onDelete && (
        <Button
          size="sm"
          variant="ghost"
          disabled={isBusy}
          onClick={() => onDelete(version.version)}
          className="text-xs h-8 px-2 text-red-400 hover:text-red-300 hover:bg-red-500/10"
          title="Xóa version"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </Button>
      )}
    </div>
  );
}
