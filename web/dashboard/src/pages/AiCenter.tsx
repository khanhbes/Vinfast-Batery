import { Database, Settings } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import ModelCatalog from '@/components/ai-center/ModelCatalog';
import { datasetItems, useAdminData } from '@/data/AdminDataContext';

export default function AiCenter() {
  const { snapshot } = useAdminData();
  const profiles = datasetItems(snapshot, 'aiProfiles');
  const insights = datasetItems(snapshot, 'aiInsights');
  const predictions = datasetItems(snapshot, 'tripPredictions').length + datasetItems(snapshot, 'socPredictions').length;
  const samples = datasetItems(snapshot, 'chargingTrainingSamples').length;
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="page-header">
        <div>
          <h1 className="text-3xl font-bold text-foreground">AI Center</h1>
          <p className="text-muted-foreground mt-1">Manage model lifecycle and inspect AI data synchronized from the mobile app.</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2" asChild><Link to="/settings">
            <Settings className="w-4 h-4" />
            Settings
          </Link></Button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border bg-border md:grid-cols-4">
        {[['Personal profiles', profiles.length], ['Vehicle insights', insights.length], ['Predictions', predictions], ['Training samples', samples]].map(([label, value]) => <div key={String(label)} className="bg-card p-5"><p className="text-2xl font-semibold tabular-nums">{value}</p><p className="mt-1 text-xs text-muted-foreground">{label}</p></div>)}
      </div>
      <div className="flex justify-end"><Button variant="outline" asChild className="gap-2"><Link to="/data?dataset=aiInsights"><Database className="h-4 w-4" />Open synchronized AI records</Link></Button></div>

      {/* Model Hub — catalog and universal model lab */}
      <ModelCatalog />
    </div>
  );
}
