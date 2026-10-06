import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { requestPortal } from '../src/lib/httpClient.ts';
import { isVerifiedAdmin } from '../src/lib/portalAccess.ts';
import { validateModelUpload } from '../src/components/ai-center/uploadPolicy.ts';
import { normalizePercentage } from '../src/lib/dataNormalization.ts';

test('missing or malformed battery percentages never become 100 or 0', () => {
  for (const value of [null, undefined, '', ' ', '12bad', NaN, Infinity, -1, 101]) {
    assert.equal(normalizePercentage(value), null);
  }
  assert.equal(normalizePercentage(0), 0);
  assert.equal(normalizePercentage('68.5'), 68.5);
  assert.equal(normalizePercentage(100), 100);
});

test('only backend-verified admin for the current identity is accepted', () => {
  assert.equal(isVerifiedAdmin({ success: true, data: { uid: 'a', role: 'admin' } }, 'a'), true);
  for (const response of [null, {}, { success: false, data: { uid: 'a', role: 'admin' } },
    { success: true, data: { uid: 'b', role: 'admin' } }, { success: true, data: { uid: 'a', role: 'user' } }]) {
    assert.equal(isVerifiedAdmin(response, 'a'), false);
  }
});

for (const status of [400, 401, 403, 409, 429, 500]) {
  test(`HTTP ${status} is not retried and raw details are not exposed`, async () => {
    let calls = 0;
    await assert.rejects(requestPortal('/fixture', {}, { fetch: async () => {
      calls++; return new Response('private-key/internal/path', { status });
    }, pause: async () => {} }), error => {
      assert.ok(error instanceof Error);
      assert.doesNotMatch(error.message, /private-key|internal\/path/);
      return true;
    });
    assert.equal(calls, 1);
  });
}

test('transient read retries are bounded', async () => {
  let calls = 0;
  await assert.rejects(requestPortal('/fixture', {}, { fetch: async () => { calls++; return new Response('', { status: 503 }); }, pause: async () => {} }));
  assert.equal(calls, 2);
});

test('mutation is never automatically repeated after network failure', async () => {
  let calls = 0;
  await assert.rejects(requestPortal('/fixture', { method: 'POST' }, { fetch: async () => { calls++; throw new TypeError('network'); } }));
  assert.equal(calls, 1);
});

test('timeout stops a request without replaying a mutation', async () => {
  await assert.rejects(requestPortal('/fixture', { method: 'POST' }, { timeoutMs: 5, fetch: async (_path, options) => new Promise((_resolve, reject) => {
    options?.signal?.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }) }), /timed out/);
});

test('HTML response is not treated as successful API data', async () => {
  await assert.rejects(requestPortal('/fixture', {}, { fetch: async () => new Response('<html>proxy error</html>', { headers: { 'content-type': 'text/html' } }) }), /invalid response/);
});

test('JSON error fields never expose provider secrets or internal details', async () => {
  await assert.rejects(requestPortal('/fixture', { method: 'POST' }, { fetch: async () => new Response(JSON.stringify({
    success: false, error: 'private-key/internal/path', userMessage: 'private-user-id', code: 'BAD_REQUEST', requestId: 'qa-request',
  }), { status: 400, headers: { 'content-type': 'application/json' } }) }), error => {
    assert.ok(error instanceof Error);
    assert.doesNotMatch(error.message, /private-key|internal\/path|private-user-id/);
    return true;
  });
});

test('normal-mode shortcuts and data rows cannot open developer-only routes', () => {
  const source = readFileSync(new URL('../src/pages/Dashboard.tsx', import.meta.url), 'utf8');
  assert.match(source, /developMode && <div className="mt-6/);
  assert.match(source, /disabled={!developMode && metric.label !== 'Tài khoản'}/);
  assert.match(source, /type="button" disabled={!developMode} onClick/);
});

test('core Shelly page has no lazy chunk and lazy routes have recovery boundary', () => {
  const source = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8');
  assert.match(source, /import ShellyGateway from/);
  assert.doesNotMatch(source, /const ShellyGateway = lazy/);
  assert.match(source, /<PageLoadBoundary/);
  assert.match(source, /fallback={<PageLoading/);
});

test('Shelly setup exposes a named 48px credential toggle and error is not empty', () => {
  const source = readFileSync(new URL('../src/pages/ShellyGateway.tsx', import.meta.url), 'utf8');
  assert.match(source, /aria-label={showPassword/);
  assert.match(source, /min-h-12 min-w-12/);
  assert.match(source, /devices.length === 0 && loadError \? null/);
  assert.doesNotMatch(source, /toast\.error\([^\n]*err/);
});

test('upload validates supported format, size, and stable version', () => {
  assert.equal(validateModelUpload({ name: 'model.ONNX', size: 100 }, '2026.09-a'), null);
  for (const file of [null, { name: 'model.pkl', size: 10 }, { name: 'model.onnx', size: 0 }, { name: 'model.tflite', size: 64 * 1024 * 1024 + 1 }]) assert.ok(validateModelUpload(file, 'v1'));
  assert.ok(validateModelUpload({ name: 'model.onnx', size: 10 }, '../v1'));
});

test('workspace fills available width and Shelly model label stays concise', () => {
  const shell = readFileSync(new URL('../src/components/layout/DashboardShell.tsx', import.meta.url), 'utf8');
  const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8');
  const topbar = readFileSync(new URL('../src/components/layout/Topbar.tsx', import.meta.url), 'utf8');
  const shelly = readFileSync(new URL('../src/pages/ShellyGateway.tsx', import.meta.url), 'utf8');
  assert.doesNotMatch(shell, /max-w-7xl/);
  assert.match(css, /\.dashboard-shell \{ display: flex; width: 100%/);
  assert.match(topbar, /'\/shelly': 'Thiết bị Shelly'/);
  assert.match(shelly, /<option value="S3PL-00112EU">Shelly Plug S Gen3<\/option>/);
  assert.match(shelly, /Mã model: S3PL-00112EU/);
});
