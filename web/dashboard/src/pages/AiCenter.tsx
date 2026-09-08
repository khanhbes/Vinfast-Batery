import { Settings } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import ModelCatalog from '@/components/ai-center/ModelCatalog';

export default function AiCenter() {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="page-header">
        <div>
          <h1 className="text-3xl font-bold text-foreground">AI Center</h1>
          <p className="text-muted-foreground mt-1">Quản lý và giám sát các mô hình AI dự đoán pin</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2" asChild><Link to="/settings">
            <Settings className="w-4 h-4" />
            Cài đặt
          </Link></Button>
        </div>
      </div>

      {/* Model Hub — Catalog + Inline Universal Model Lab */}
      <ModelCatalog />
    </div>
  );
}
