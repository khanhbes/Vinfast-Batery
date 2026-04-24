import { Settings } from 'lucide-react';
import { Button } from '@/components/ui/button';
import ModelCatalog from '@/components/ai-center/ModelCatalog';

export default function AiCenter() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">AI Center</h1>
          <p className="text-muted-foreground mt-1">Quản lý và giám sát các mô hình AI dự đoán pin</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2">
            <Settings className="w-4 h-4" />
            Cài đặt
          </Button>
        </div>
      </div>

      {/* Model Hub — multi-type catalog + detail panel (only when selected) */}
      <ModelCatalog />
    </div>
  );
}
