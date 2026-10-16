import { auth } from './firebase.ts'
import { requestPortal, PortalHttpError } from './lib/httpClient'

// Production normally reaches the API through the same-origin Caddy proxy.
// Accept an origin or a legacy `/api` value without producing `/api/api/...`.
const configuredApiBase = String(import.meta.env.VITE_API_BASE_URL || '').trim().replace(/\/+$/, '')
let BASE = configuredApiBase.replace(/\/api$/i, '')
if (typeof window !== 'undefined') {
  const isHttps = window.location.protocol === 'https:'
  const isNonLocalhost = window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1'
  if ((isHttps || isNonLocalhost) && (BASE.startsWith('http://localhost') || BASE.startsWith('http://127.0.0.1'))) {
    BASE = ''
  }
}

function endpointTimeout(path, method = 'GET') {
  if (/\/api\/admin\/data-snapshot(?:\?|$)/.test(path)) return 30_000
  if (/(?:import|upload|research)/i.test(path)) return 120_000
  return 15_000
}

function emitPortalError(message) {
  window.dispatchEvent(new CustomEvent('vf:error', { detail: { message } }))
}

function emitPortalSuccess(message) {
  window.dispatchEvent(new CustomEvent('vf:success', { detail: { message } }))
}

async function getToken(forceRefresh = false) {
  const user = auth.currentUser
  if (!user) return null
  return user.getIdToken(forceRefresh)
}

async function apiFetch(path, options = {}) {
  // httpClient already replays a read once on 502-504/network errors; a second
  // retry layer here sent a failing GET up to 6 times (Task 125).
  const { silent = false, retries = 0, ...requestOptions } = options
  const retryableAuth = ['GET', 'HEAD'].includes((requestOptions.method ?? 'GET').toUpperCase())
  const retryableMethods = retryableAuth // only retry idempotent methods for network errors
  let refreshed = false
  let attempt = 0
  for (;;) {
    const token = await getToken(refreshed)
    const headers = { 'Content-Type': 'application/json', ...requestOptions.headers }
    if (token) headers['Authorization'] = `Bearer ${token}`
    try {
      return await requestPortal(`${BASE}${path}`, {
        ...requestOptions,
        headers,
        timeoutMs: requestOptions.timeoutMs ?? endpointTimeout(path, requestOptions.method),
      })
    } catch (error) {
      // Retry once with a refreshed token on 401
      if (retryableAuth && !refreshed && error instanceof PortalHttpError && error.status === 401 && auth.currentUser) {
        refreshed = true
        continue
      }
      // Exponential backoff for transient network errors (5xx, timeouts, network failures)
      const isTransient = error instanceof PortalHttpError
        ? error.status >= 500
        : error?.name === 'AbortError' || error?.message?.includes('fetch')
      if (retryableMethods && isTransient && attempt < retries) {
        attempt++
        await new Promise(resolve => setTimeout(resolve, attempt * 750))
        continue
      }
      if (!silent) {
        const message = error?.message || 'The server could not be reached'
        emitPortalError(message)
      }
      throw error
    }
  }
}

// ── Auth ──
export const authMe = () => apiFetch('/api/auth/me')

export const adminAccounts = (params = {}) => {
  const query = new URLSearchParams(Object.entries(params).filter(([, value]) => value !== '' && value != null)).toString()
  return apiFetch(`/api/admin/accounts${query ? `?${query}` : ''}`)
}
export const adminAccount = (uid) => apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}`)
export const adminAccountData = (uid, params = {}) => {
  const query = new URLSearchParams(Object.entries(params).filter(([, value]) => value !== '' && value != null)).toString()
  return apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}/data${query ? `?${query}` : ''}`)
}
export const adminSetAccountStatus = (uid, status) =>
  apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}/status`, { method: 'PATCH', body: JSON.stringify({ status }) })
export const adminRevokeAccountSessions = (uid) =>
  apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}/revoke-sessions`, { method: 'POST' })
export const adminPasswordResetAudit = (uid) =>
  apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}/password-reset-audit`, { method: 'POST' })
export const adminDeleteAccount = (uid, confirmUid) =>
  apiFetch(`/api/admin/accounts/${encodeURIComponent(uid)}`, {
    method: 'DELETE', body: JSON.stringify({ confirmUid }),
  })
export const adminDataSnapshot = (limit = 50, datasets = [], force = false) => {
  const query = new URLSearchParams({ limit: String(limit) })
  if (datasets.length) query.set('datasets', datasets.join(','))
  if (force) query.set('force', '1')
  return apiFetch(`/api/admin/data-snapshot?${query}`, { silent: true })
}

// ── Global EV catalog ──
export const catalogList = (status = '') =>
  apiFetch(`/api/admin/vehicle-catalog${status ? `?status=${encodeURIComponent(status)}` : ''}`)
export const catalogGet = (catalogId) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}`)
export const catalogCreate = (data) =>
  apiFetch('/api/admin/vehicle-catalog', { method: 'POST', body: JSON.stringify(data) })
export const catalogUpdate = (catalogId, data) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}`, { method: 'PATCH', body: JSON.stringify(data) })
export const catalogPublish = (catalogId) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}/publish`, { method: 'POST' })
export const catalogArchive = (catalogId) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}/archive`, { method: 'POST' })
export const catalogRestore = (catalogId) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}/restore`, { method: 'POST' })
export const catalogResearchCreate = (data) =>
  apiFetch('/api/admin/catalog-research-jobs', { method: 'POST', body: JSON.stringify(data) })
export const catalogResearchGet = (jobId) =>
  apiFetch(`/api/admin/catalog-research-jobs/${encodeURIComponent(jobId)}`)
export const catalogManufacturerSave = (brandId, data) =>
  apiFetch(`/api/admin/vehicle-manufacturers/${encodeURIComponent(brandId)}`, { method: 'PUT', body: JSON.stringify(data) })

export async function catalogUploadMedia(catalogId, file, metadata) {
  const token = await getToken()
  const form = new FormData()
  form.append('file', file)
  Object.entries(metadata).forEach(([key, value]) => form.append(key, String(value)))
  return requestPortal(`${BASE}/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}/media`, {
    method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {}, body: form, timeoutMs: 120_000,
  })
}

export const catalogUpdateShowroom = (catalogId, data) =>
  apiFetch(`/api/admin/vehicle-catalog/${encodeURIComponent(catalogId)}/showroom`, { method: 'PUT', body: JSON.stringify(data) })

// ── Audit ──
export const adminAuditLogs = () => apiFetch('/api/admin/audit-logs')

// ── AI Model Management (per-type; FastAPI via Flask proxy) ──
export const aiListTypes = () => apiFetch('/api/admin/ai/types')

export const aiListModels = (typeKey = 'soc') =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}`)

export const aiDeleteModel = (typeKey, version) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/${encodeURIComponent(version)}`, { method: 'DELETE' })

export const aiQuickPredict = (typeKey, payload) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/predict`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })

export const aiLoadActiveModel = (typeKey) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/load-active`, {
    method: 'POST',
  })

export const aiDeactivateModel = (typeKey) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/deactivate`, {
    method: 'POST',
  });

/// Smoke-test an uploaded version before deployment — PLAN1
/** @param {string} typeKey @param {string} version @param {Record<string, unknown> | null} testInput */
export const aiTestVersion = (typeKey, version, testInput = null) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/test-version`, {
    method: 'POST',
    body: JSON.stringify({ version, testInput }),
  })

/// Deploy a version — PLAN1
export const aiDeployModel = (typeKey, version) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/deploy`, {
    method: 'POST',
    body: JSON.stringify({ version }),
  })

/**
 * Upload a model file for a given model type.
 * @param {string} typeKey
 * @param {File} file
 * @param {string} version
 * @param {string} note
 */
export async function aiUploadModel(typeKey, file, version, note = '', skipSmokeTest = false) {
  const token = await getToken()
  const form = new FormData()
  form.append('file', file)
  form.append('version', version)
  form.append('note', note)
  if (skipSmokeTest) form.append('skipSmokeTest', 'true')

  try {
    return await requestPortal(`${BASE}/api/admin/ai/models/${encodeURIComponent(typeKey)}/upload`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: form,
      timeoutMs: 120_000,
    })
  } catch (err) {
    emitPortalError(err?.message || 'Model upload failed')
    throw err
  }
}

// ── Shelly Connection Codes (Admin) ──
export const adminShellyDevices = () => apiFetch('/api/admin/shelly-devices', { silent: true })
export const adminSaveShellyDevice = (data) =>
  apiFetch('/api/admin/shelly-devices', { method: 'POST', body: JSON.stringify(data) })
export const adminDeleteShellyDevice = (deviceId) =>
  apiFetch('/api/admin/shelly-devices/' + encodeURIComponent(deviceId), { method: 'DELETE' })
export const adminGenerateCodeForDevice = (deviceId, data = {}) =>
  apiFetch('/api/admin/shelly-devices/' + encodeURIComponent(deviceId) + '/generate-code', { method: 'POST', body: JSON.stringify(data) })
export { emitPortalError, emitPortalSuccess }

// BatteryBot v2 knowledge (Task 124)
export const adminAssistantKnowledge = () => apiFetch('/api/admin/assistant/knowledge', { silent: true })
export const adminSaveAssistantKnowledge = (id, data) =>
  apiFetch('/api/admin/assistant/knowledge/' + encodeURIComponent(id), { method: 'PUT', body: JSON.stringify(data) })
export const adminDeleteAssistantKnowledge = (id) =>
  apiFetch('/api/admin/assistant/knowledge/' + encodeURIComponent(id), { method: 'DELETE' })
