async (page) => {
  const errors = [];
  await page.unrouteAll();
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = route.request().url();
    if (!url.startsWith('http://127.0.0.1:3011/')) return route.abort();
    if (!url.includes('/api/')) return route.continue();
    const meta = {
      key: 'charging_time', label: 'Dự đoán thời gian sạc', description: 'Dữ liệu giả lập để kiểm tra bố cục và thao tác.',
      icon: 'Clock', accent: 'emerald', group: 'survival', phase: 'v1.0', status: 'ready',
      deploymentStatus: 'deployed', outputKind: 'scalar', displayUnit: 'time', outputUnit: 's',
      inputFields: ['start_soc', 'end_soc', 'delta_soc'], visibleInputFields: ['start_soc', 'end_soc'],
      sampleInput: { start_soc: 20, end_soc: 80 },
      inputSchema: { start_soc: { type: 'number', min: 0, max: 100, label: 'SOC bắt đầu' }, end_soc: { type: 'number', min: 0, max: 100, label: 'SOC kết thúc' } },
      derivedFields: { delta_soc: { formula: 'end_soc - start_soc' } },
      runtimeStatus: { isLoaded: true, isPredictable: true, activeVersion: 'qa-v1', versionsCount: 1 },
    };
    let data = {};
    if (url.endsWith('/types')) data = { types: [meta], groups: [{ key: 'survival', label: 'Pin & sạc', subtitle: 'Fixture kiểm thử', phase: 'v1.0', order: 0 }] };
    else if (url.endsWith('/predict')) data = { prediction: 3600, rawPrediction: 3600, predictionSeconds: 3600, formattedPrediction: '1 giờ', confidence: 0.82, modelVersion: 'qa-v1' };
    else data = { versions: [{ version: 'qa-v1', active: true, uploadedAt: '2026-09-08T01:00:00Z' }] };
    return route.fulfill({ json: { success: true, data } });
  });
  await page.goto('http://127.0.0.1:3011/output/playwright/preview.html');
  await page.getByRole('button', { name: 'Mở phòng thử nghiệm Dự đoán thời gian sạc' }).waitFor();
  return { title: await page.title(), errors };
}
