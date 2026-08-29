import { Upload, CheckCircle2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { ModelVersion, formatBytes, formatDate } from '../types';
import ModelVersionActions from './ModelVersionActions';

interface Props {
  versions: ModelVersion[];
  loading: boolean;
  isBusy?: boolean;
  onTest?: (version: string) => void;
  onDeploy?: (version: string) => void;
  onDelete?: (version: string) => void;
  onDeactivate?: () => void;
  onEvaluate?: (version: string) => void;
}

export default function ModelVersionsList({
  versions,
  loading,
  isBusy = false,
  onTest,
  onDeploy,
  onDelete,
  onDeactivate,
  onEvaluate,
}: Props) {
  if (loading) {
    return (
      <div className="text-center py-10 text-slate-400 text-sm">
        Đang tải danh sách version...
      </div>
    );
  }

  if (versions.length === 0) {
    return (
      <div className="text-center py-12 text-slate-400">
        <Upload className="w-8 h-8 mx-auto mb-2 opacity-30 text-white" />
        <div className="text-sm font-medium text-slate-300">Chưa có version nào</div>
        <div className="text-xs text-slate-500 mt-1">
          Nhấn "Upload model" để thêm version đầu tiên.
        </div>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="text-xs uppercase text-slate-400 border-b border-white/10">
          <tr>
            <th className="text-left py-2.5 px-3">Version</th>
            <th className="text-left py-2.5 px-3">Uploaded</th>
            <th className="text-left py-2.5 px-3">Size</th>
            <th className="text-left py-2.5 px-3">Ghi chú</th>
            <th className="text-right py-2.5 px-3">Thao tác</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-white/5">
          {versions.map((v) => (
            <tr
              key={v.version}
              className={`transition-colors hover:bg-white/[0.02] ${
                v.active ? 'bg-emerald-500/10' : ''
              }`}
            >
              <td className="py-3 px-3 font-mono">
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-white">{v.version}</span>
                  {v.active && (
                    <Badge variant="default" className="bg-emerald-600 hover:bg-emerald-600 text-white text-[10px] px-1.5 py-0 h-4">
                      <CheckCircle2 className="w-2.5 h-2.5 mr-0.5" />
                      ACTIVE
                    </Badge>
                  )}
                </div>
              </td>
              <td className="py-3 px-3 text-slate-400 text-xs">
                {formatDate(v.uploadedAt)}
              </td>
              <td className="py-3 px-3 text-slate-400 text-xs">
                {formatBytes(v.sizeBytes)}
              </td>
              <td className="py-3 px-3 text-slate-400 text-xs truncate max-w-[200px]" title={v.note || ''}>
                {v.note || '—'}
              </td>
              <td className="py-3 px-3 text-right">
                <ModelVersionActions
                  version={v}
                  isBusy={isBusy}
                  onTest={onTest}
                  onDeploy={onDeploy}
                  onDelete={onDelete}
                  onDeactivate={v.active ? onDeactivate : undefined}
                  onEvaluate={onEvaluate}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
