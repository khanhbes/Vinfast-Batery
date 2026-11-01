import { Brain, Cpu, Eye, Sparkles } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import ModelCatalog from '@/components/ai-center/ModelCatalog';
import { datasetItems, useAdminData } from '@/data/AdminDataContext';

export default function AiCenter() {
  const { snapshot } = useAdminData();
  const profiles = datasetItems(snapshot, 'aiProfiles');
  const insights = datasetItems(snapshot, 'aiInsights');
  const predictions =
    datasetItems(snapshot, 'tripPredictions').length +
    datasetItems(snapshot, 'socPredictions').length;
  const samples = datasetItems(snapshot, 'chargingTrainingSamples').length;

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-[22px] font-semibold tracking-tight text-foreground">
          Mô hình AI
        </h1>
      </div>

      {/* KPI Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Hồ sơ AI cá nhân</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-foreground">{profiles.length}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">Xe đủ điều kiện fine-tune</p>
            </div>
            <div className="rounded-xl border border-border/60 bg-elevated/80 p-2.5 text-muted-foreground">
              <Brain className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Thông số xe (Insights)</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-emerald-500">{insights.length}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">Độ chính xác & sức khỏe</p>
            </div>
            <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-2.5 text-emerald-500">
              <Eye className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Tổng số lần dự đoán</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-sky-400">{predictions}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">Chuyến đi & thời gian sạc</p>
            </div>
            <div className="rounded-xl border border-sky-400/20 bg-sky-400/10 p-2.5 text-sky-400">
              <Sparkles className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-surface/50">
          <CardContent className="p-4 flex items-center justify-between">
            <div>
              <p className="text-xs text-muted-foreground font-medium">Mẫu dữ liệu huấn luyện</p>
              <p className="mt-1 text-2xl font-bold tabular-nums text-violet-400">{samples}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">Telemetry & sạc pin thực</p>
            </div>
            <div className="rounded-xl border border-violet-400/20 bg-violet-400/10 p-2.5 text-violet-400">
              <Cpu className="h-5 w-5" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Model Hub — catalog and universal model lab */}
      <ModelCatalog />
    </div>
  );
}
