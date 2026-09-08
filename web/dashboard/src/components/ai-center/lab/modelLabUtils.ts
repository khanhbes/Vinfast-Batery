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
  const fields = meta.inputFields || [];
  const schema = meta.inputSchema || {};
  const visible = meta.visibleInputFields?.length ? meta.visibleInputFields : fields;

  for (const field of fields) {
    if (meta.derivedFields?.[field]) continue;
    const raw = field in inputState ? inputState[field]
      : !visible.includes(field) ? meta.sampleInput?.[field] : undefined;
    const definition = schema[field];
    const label = definition?.label || field;
    if (raw === undefined || raw === null || String(raw).trim() === '') {
      throw new Error(`Nhập giá trị cho ${label}.`);
    }
    if (definition?.type === 'number' || definition?.type === 'integer') {
      const value = Number(raw);
      if (!Number.isFinite(value) || (definition.type === 'integer' && !Number.isInteger(value))) {
        throw new Error(`${label} phải là ${definition.type === 'integer' ? 'số nguyên' : 'số hữu hạn'} hợp lệ.`);
      }
      payload[field] = value;
    } else {
      payload[field] = raw;
    }
  }

  for (const [field, spec] of Object.entries(meta.derivedFields || {})) {
    if (spec.formula === 'end_soc - start_soc') {
      const end = Number(payload.end_soc);
      const start = Number(payload.start_soc);
      if (!Number.isFinite(end) || !Number.isFinite(start) || end <= start) {
        throw new Error('SOC kết thúc phải lớn hơn SOC bắt đầu.');
      }
      payload[field] = end - start;
    } else if (spec.formula === 'abs(ambient_temp_c - 27)') {
      const temperature = Number(payload.ambient_temp_c);
      if (!Number.isFinite(temperature)) throw new Error('Nhiệt độ môi trường không hợp lệ.');
      payload[field] = Math.abs(temperature - 27);
    } else if (!spec.formula && spec.default !== undefined) {
      payload[field] = spec.default;
    } else {
      throw new Error(`Chưa hỗ trợ công thức của ${field}. Không gửi giá trị thay thế.`);
    }
  }

  for (const field of fields) {
    const value = payload[field];
    const definition = schema[field];
    const label = definition?.label || field;
    if (value === undefined || (typeof value === 'number' && !Number.isFinite(value))) throw new Error(`Thiếu hoặc sai giá trị ${label}.`);
    if (definition?.min !== undefined && Number(value) < definition.min) throw new Error(`${label} phải ≥ ${definition.min}.`);
    if (definition?.max !== undefined && Number(value) > definition.max) throw new Error(`${label} phải ≤ ${definition.max}.`);
    if (definition?.enum && !(definition.enum as (string | number)[]).includes(value)) throw new Error(`Chọn giá trị hợp lệ cho ${label}.`);
  }
  return payload;
}

/**
 * Formats duration in seconds to "X giờ Y phút" or "X phút".
 */
export function formatDurationSeconds(seconds: number): string {
  if (!Number.isFinite(seconds)) return '—';
  if (seconds <= 0) return '0 phút';
  const totalMins = Math.round(seconds / 60);
  const hours = Math.floor(totalMins / 60);
  const mins = totalMins % 60;
  if (hours > 0) {
    return mins > 0 ? `${hours} giờ ${mins} phút` : `${hours} giờ`;
  }
  return `${mins} phút`;
}
