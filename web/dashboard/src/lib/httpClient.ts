export class PortalHttpError extends Error {
  constructor(
    message: string,
    public status = 0,
    public code = '',
    public data: Record<string, unknown> = {},
    public requestId = '',
  ) { super(message); }
}

export interface PortalRequestOptions extends RequestInit {
  /** Per-endpoint budget. This value is deliberately never passed to fetch. */
  timeoutMs?: number;
}

function statusMessage(status: number): string {
  if (status === 401) return 'Your session is invalid. Sign in again.';
  if (status === 403) return 'This account is not allowed to perform that action.';
  if (status === 409) return 'The data changed or this version already exists. Refresh before trying again.';
  if (status === 429) return 'Too many requests. Wait a moment and try again.';
  if (status === 413) return 'The uploaded file or payload exceeds the allowed size.';
  if (status >= 500) return 'The server could not process this request. Please try again later.';
  return 'The request is invalid. Check the input and try again.';
}

function errorBodyMessage(body: unknown, status: number): PortalHttpError {
  const data = body && typeof body === 'object' ? body as Record<string, unknown> : {};
  const raw = data.error;
  const message = typeof raw === 'string' && raw.trim()
    ? raw
    : typeof raw === 'object' && raw && typeof (raw as Record<string, unknown>).message === 'string'
      ? String((raw as Record<string, unknown>).message)
      : statusMessage(status);
  return new PortalHttpError(message, status, String(data.code ?? ''), data, String(data.requestId ?? ''));
}

export async function requestPortal(path: string, options: PortalRequestOptions = {}, dependencies: {
  fetch?: typeof fetch; timeoutMs?: number; pause?: (ms: number) => Promise<void>;
} = {}): Promise<any> {
  const send = dependencies.fetch ?? fetch;
  const pause = dependencies.pause ?? (ms => new Promise(resolve => setTimeout(resolve, ms)));
  const retryable = ['GET', 'HEAD'].includes((options.method ?? 'GET').toUpperCase());
  const timeoutMs = dependencies.timeoutMs ?? options.timeoutMs ?? (retryable ? 15000 : 120000);
  const { timeoutMs: _timeoutMs, signal: externalSignal, ...fetchOptions } = options;
  for (let attempt = 0; ; attempt++) {
    const controller = new AbortController();
    const cancel = () => controller.abort();
    let timedOut = false;
    externalSignal?.addEventListener('abort', cancel, { once: true });
    if (externalSignal?.aborted) cancel();
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
    try {
      const response = await send(path, { ...fetchOptions, signal: controller.signal });
      const contentType = response.headers.get('content-type') ?? '';
      if (contentType.includes('text/csv')) return await response.text();
      if (!contentType.includes('application/json')) {
        if (!response.ok) throw new PortalHttpError(statusMessage(response.status), response.status);
        throw new PortalHttpError('The server returned an invalid response. Refresh the page.');
      }
      const body = await response.json();
      if (!response.ok) throw errorBodyMessage(body, response.status);
      if (!body || typeof body !== 'object') throw new PortalHttpError('The server returned invalid data.');
      if (body.success === false) throw errorBodyMessage(body, response.status);
      return body;
    } catch (error) {
      const aborted = controller.signal.aborted;
      const transient = error instanceof PortalHttpError ? [502, 503, 504].includes(error.status) : error instanceof TypeError;
      // A read can be replayed once for a gateway/network failure. Never
      // replay cancellation, auth failures, or a user mutation.
      if (retryable && transient && !aborted && attempt < 1) {
        clearTimeout(timer);
        await pause(350 * (attempt + 1));
        continue;
      }
      if (error instanceof PortalHttpError) throw error;
      throw new PortalHttpError(timedOut
        ? 'The request timed out. Check the connection and try again.'
        : externalSignal?.aborted
          ? 'The request was cancelled.'
        : 'No valid response was received. Check the connection and try again.');
    } finally {
      clearTimeout(timer);
      externalSignal?.removeEventListener('abort', cancel);
    }
  }
}
