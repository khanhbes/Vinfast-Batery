export class PortalHttpError extends Error {
  constructor(message: string, public status = 0) { super(message); }
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

export async function requestPortal(path: string, options: RequestInit = {}, dependencies: {
  fetch?: typeof fetch; timeoutMs?: number; pause?: (ms: number) => Promise<void>;
} = {}): Promise<any> {
  const send = dependencies.fetch ?? fetch;
  const pause = dependencies.pause ?? (ms => new Promise(resolve => setTimeout(resolve, ms)));
  const retryable = ['GET', 'HEAD'].includes((options.method ?? 'GET').toUpperCase());
  const timeoutMs = dependencies.timeoutMs ?? (retryable ? 15000 : 120000);
  for (let attempt = 0; ; attempt++) {
    const controller = new AbortController();
    const cancel = () => controller.abort();
    options.signal?.addEventListener('abort', cancel, { once: true });
    if (options.signal?.aborted) cancel();
    const timer = setTimeout(cancel, timeoutMs);
    try {
      const response = await send(path, { ...options, signal: controller.signal });
      if (!response.ok) throw new PortalHttpError(statusMessage(response.status), response.status);
      const contentType = response.headers.get('content-type') ?? '';
      if (contentType.includes('text/csv')) return await response.text();
      if (!contentType.includes('application/json')) throw new PortalHttpError('The server returned an invalid response. Refresh the page.');
      const body = await response.json();
      if (!body || typeof body !== 'object') throw new PortalHttpError('The server returned invalid data.');
      if (body.success === false) throw new PortalHttpError('The server did not confirm this action. Refresh the data before trying again.');
      return body;
    } catch (error) {
      const aborted = controller.signal.aborted;
      const transient = error instanceof PortalHttpError ? [502, 503, 504].includes(error.status) : error instanceof TypeError;
      if (retryable && transient && !aborted && attempt < 2) {
        clearTimeout(timer);
        await pause(350 * (attempt + 1));
        continue;
      }
      if (error instanceof PortalHttpError) throw error;
      throw new PortalHttpError(aborted
        ? 'The request was cancelled or timed out. Check current status before trying again.'
        : 'No valid response was received. Check the connection and try again.');
    } finally {
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', cancel);
    }
  }
}
