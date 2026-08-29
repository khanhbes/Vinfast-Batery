import { CheckCircle2, AlertCircle, XCircle, PackageX, Loader2 } from 'lucide-react';
import { ModelTypeMeta } from './types';

export type ModelAvailabilityState =
  | 'no_model'
  | 'uploaded_only'
  | 'deployed_not_loaded'
  | 'loading'
  | 'ready'
  | 'invalid'
  | 'error';

export interface ModelAvailabilityInfo {
  state: ModelAvailabilityState;
  label: string;
  badgeText: string;
  color: string;
  bg: string;
  borderColor: string;
  icon: any;
  canPredict: boolean;
  activeVersion: string | null;
  description: string;
}

export function getActiveVersion(meta: ModelTypeMeta): string | null {
  return (
    meta.runtimeStatus.activeVersion ||
    meta.runtimeStatus.deploymentVersion ||
    meta.deploymentVersion ||
    meta.activeVersion ||
    null
  );
}

export function isModelDeployed(meta: ModelTypeMeta): boolean {
  return (
    meta.deploymentStatus === 'deployed' ||
    meta.runtimeStatus.deploymentStatus === 'deployed' ||
    Boolean(getActiveVersion(meta))
  );
}

export function isModelPredictable(meta: ModelTypeMeta): boolean {
  const activeVer = getActiveVersion(meta);
  const rt = meta.runtimeStatus;
  return (
    isModelDeployed(meta) &&
    Boolean(activeVer) &&
    rt.isLoaded === true &&
    rt.isPredictable === true
  );
}

export function getModelAvailability(meta: ModelTypeMeta): ModelAvailabilityInfo {
  const rt = meta.runtimeStatus;
  const activeVersion = getActiveVersion(meta);

  // 1. Ready: Loaded & Predictable
  if (rt.isLoaded && rt.isPredictable) {
    return {
      state: 'ready',
      label: 'Sẵn sàng',
      badgeText: activeVersion ? `Sẵn sàng · ${activeVersion}` : 'Sẵn sàng',
      color: 'text-emerald-400',
      bg: 'bg-emerald-500/10',
      borderColor: 'border-emerald-500/30',
      icon: CheckCircle2,
      canPredict: true,
      activeVersion,
      description: 'Model đã nạp và sẵn sàng chạy kiểm thử dự đoán.',
    };
  }

  // 2. Loaded but Predictor check failed
  if (rt.isLoaded && rt.isPredictable === false) {
    return {
      state: 'invalid',
      label: 'Model có lỗi',
      badgeText: activeVersion ? `Lỗi kiểm tra · ${activeVersion}` : 'Lỗi kiểm tra',
      color: 'text-red-400',
      bg: 'bg-red-500/10',
      borderColor: 'border-red-500/30',
      icon: XCircle,
      canPredict: false,
      activeVersion,
      description: 'Model đã nạp nhưng kiểm tra smoke test hoặc predictor không đạt yêu cầu.',
    };
  }

  // 3. Deployed / Active version exists but not yet loaded into RAM
  if (isModelDeployed(meta)) {
    return {
      state: 'deployed_not_loaded',
      label: 'Chưa nạp RAM',
      badgeText: activeVersion ? `Đã kích hoạt · ${activeVersion}` : 'Đã triển khai',
      color: 'text-blue-400',
      bg: 'bg-blue-500/10',
      borderColor: 'border-blue-500/30',
      icon: Loader2,
      canPredict: false,
      activeVersion,
      description: 'Model đã được kích hoạt làm phiên bản chính thức, đang cần nạp vào bộ nhớ.',
    };
  }

  // 4. Has uploaded versions but none is active / deployed
  if (rt.versionsCount > 0) {
    return {
      state: 'uploaded_only',
      label: 'Chưa triển khai',
      badgeText: `${rt.versionsCount} version chưa active`,
      color: 'text-amber-400',
      bg: 'bg-amber-500/10',
      borderColor: 'border-amber-500/30',
      icon: AlertCircle,
      canPredict: false,
      activeVersion: null,
      description: 'Bạn đã upload model nhưng chưa chọn version hoạt động (Deploy / Active).',
    };
  }

  // 5. No model at all
  return {
    state: 'no_model',
    label: 'Chưa có model',
    badgeText: 'Chưa có model',
    color: 'text-slate-400',
    bg: 'bg-slate-500/10',
    borderColor: 'border-slate-500/30',
    icon: PackageX,
    canPredict: false,
    activeVersion: null,
    description: 'Chưa có file model nào được tải lên cho chức năng này.',
  };
}
