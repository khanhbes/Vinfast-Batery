import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildPredictionPayload, formatDurationSeconds } from '../src/components/ai-center/lab/modelLabUtils.ts';
import type { ModelTypeMeta } from '../src/components/ai-center/types.ts';

const meta = {
  inputFields: ['start_soc', 'end_soc', 'delta_soc', 'ambient_temp_c', 'temp_deviation'],
  visibleInputFields: ['start_soc', 'end_soc', 'ambient_temp_c'],
  inputSchema: { start_soc: { type: 'number', min: 0, max: 100 }, end_soc: { type: 'number', min: 0, max: 100 }, ambient_temp_c: { type: 'number', min: -30, max: 60 } },
  derivedFields: { delta_soc: { formula: 'end_soc - start_soc' }, temp_deviation: { formula: 'abs(ambient_temp_c - 27)' } },
} as ModelTypeMeta;
const valid = { start_soc: 20, end_soc: 80, ambient_temp_c: 30 };
test('valid values generate expected derived inputs', () => assert.deepEqual(buildPredictionPayload(meta, valid), { ...valid, delta_soc: 60, temp_deviation: 3 }));
for (const bad of ['', ' ', '12invalid', NaN, Infinity, -1, 101]) {
  test(`reject invalid SOC ${String(bad)}`, () => assert.throws(() => buildPredictionPayload(meta, { ...valid, start_soc: bad })));
}
test('reject target below current SOC', () => assert.throws(() => buildPredictionPayload(meta, { ...valid, end_soc: 10 })));
test('preserve valid zero', () => assert.equal(buildPredictionPayload(meta, { ...valid, start_soc: 0 }).start_soc, 0));
test('reject fractional integer rather than truncating', () => assert.throws(() => buildPredictionPayload({ inputFields: ['n'], inputSchema: { n: { type: 'integer' } } } as ModelTypeMeta, { n: '1.5' })));
test('reject unsupported formula instead of fabricating zero', () => assert.throws(() => buildPredictionPayload({ ...meta, derivedFields: { delta_soc: { formula: 'unsupported' } } }, valid)));
test('reject invalid category', () => assert.throws(() => buildPredictionPayload({ inputFields: ['mode'], inputSchema: { mode: { type: 'string', enum: ['normal'] } } } as ModelTypeMeta, { mode: 'unknown' })));
test('duration formatting remains finite', () => { assert.equal(formatDurationSeconds(3600), '1 hour'); assert.equal(formatDurationSeconds(Infinity), '—'); });
