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
        Loading versions...
      </div>
    );
  }

  if (versions.length === 0) {
    return (
      <div className="text-center py-12 text-slate-400">
        <Upload className="w-8 h-8 mx-auto mb-2 opacity-30 text-white" />
        <div className="text-sm font-medium text-slate-300">No versions yet</div>
        <div className="text-xs text-slate-500 mt-1">
          Select "Upload model" to add the first version.
        </div>
      </div>
    );
  }

  return (
    <div className="model-version-layout">
    <div className="model-version-cards space-y-3">
      {versions.map(v => <article key={v.version} className="rounded-xl border border-white/10 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h4 className="break-all font-mono font-semibold text-white">{v.version}</h4>
          {v.active && <Badge className="bg-emerald-700 text-white">ACTIVE</Badge>}
        </div>
        <dl className="my-4 space-y-2 text-sm">
          <div><dt className="text-slate-400">Uploaded</dt><dd className="text-slate-200">{formatDate(v.uploadedAt)}</dd></div>
          <div><dt className="text-slate-400">Size</dt><dd className="text-slate-200">{v.sizeBytes == null ? 'No data' : formatBytes(v.sizeBytes)}</dd></div>
          {v.note && <div><dt className="text-slate-400">Notes</dt><dd className="break-words text-slate-200">{v.note}</dd></div>}
        </dl>
        <ModelVersionActions version={v} isBusy={isBusy} onTest={onTest}
          onDeploy={onDeploy} onDelete={onDelete} onDeactivate={onDeactivate} onEvaluate={onEvaluate} />
      </article>)}
    </div>
    <div className="model-version-table overflow-x-auto">
      <table className="w-full min-w-[680px] text-sm [overflow-wrap:normal]">
        <thead className="whitespace-nowrap text-xs uppercase text-slate-400 border-b border-white/10">
          <tr>
            <th className="text-left py-2.5 px-3">Version</th>
            <th className="text-left py-2.5 px-3">Uploaded</th>
            <th className="text-left py-2.5 px-3">Size</th>
            <th className="text-left py-2.5 px-3">Notes</th>
            <th className="text-right py-2.5 px-3">Actions</th>
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
                <div className="flex min-w-32 flex-wrap items-center gap-2">
                  <span className="break-all font-semibold text-white">{v.version}</span>
                  {v.active && (
                    <Badge variant="default" className="shrink-0 whitespace-nowrap bg-emerald-600 hover:bg-emerald-600 text-white text-[10px] px-1.5 py-0 h-4">
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
                {v.sizeBytes == null ? '—' : formatBytes(v.sizeBytes)}
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
    </div>
  );
}
