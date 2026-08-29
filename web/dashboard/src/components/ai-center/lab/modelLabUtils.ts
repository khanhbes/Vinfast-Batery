import { ModelTypeMeta } from '../types';

/**
 * Builds the final JSON payload for prediction by merging visible user inputs
 * and evaluating derived/hidden fields.
 */
export function buildPredictionPayload(
  meta: ModelTypeMeta,
  inputState: Record<string, any>
): Record<string, any> {
  const payload: Record<string, any> = {};

  // 1. Copy & normalize visible/known inputs
  const allFields = meta.inputFields || [];
  const schema = meta.inputSchema || {};

  for (const field of allFields) {
    if (field in inputState) {
      const raw = inputState[field];
      const fieldSchema = schema[field];
      if (fieldSchema?.type === 'integer') {
        const num = parseInt(String(raw), 10);
        payload[field] = isNaN(num) ? 0 : num;
      } else if (fieldSchema?.type === 'number') {
        const num = parseFloat(String(raw));
        payload[field] = isNaN(num) ? 0 : num;
      } else {
        payload[field] = raw;
      }
    }
  }

  // 2. Compute derived fields
  if (meta.derivedFields) {
    for (const [derivedKey, spec] of Object.entries(meta.derivedFields)) {
      if (spec.formula) {
        // Evaluate known formula patterns safely
        if (spec.formula === 'end_soc - start_soc') {
          const end = Number(payload.end_soc ?? inputState.end_soc ?? 0);
          const start = Number(payload.start_soc ?? inputState.start_soc ?? 0);
          payload[derivedKey] = Math.max(0, end - start);
        } else if (spec.formula.includes('ambient_temp_c')) {
          const temp = Number(payload.ambient_temp_c ?? inputState.ambient_temp_c ?? 27);
          payload[derivedKey] = Math.abs(temp - 27);
        } else {
          payload[derivedKey] = spec.default ?? 0;
        }
      } else if (spec.default !== undefined) {
        payload[derivedKey] = spec.default;
      }
    }
  }

  // 3. Ensure any missing required input fields have fallbacks from sampleInput
  for (const field of allFields) {
    if (payload[field] === undefined) {
      const sampleVal = meta.sampleInput?.[field];
      if (sampleVal !== undefined) {
        payload[field] = sampleVal;
      } else {
        payload[field] = 0;
      }
    }
  }

  return payload;
}

/**
 * Formats duration in seconds to "X giờ Y phút" or "X phút".
 */
export function formatDurationSeconds(seconds: number): string {
  if (isNaN(seconds) || seconds <= 0) return '0 phút';
  const totalMins = Math.round(seconds / 60);
  const hours = Math.floor(totalMins / 60);
  const mins = totalMins % 60;
  if (hours > 0) {
    return mins > 0 ? `${hours} giờ ${mins} phút` : `${hours} giờ`;
  }
  return `${mins} phút`;
}
