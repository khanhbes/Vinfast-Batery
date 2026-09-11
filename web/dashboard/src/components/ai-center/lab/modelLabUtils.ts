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
      throw new Error(`Enter a value for ${label}.`);
    }
    if (definition?.type === 'number' || definition?.type === 'integer') {
      const value = Number(raw);
      if (!Number.isFinite(value) || (definition.type === 'integer' && !Number.isInteger(value))) {
        throw new Error(`${label} must be a valid ${definition.type === 'integer' ? 'integer' : 'finite number'}.`);
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
        throw new Error('Ending SOC must be greater than starting SOC.');
      }
      payload[field] = end - start;
    } else if (spec.formula === 'abs(ambient_temp_c - 27)') {
      const temperature = Number(payload.ambient_temp_c);
      if (!Number.isFinite(temperature)) throw new Error('Ambient temperature is invalid.');
      payload[field] = Math.abs(temperature - 27);
    } else if (!spec.formula && spec.default !== undefined) {
      payload[field] = spec.default;
    } else {
      throw new Error(`No formula is available for ${field}. No substitute value will be sent.`);
    }
  }

  for (const field of fields) {
    const value = payload[field];
    const definition = schema[field];
    const label = definition?.label || field;
    if (value === undefined || (typeof value === 'number' && !Number.isFinite(value))) throw new Error(`Missing or invalid value for ${label}.`);
    if (definition?.min !== undefined && Number(value) < definition.min) throw new Error(`${label} must be at least ${definition.min}.`);
    if (definition?.max !== undefined && Number(value) > definition.max) throw new Error(`${label} must be at most ${definition.max}.`);
    if (definition?.enum && !(definition.enum as (string | number)[]).includes(value)) throw new Error(`Select a valid value for ${label}.`);
  }
  return payload;
}

/**
 * Formats duration in seconds to "X hours Y minutes" or "X minutes".
 */
export function formatDurationSeconds(seconds: number): string {
  if (!Number.isFinite(seconds)) return '—';
  if (seconds <= 0) return '0 minutes';
  const totalMins = Math.round(seconds / 60);
  const hours = Math.floor(totalMins / 60);
  const mins = totalMins % 60;
  if (hours > 0) {
    const hoursLabel = `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
    const minutesLabel = `${mins} ${mins === 1 ? 'minute' : 'minutes'}`;
    return mins > 0 ? `${hoursLabel} ${minutesLabel}` : hoursLabel;
  }
  return `${mins} ${mins === 1 ? 'minute' : 'minutes'}`;
}
