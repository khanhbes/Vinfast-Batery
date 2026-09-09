import { test } from 'node:test';
import assert from 'node:assert/strict';
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
  assert.equal(calls, 3);
});

test('mutation is never automatically repeated after network failure', async () => {
  let calls = 0;
  await assert.rejects(requestPortal('/fixture', { method: 'POST' }, { fetch: async () => { calls++; throw new TypeError('network'); } }));
  assert.equal(calls, 1);
});

test('timeout stops a request without replaying a mutation', async () => {
  await assert.rejects(requestPortal('/fixture', { method: 'POST' }, { timeoutMs: 5, fetch: async (_path, options) => new Promise((_resolve, reject) => {
    options?.signal?.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }) }), /quá thời gian/);
});

test('HTML response is not treated as successful API data', async () => {
  await assert.rejects(requestPortal('/fixture', {}, { fetch: async () => new Response('<html>proxy error</html>', { headers: { 'content-type': 'text/html' } }) }), /không hợp lệ/);
});

test('upload validates supported format, size, and stable version', () => {
  assert.equal(validateModelUpload({ name: 'model.ONNX', size: 100 }, '2026.09-a'), null);
  for (const file of [null, { name: 'model.pkl', size: 10 }, { name: 'model.onnx', size: 0 }, { name: 'model.tflite', size: 64 * 1024 * 1024 + 1 }]) assert.ok(validateModelUpload(file, 'v1'));
  assert.ok(validateModelUpload({ name: 'model.onnx', size: 10 }, '../v1'));
});
