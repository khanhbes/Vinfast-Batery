// Isolated QA fixture, not a production entry or authentication bypass.
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { MotionConfig } from 'motion/react';
import { DashboardShell } from '../../src/components/layout/DashboardShell';
import AiCenter from '../../src/pages/AiCenter';
import '../../src/index.css';

const model = {
  key: 'charging_time', label: 'Dự đoán thời gian sạc',
  description: 'Dữ liệu giả lập để kiểm tra giao diện.',
  icon: 'Clock', accent: 'emerald', group: 'survival', phase: 'v1.0',
  status: 'ready', deploymentStatus: 'deployed', outputKind: 'scalar',
  displayUnit: 'time', outputUnit: 's', inputFields: ['start_soc', 'end_soc', 'delta_soc'],
  visibleInputFields: ['start_soc', 'end_soc'], sampleInput: { start_soc: 20, end_soc: 80 },
  inputSchema: {
    start_soc: { type: 'number', min: 0, max: 100, label: 'SOC bắt đầu' },
    end_soc: { type: 'number', min: 0, max: 100, label: 'SOC kết thúc' },
  },
  derivedFields: { delta_soc: { formula: 'end_soc - start_soc' } },
  runtimeStatus: { isLoaded: true, isPredictable: true, activeVersion: 'qa-v1', versionsCount: 1 },
};
// Fixture-only network boundary: never call a real API or Firebase.
window.fetch = async (input) => {
  const url = String(input instanceof Request ? input.url : input);
  let data: unknown;
  if (url.endsWith('/types')) data = { types: [model], groups: [
    { key: 'survival', label: 'Pin & sạc', subtitle: 'Dữ liệu kiểm thử', phase: 'v1.0', order: 0 },
  ] };
  else if (url.endsWith('/predict')) data = { prediction: 3600, rawPrediction: 3600,
    predictionSeconds: 3600, formattedPrediction: '1 giờ', confidence: 0.82, modelVersion: 'qa-v1' };
  else if (url.includes('/api/')) data = { versions: [
    { version: 'qa-v1', active: true, uploadedAt: '2026-09-08T01:00:00Z' },
  ] };
  else return new Response('{}', { status: 503 });
  return new Response(JSON.stringify({ success: true, data }), {
    headers: { 'Content-Type': 'application/json' },
  });
};

createRoot(document.getElementById('root')!).render(<BrowserRouter><MotionConfig reducedMotion="user"><DashboardShell userName="Kiểm thử giao diện" userEmail="qa@example.test" onSignOut={() => {}}><p role="status" className="mb-4 text-sm text-muted-foreground">QA fixture — dữ liệu giả lập, không điều khiển thiết bị.</p><AiCenter /></DashboardShell></MotionConfig></BrowserRouter>);
