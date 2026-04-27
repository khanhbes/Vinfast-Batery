import { auth } from './firebase.js'

const BASE = ''  // same origin via proxy
const RETRYABLE_METHODS = new Set(['GET', 'HEAD'])
const MAX_RETRIES = 2

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function emitPortalError(message) {
  window.dispatchEvent(new CustomEvent('vf:error', { detail: { message } }))
}

function emitPortalSuccess(message) {
  window.dispatchEvent(new CustomEvent('vf:success', { detail: { message } }))
}

async function getToken() {
  const user = auth.currentUser
  if (!user) return null
  return user.getIdToken()
}

async function apiFetch(path, options = {}) {
  const token = await getToken()
  const headers = { 'Content-Type': 'application/json', ...options.headers }
  if (token) headers['Authorization'] = `Bearer ${token}`

  const method = (options.method || 'GET').toUpperCase()
  const canRetry = RETRYABLE_METHODS.has(method)
  let lastError = null

  try {
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
      try {
        const res = await fetch(`${BASE}${path}`, { ...options, headers })
        const shouldRetryStatus = canRetry && res.status >= 500 && attempt < MAX_RETRIES
        if (shouldRetryStatus) {
          await sleep(350 * (attempt + 1))
          continue
        }

        const contentType = res.headers.get('content-type') || ''
        const isJson = contentType.includes('application/json')
        const body = isJson ? await res.json() : await res.text()

        if (!res.ok) {
          const message = isJson
            ? (body?.error || body?.message || `HTTP ${res.status}`)
            : `HTTP ${res.status}`
          throw new Error(message)
        }

        if (isJson && body?.success === false) {
          const message = body.error || body.message || 'Yeu cau that bai'
          throw new Error(message)
        }

        return body
      } catch (err) {
        lastError = err
        const isLastAttempt = attempt >= MAX_RETRIES
        if (!canRetry || isLastAttempt) {
          throw err
        }
        await sleep(350 * (attempt + 1))
      }
    }
    throw lastError || new Error('Khong the ket noi den server')
  } catch (error) {
    const message = error?.message || 'Khong the ket noi den server'
    emitPortalError(message)
    throw error
  }
}

// ── Auth ──
export const authMe = () => apiFetch('/api/auth/me')

// ── Admin CRUD ──
export const adminList = (entity, params = {}) => {
  const qs = new URLSearchParams(params).toString()
  return apiFetch(`/api/admin/${entity}${qs ? '?' + qs : ''}`)
}
export const adminGet = (entity, id) => apiFetch(`/api/admin/${entity}/${id}`)
export const adminCreate = (entity, data) =>
  apiFetch(`/api/admin/${entity}`, { method: 'POST', body: JSON.stringify(data) })
export const adminUpdate = (entity, id, data) =>
  apiFetch(`/api/admin/${entity}/${id}`, { method: 'PUT', body: JSON.stringify(data) })
export const adminDelete = (entity, id) =>
  apiFetch(`/api/admin/${entity}/${id}`, { method: 'DELETE' })
export const adminRestore = (entity, id) =>
  apiFetch(`/api/admin/${entity}/${id}/restore`, { method: 'POST' })
export const adminBulkDelete = (entity, ids) =>
  apiFetch(`/api/admin/${entity}/bulk-delete`, { method: 'POST', body: JSON.stringify({ ids }) })

// ── Users ──
export const adminUsers = () => apiFetch('/api/admin/users')
export const setAdmin = (email) =>
  apiFetch('/api/auth/set-admin', { method: 'POST', body: JSON.stringify({ email }) })

// ── Import/Export ──
export const adminExport = (entity, format = 'json', params = {}) => {
  const qs = new URLSearchParams({ entity, format, ...params }).toString()
  return apiFetch(`/api/admin/export?${qs}`)
}
export const adminImport = (entity, data, mode = 'upsert') =>
  apiFetch(`/api/admin/import?entity=${entity}&mode=${mode}`, {
    method: 'POST', body: JSON.stringify({ data }),
  })

// ── Audit ──
export const adminAuditLogs = () => apiFetch('/api/admin/audit-logs')
export const adminResetAll = () => apiFetch('/api/admin/reset-all?force=true', { method: 'POST' })

// ── AI ──
export const aiNormalize = (records) =>
  apiFetch('/api/admin/ai/normalize-dataset', { method: 'POST', body: JSON.stringify({ records }) })
export const aiDataset = (vehicleId) =>
  apiFetch(`/api/admin/ai/dataset/${encodeURIComponent(vehicleId)}`)
export const aiTrain = (vehicleId, records) =>
  apiFetch('/api/admin/ai/train', { method: 'POST', body: JSON.stringify({ vehicleId, records }) })
export const aiTest = (vehicleId, records) =>
  apiFetch('/api/admin/ai/test', { method: 'POST', body: JSON.stringify({ vehicleId, records }) })
export const aiPredict = (vehicleId, chargeLogs) =>
  apiFetch('/api/ai/predict-degradation', { method: 'POST', body: JSON.stringify({ vehicleId, chargeLogs }) })
export const aiAnalyze = (vehicleId, chargeLogs) =>
  apiFetch('/api/ai/analyze-patterns', { method: 'POST', body: JSON.stringify({ vehicleId, chargeLogs }) })
export const aiProfileStatus = (vehicleId) =>
  apiFetch(`/api/ai/profile-status/${encodeURIComponent(vehicleId)}`)
export const aiCenterStatus = () =>
  apiFetch('/api/admin/ai/status')
export const aiRefreshInsights = (vehicleId) =>
  apiFetch('/api/admin/ai/refresh-insights', { method: 'POST', body: JSON.stringify({ vehicleId }) })

// ── AI Charging Time Prediction ──
export const aiPredictChargingTime = (payload) =>
  apiFetch('/api/ai/predict-charging-time', { method: 'POST', body: JSON.stringify(payload) })


// ── AI Model Management (per-type; FastAPI via Flask proxy) ──
export const aiListTypes = () => apiFetch('/api/admin/ai/types')

export const aiListModels = (typeKey = 'soc') =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}`)

export const aiModelStatus = (typeKey = 'soc') =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/status`)

export const aiRollbackModel = (typeKey, version) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/rollback`, {
    method: 'POST',
    body: JSON.stringify({ version }),
  })

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
  })

export const aiValidateVersion = (typeKey, version) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/validate-version`, {
    method: 'POST',
    body: JSON.stringify({ version }),
  })

/// Test nhanh một version đã upload (chưa deploy) — PLAN1
export const aiTestVersion = (typeKey, version, testInput = null) =>
  apiFetch(`/api/admin/ai/models/${encodeURIComponent(typeKey)}/test-version`, {
    method: 'POST',
    body: JSON.stringify({ version, testInput }),
  })

/// Deploy một version — PLAN1
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
    const res = await fetch(`${BASE}/api/admin/ai/models/${encodeURIComponent(typeKey)}/upload`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: form,
    })
    const contentType = res.headers.get('content-type') || ''
    const isJson = contentType.includes('application/json')
    const body = isJson ? await res.json() : await res.text()
    if (!res.ok || (isJson && body?.success === false)) {
      let msg = (isJson && (body?.error || body?.message)) || `HTTP ${res.status}`
      // Handle case where error/message is an object
      if (typeof msg === 'object') {
        msg = JSON.stringify(msg)
      }
      throw new Error(msg)
    }
    return body
  } catch (err) {
    emitPortalError(err?.message || 'Upload model that bai')
    throw err
  }
}

export const aiSocStatus = () => apiFetch('/api/soc/status')

// ── Legacy ──
export const migrateLegacy = () => apiFetch('/api/admin/migrate-legacy', { method: 'POST' })

// ── Telemetry (public) ──
export const getTelemetry = (tripId) => {
  const qs = tripId ? `?trip_id=${encodeURIComponent(tripId)}` : ''
  return fetch(`${BASE}/api/telemetry${qs}`).then(async r => {
    if (!r.ok) {
      const message = `HTTP ${r.status} khi tai telemetry`
      emitPortalError(message)
      throw new Error(message)
    }
    return r.json()
  })
}
export const getChargeLogs = (vehicleId) => {
  const qs = vehicleId ? `?vehicleId=${encodeURIComponent(vehicleId)}` : ''
  return fetch(`${BASE}/api/charge-logs${qs}`).then(async r => {
    if (!r.ok) {
      const message = `HTTP ${r.status} khi tai charge logs`
      emitPortalError(message)
      throw new Error(message)
    }
    return r.json()
  })
}

export { emitPortalError, emitPortalSuccess }
