import { useState, useEffect, useCallback } from 'react'
import { auth } from './firebase.js'
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  signOut,
  onAuthStateChanged,
} from 'firebase/auth'
import * as api from './api.js'
import TelemetryDashboard from './TelemetryDashboard.jsx'

// ═══════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ═══════════════════════════════════════════════════════════════
function mapFirebaseAuthError(err) {
  const code = err?.code || ''
  switch (code) {
    case 'auth/operation-not-allowed':
      return 'Đăng nhập Email/Password chưa được bật trên Firebase. Vào Firebase Console > Authentication > Sign-in method > bật Email/Password.'
    case 'auth/invalid-credential':
    case 'auth/invalid-email':
    case 'auth/user-not-found':
    case 'auth/wrong-password':
      return 'Email hoặc mật khẩu không đúng.'
    case 'auth/email-already-in-use':
      return 'Email này đã được đăng ký.'
    case 'auth/weak-password':
      return 'Mật khẩu quá yếu. Hãy dùng ít nhất 6 ký tự.'
    case 'auth/too-many-requests':
      return 'Bạn thử quá nhiều lần. Vui lòng đợi rồi thử lại.'
    default:
      return err?.message || 'Xác thực thất bại.'
  }
}

function LoginScreen() {
  const [mode, setMode] = useState('login') // login | signup
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    setSuccess('')
    try {
      if (mode === 'signup') {
        if (password.length < 6) {
          setError('Mật khẩu cần ít nhất 6 ký tự.')
          return
        }
        if (password !== confirmPassword) {
          setError('Mật khẩu xác nhận không khớp.')
          return
        }
        await createUserWithEmailAndPassword(auth, email.trim(), password)
        setSuccess('Đăng ký thành công. Nếu chưa có quyền Admin, tài khoản sẽ bị chặn ở bước vào portal.')
      } else {
        await signInWithEmailAndPassword(auth, email.trim(), password)
      }
    } catch (err) {
      setError(mapFirebaseAuthError(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-[var(--color-bg)] flex items-center justify-center p-4">
      <form onSubmit={handleSubmit} className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-2xl p-8 w-full max-w-sm space-y-5">
        <div className="text-center">
          <div className="text-3xl mb-2">⚡</div>
          <h1 className="text-lg font-bold text-[var(--color-text)]">VinFast Admin Portal</h1>
          <p className="text-xs text-[var(--color-text-dim)] mt-1">
            {mode === 'login' ? 'Đăng nhập bằng tài khoản Admin' : 'Tạo tài khoản mới'}
          </p>
        </div>
        {error && <div className="bg-[var(--color-red)]/10 border border-[var(--color-red)]/30 rounded-lg p-3 text-xs text-[var(--color-red)]">{error}</div>}
        {success && <div className="bg-[var(--color-accent)]/10 border border-[var(--color-accent)]/30 rounded-lg p-3 text-xs text-[var(--color-accent)]">{success}</div>}
        <div>
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Email</label>
          <input type="email" value={email} onChange={e => setEmail(e.target.value)} required
            className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2.5 text-sm text-[var(--color-text)] focus:outline-none focus:border-[var(--color-accent)]" />
        </div>
        <div>
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Mật khẩu</label>
          <input type="password" value={password} onChange={e => setPassword(e.target.value)} required
            className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2.5 text-sm text-[var(--color-text)] focus:outline-none focus:border-[var(--color-accent)]" />
        </div>
        {mode === 'signup' && (
          <div>
            <label className="block text-xs text-[var(--color-text-dim)] mb-1">Xác nhận mật khẩu</label>
            <input type="password" value={confirmPassword} onChange={e => setConfirmPassword(e.target.value)} required
              className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2.5 text-sm text-[var(--color-text)] focus:outline-none focus:border-[var(--color-accent)]" />
          </div>
        )}
        <button type="submit" disabled={loading}
          className="w-full py-2.5 rounded-lg bg-[var(--color-accent)] text-black font-semibold text-sm hover:opacity-90 disabled:opacity-50 cursor-pointer disabled:cursor-not-allowed">
          {loading
            ? (mode === 'login' ? '⏳ Đang đăng nhập...' : '⏳ Đang đăng ký...')
            : (mode === 'login' ? 'Đăng nhập' : 'Đăng ký')}
        </button>
        <button
          type="button"
          onClick={() => {
            setMode(prev => prev === 'login' ? 'signup' : 'login')
            setError('')
            setSuccess('')
          }}
          className="w-full py-2 rounded-lg border border-[var(--color-border)] text-[var(--color-text-dim)] text-sm hover:bg-[var(--color-surface-hover)] cursor-pointer transition-colors"
        >
          {mode === 'login' ? 'Chưa có tài khoản? Đăng ký' : 'Đã có tài khoản? Đăng nhập'}
        </button>
      </form>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// SIDEBAR
// ═══════════════════════════════════════════════════════════════
const TABS = [
  { id: 'dashboard', icon: '📊', label: 'Dashboard' },
  { id: 'data', icon: '🗃️', label: 'Data Manager' },
  { id: 'ai', icon: '🤖', label: 'AI Lab' },
  { id: 'import', icon: '📦', label: 'Import/Export' },
  { id: 'guide', icon: '📖', label: 'Hướng dẫn' },
]

function ToastCenter({ items, onClose }) {
  return (
    <div className="fixed top-4 right-4 z-[70] space-y-2 w-[min(92vw,380px)]">
      {items.map(item => (
        <div
          key={item.id}
          className={`portal-toast rounded-xl border px-4 py-3 shadow-lg backdrop-blur-sm ${
            item.type === 'error'
              ? 'bg-[var(--color-red)]/12 border-[var(--color-red)]/30 text-[var(--color-red)]'
              : 'bg-[var(--color-accent)]/12 border-[var(--color-accent)]/30 text-[var(--color-accent)]'
          }`}
        >
          <div className="flex items-start gap-3">
            <span className="text-sm mt-0.5">{item.type === 'error' ? '⚠️' : '✅'}</span>
            <div className="text-sm leading-5 flex-1">{item.message}</div>
            <button onClick={() => onClose(item.id)} className="text-xs opacity-70 hover:opacity-100 cursor-pointer">✕</button>
          </div>
        </div>
      ))}
    </div>
  )
}

function Sidebar({ activeTab, setActiveTab, user, open, onClose }) {
  return (
    <>
      {open && <div className="fixed inset-0 bg-black/50 z-40 lg:hidden" onClick={onClose} />}
      <aside className={`
        fixed top-0 left-0 h-full w-60 z-50
        bg-[var(--color-surface)] border-r border-[var(--color-border)]
        transform transition-transform duration-200
        ${open ? 'translate-x-0' : '-translate-x-full'}
        lg:translate-x-0 lg:static lg:z-auto flex flex-col
      `}>
        <div className="p-4 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-[var(--color-accent)] flex items-center justify-center text-black font-bold">⚡</div>
            <div>
              <div className="font-bold text-sm text-[var(--color-text)]">Admin Portal</div>
              <div className="text-[10px] text-[var(--color-text-dim)] truncate max-w-[150px]">{user?.email}</div>
            </div>
          </div>
        </div>
        <nav className="flex-1 p-3 space-y-0.5">
          {TABS.map(t => (
            <button key={t.id} onClick={() => { setActiveTab(t.id); onClose() }}
              className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm cursor-pointer transition-colors
                ${activeTab === t.id
                  ? 'bg-[var(--color-accent-dim)] text-[var(--color-accent)]'
                  : 'text-[var(--color-text-dim)] hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text)]'}`}>
              <span>{t.icon}</span><span className="truncate">{t.label}</span>
            </button>
          ))}
        </nav>
        <div className="p-3 border-t border-[var(--color-border)]">
          <button onClick={() => signOut(auth)}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-[var(--color-red)] hover:bg-[var(--color-red)]/10 cursor-pointer transition-colors">
            <span>🚪</span><span>Đăng xuất</span>
          </button>
        </div>
      </aside>
    </>
  )
}

// ═══════════════════════════════════════════════════════════════
// DATA MANAGER TAB
// ═══════════════════════════════════════════════════════════════
const ENTITY_OPTIONS = [
  { key: 'vehicles', label: 'Vehicles' },
  { key: 'charge-logs', label: 'Charge Logs' },
  { key: 'trip-logs', label: 'Trip Logs' },
  { key: 'maintenance', label: 'Maintenance' },
  { key: 'telemetry', label: 'Telemetry' },
]

function DataManagerTab() {
  const [entity, setEntity] = useState('vehicles')
  const [data, setData] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [filterOwner, setFilterOwner] = useState('')
  const [filterVehicle, setFilterVehicle] = useState('')
  const [showDeleted, setShowDeleted] = useState(false)
  const [selected, setSelected] = useState(new Set())
  const [editDoc, setEditDoc] = useState(null)
  const [editJson, setEditJson] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    setSelected(new Set())
    try {
      const params = {}
      if (filterOwner) params.ownerUid = filterOwner
      if (filterVehicle) params.vehicleId = filterVehicle
      if (showDeleted) params.includeDeleted = 'true'
      const res = await api.adminList(entity, params)
      setData(res.data || [])
    } catch (e) {
      setError(e.message)
      setData([])
    } finally {
      setLoading(false)
    }
  }, [entity, filterOwner, filterVehicle, showDeleted])

  useEffect(() => { load() }, [load])

  const handleDelete = async (id) => {
    if (!confirm('Xóa mềm bản ghi này?')) return
    try {
      await api.adminDelete(entity, id)
      api.emitPortalSuccess('Đã xóa bản ghi')
      load()
    } catch (e) { api.emitPortalError(e.message) }
  }

  const handleRestore = async (id) => {
    try {
      await api.adminRestore(entity, id)
      api.emitPortalSuccess('Đã khôi phục bản ghi')
      load()
    } catch (e) { api.emitPortalError(e.message) }
  }

  const handleBulkDelete = async () => {
    if (selected.size === 0) return
    if (!confirm(`Xóa mềm ${selected.size} bản ghi?`)) return
    try {
      await api.adminBulkDelete(entity, [...selected])
      api.emitPortalSuccess(`Đã xóa mềm ${selected.size} bản ghi`)
      load()
    } catch (e) { api.emitPortalError(e.message) }
  }

  const handleSaveEdit = async () => {
    try {
      const parsed = JSON.parse(editJson)
      await api.adminUpdate(entity, editDoc, parsed)
      setEditDoc(null)
      api.emitPortalSuccess('Đã cập nhật dữ liệu')
      load()
    } catch (e) { api.emitPortalError(e.message) }
  }

  const toggleSelect = (id) => {
    const next = new Set(selected)
    next.has(id) ? next.delete(id) : next.add(id)
    setSelected(next)
  }

  const columns = data.length > 0 ? Object.keys(data[0]).filter(k => !k.startsWith('_')).slice(0, 8) : []

  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Entity</label>
          <select value={entity} onChange={e => setEntity(e.target.value)}
            className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs text-[var(--color-text)] cursor-pointer">
            {ENTITY_OPTIONS.map(o => <option key={o.key} value={o.key}>{o.label}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Owner UID</label>
          <input value={filterOwner} onChange={e => setFilterOwner(e.target.value)} placeholder="Tất cả"
            className="bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs text-[var(--color-text)] w-40" />
        </div>
        <div>
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Vehicle ID</label>
          <input value={filterVehicle} onChange={e => setFilterVehicle(e.target.value)} placeholder="Tất cả"
            className="bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs text-[var(--color-text)] w-40" />
        </div>
        <label className="flex items-center gap-1.5 text-xs text-[var(--color-text-dim)] cursor-pointer">
          <input type="checkbox" checked={showDeleted} onChange={e => setShowDeleted(e.target.checked)} />
          Hiện đã xóa
        </label>
        <button onClick={load} className="px-3 py-2 rounded-lg bg-[var(--color-accent)] text-black text-xs font-semibold cursor-pointer hover:opacity-90">
          🔄 Tải lại
        </button>
        {selected.size > 0 && (
          <button onClick={handleBulkDelete}
            className="px-3 py-2 rounded-lg bg-[var(--color-red)] text-white text-xs font-semibold cursor-pointer hover:opacity-90">
            🗑 Xóa {selected.size}
          </button>
        )}
      </div>

      {error && <div className="text-sm text-[var(--color-red)]">❌ {error}</div>}

      {/* Table */}
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-[var(--color-border)] text-[var(--color-text-dim)]">
                <th className="px-3 py-2 w-8"><input type="checkbox" onChange={e => {
                  if (e.target.checked) setSelected(new Set(data.map(d => d._id)))
                  else setSelected(new Set())
                }} /></th>
                <th className="px-3 py-2 text-left font-medium">ID</th>
                {columns.map(c => <th key={c} className="px-3 py-2 text-left font-medium truncate max-w-[120px]">{c}</th>)}
                <th className="px-3 py-2 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading && <tr><td colSpan={columns.length + 3} className="px-3 py-8 text-center text-[var(--color-text-dim)]">⏳ Đang tải...</td></tr>}
              {!loading && data.length === 0 && <tr><td colSpan={columns.length + 3} className="px-3 py-8 text-center text-[var(--color-text-dim)]">Không có dữ liệu</td></tr>}
              {!loading && data.map(row => (
                <tr key={row._id} className={`border-b border-[var(--color-border)] hover:bg-[var(--color-surface-hover)] transition-colors ${row.isDeleted ? 'opacity-40' : ''}`}>
                  <td className="px-3 py-2"><input type="checkbox" checked={selected.has(row._id)} onChange={() => toggleSelect(row._id)} /></td>
                  <td className="px-3 py-2 font-mono text-[10px] text-[var(--color-text-dim)] max-w-[80px] truncate">{row._id}</td>
                  {columns.map(c => (
                    <td key={c} className="px-3 py-2 max-w-[150px] truncate">
                      {typeof row[c] === 'boolean' ? (row[c] ? '✅' : '❌') : String(row[c] ?? '')}
                    </td>
                  ))}
                  <td className="px-3 py-2 text-right whitespace-nowrap">
                    <button onClick={() => { setEditDoc(row._id); setEditJson(JSON.stringify(row, null, 2)) }}
                      className="text-[var(--color-blue)] hover:underline cursor-pointer mr-2">✏️</button>
                    {row.isDeleted
                      ? <button onClick={() => handleRestore(row._id)} className="text-[var(--color-accent)] hover:underline cursor-pointer">♻️</button>
                      : <button onClick={() => handleDelete(row._id)} className="text-[var(--color-red)] hover:underline cursor-pointer">🗑</button>
                    }
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="px-3 py-2 border-t border-[var(--color-border)] text-[10px] text-[var(--color-text-dim)]">
          {data.length} bản ghi
        </div>
      </div>

      {/* Edit Modal */}
      {editDoc && (
        <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4" onClick={() => setEditDoc(null)}>
          <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-5 w-full max-w-lg max-h-[80vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <h3 className="text-sm font-semibold mb-3">Chỉnh sửa: {editDoc}</h3>
            <textarea value={editJson} onChange={e => setEditJson(e.target.value)} rows={15}
              className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs font-mono text-[var(--color-text)] focus:outline-none" />
            <div className="flex justify-end gap-2 mt-3">
              <button onClick={() => setEditDoc(null)} className="px-3 py-1.5 rounded-lg bg-[var(--color-surface-hover)] text-xs cursor-pointer">Hủy</button>
              <button onClick={handleSaveEdit} className="px-3 py-1.5 rounded-lg bg-[var(--color-accent)] text-black text-xs font-semibold cursor-pointer">Lưu</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// AI LAB TAB
// ═══════════════════════════════════════════════════════════════
function AiLabTab() {
  const [vehicleId, setVehicleId] = useState('')
  const [dataset, setDataset] = useState([])
  const [normalized, setNormalized] = useState(null)
  const [trainResult, setTrainResult] = useState(null)
  const [testResult, setTestResult] = useState(null)
  const [profileStatus, setProfileStatus] = useState(null)
  const [loading, setLoading] = useState('')
  const [error, setError] = useState('')

  const loadDataset = async () => {
    if (!vehicleId) return
    setLoading('load')
    setError('')
    try {
      const res = await api.adminList('charge-logs', { vehicleId })
      setDataset(res.data || [])
      setNormalized(null)
      setTrainResult(null)
      setTestResult(null)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const checkProfile = async () => {
    if (!vehicleId) return
    setLoading('check')
    try {
      const res = await api.aiProfileStatus(vehicleId)
      setProfileStatus(res.data)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const normalize = async () => {
    setLoading('normalize')
    setError('')
    try {
      const res = await api.aiNormalize(dataset)
      setNormalized(res.data)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const train = async () => {
    const records = normalized?.records || dataset
    setLoading('train')
    setError('')
    try {
      const res = await api.aiTrain(vehicleId, records)
      setTrainResult(res.data)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const test = async () => {
    const records = normalized?.records || dataset
    setLoading('test')
    setError('')
    try {
      const res = await api.aiTest(vehicleId, records)
      setTestResult(res.data)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  return (
    <div className="space-y-5">
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-5">
        <h3 className="text-sm font-semibold mb-4 flex items-center gap-2"><span>🤖</span> AI Lab — Train & Test</h3>

        <div className="flex flex-wrap items-end gap-3 mb-4">
          <div className="flex-1 min-w-[200px]">
            <label className="block text-xs text-[var(--color-text-dim)] mb-1">Vehicle ID</label>
            <input value={vehicleId} onChange={e => setVehicleId(e.target.value)} placeholder="VF-OPES-001"
              className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-sm text-[var(--color-text)]" />
          </div>
          {[
            { key: 'load', label: '📥 Load Dataset', fn: loadDataset },
            { key: 'check', label: '🔍 Check Profile', fn: checkProfile },
            { key: 'normalize', label: '🧹 Normalize', fn: normalize, disabled: dataset.length === 0 },
            { key: 'train', label: '🎯 Train', fn: train, disabled: dataset.length < 5 },
            { key: 'test', label: '🧪 Test', fn: test, disabled: dataset.length === 0 },
          ].map(b => (
            <button key={b.key} onClick={b.fn} disabled={b.disabled || loading !== ''}
              className="px-3 py-2 rounded-lg text-xs font-medium bg-[var(--color-surface-hover)] border border-[var(--color-border)] hover:border-[var(--color-accent)] disabled:opacity-40 cursor-pointer disabled:cursor-not-allowed whitespace-nowrap">
              {loading === b.key ? '⏳' : ''} {b.label}
            </button>
          ))}
        </div>

        {error && <div className="text-sm text-[var(--color-red)] mb-3">❌ {error}</div>}

        {/* Dataset info */}
        {dataset.length > 0 && (
          <div className="bg-[var(--color-bg)] rounded-lg p-3 mb-3 text-xs">
            <span className="text-[var(--color-accent)] font-semibold">{dataset.length}</span> bản ghi charge logs
            {normalized && <span className="ml-3 text-[var(--color-blue)]">✅ Normalized: {normalized.cleaned} OK, {normalized.rejected} rejected</span>}
          </div>
        )}

        {/* Profile Status */}
        {profileStatus && (
          <div className="bg-[var(--color-bg)] rounded-lg p-3 mb-3">
            <div className="text-xs font-medium text-[var(--color-text-dim)] mb-2">Profile Status</div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
              <div><span className="text-[var(--color-text-dim)]">Trained:</span> {profileStatus.hasTrained ? '✅' : '❌'}</div>
              <div><span className="text-[var(--color-text-dim)]">Points:</span> {profileStatus.dataPoints}</div>
              <div><span className="text-[var(--color-text-dim)]">Version:</span> {profileStatus.version || '—'}</div>
              <div><span className="text-[var(--color-text-dim)]">Adj:</span> {profileStatus.healthAdjustment || 0}</div>
            </div>
          </div>
        )}

        {/* Train Result */}
        {trainResult && (
          <div className="bg-[var(--color-accent-dim)] rounded-lg p-3 mb-3">
            <div className="text-xs font-medium text-[var(--color-accent)] mb-1">✅ Train Completed</div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
              <div>Data Points: {trainResult.dataPoints}</div>
              <div>Health Adj: {trainResult.healthAdjustment}</div>
              <div>Version: {trainResult.version}</div>
              <div>Trained: {trainResult.trainedAt?.slice(0, 16)}</div>
            </div>
          </div>
        )}

        {/* Test Result */}
        {testResult && (
          <div className="bg-[var(--color-blue)]/10 rounded-lg p-3">
            <div className="text-xs font-medium text-[var(--color-blue)] mb-1">🧪 Test Result</div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
              <div>Health: <span className={testResult.healthScore >= 80 ? 'text-[var(--color-accent)]' : testResult.healthScore >= 60 ? 'text-[var(--color-amber)]' : 'text-[var(--color-red)]'}>{testResult.healthScore}%</span></div>
              <div>Status: {testResult.healthStatus}</div>
              <div>Cycles: {testResult.equivalentCycles}</div>
              <div>Source: {testResult.modelSource}</div>
            </div>
            {testResult.recommendations?.length > 0 && (
              <ul className="mt-2 space-y-1 text-xs">{testResult.recommendations.map((r, i) => <li key={i}>{r}</li>)}</ul>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// IMPORT/EXPORT TAB
// ═══════════════════════════════════════════════════════════════
function ImportExportTab() {
  const [entity, setEntity] = useState('charge-logs')
  const [importData, setImportData] = useState('')
  const [importResult, setImportResult] = useState(null)
  const [exportResult, setExportResult] = useState(null)
  const [loading, setLoading] = useState('')
  const [error, setError] = useState('')

  const handleResetAll = async () => {
    const ok = confirm('Hành động này sẽ xóa TOÀN BỘ dữ liệu (Vehicles, ChargeLogs, TripLogs, Maintenance, Telemetry, AIProfiles). Tiếp tục?')
    if (!ok) return
    setLoading('reset')
    setError('')
    setImportResult(null)
    setExportResult(null)
    try {
      const res = await api.adminResetAll()
      api.emitPortalSuccess(res?.message || 'Đã xóa toàn bộ dữ liệu cũ')
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading('')
    }
  }

  const handleExport = async (fmt) => {
    setLoading('export')
    setError('')
    try {
      if (fmt === 'csv') {
        const res = await api.adminExport(entity, 'csv')
        // For CSV the response is already data
        setExportResult({ format: 'csv', data: res.data, total: res.total })
      } else {
        const res = await api.adminExport(entity, 'json')
        setExportResult({ format: 'json', data: res.data, total: res.total })
      }
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const handleImport = async () => {
    setLoading('import')
    setError('')
    setImportResult(null)
    try {
      const parsed = JSON.parse(importData)
      const records = Array.isArray(parsed) ? parsed : (parsed.data || [])
      const res = await api.adminImport(entity, records)
      setImportResult(res.data)
    } catch (e) { setError(e.message) }
    finally { setLoading('') }
  }

  const handleFileUpload = (e) => {
    const file = e.target.files[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => setImportData(ev.target.result)
    reader.readAsText(file)
  }

  const downloadExport = () => {
    if (!exportResult) return
    const blob = new Blob([JSON.stringify(exportResult.data, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${entity}_export.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-5">
      <div className="bg-[var(--color-surface)] border border-[var(--color-red)]/30 rounded-xl p-5">
        <h3 className="text-sm font-semibold mb-3 text-[var(--color-red)]">🧨 Reset dữ liệu hệ thống</h3>
        <p className="text-xs text-[var(--color-text-dim)] mb-3">
          Dùng khi cần làm sạch toàn bộ dữ liệu cũ để test lại từ đầu.
        </p>
        <button
          onClick={handleResetAll}
          disabled={loading !== ''}
          className="px-4 py-2 rounded-lg bg-[var(--color-red)] text-white text-xs font-semibold cursor-pointer disabled:opacity-50"
        >
          {loading === 'reset' ? '⏳ Đang xóa...' : '🗑 Xóa toàn bộ dữ liệu'}
        </button>
      </div>

      {/* Export */}
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-5">
        <h3 className="text-sm font-semibold mb-4">📤 Export</h3>
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <label className="block text-xs text-[var(--color-text-dim)] mb-1">Entity</label>
            <select value={entity} onChange={e => setEntity(e.target.value)}
              className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs text-[var(--color-text)] cursor-pointer">
              {ENTITY_OPTIONS.map(o => <option key={o.key} value={o.key}>{o.label}</option>)}
            </select>
          </div>
          <button onClick={() => handleExport('json')} disabled={loading !== ''}
            className="px-3 py-2 rounded-lg bg-[var(--color-blue)] text-white text-xs font-semibold cursor-pointer disabled:opacity-50">
            JSON
          </button>
          <button onClick={() => handleExport('csv')} disabled={loading !== ''}
            className="px-3 py-2 rounded-lg bg-[var(--color-accent)] text-black text-xs font-semibold cursor-pointer disabled:opacity-50">
            CSV
          </button>
          {exportResult && (
            <button onClick={downloadExport} className="px-3 py-2 rounded-lg bg-[var(--color-surface-hover)] text-xs cursor-pointer">
              💾 Tải file ({exportResult.total} bản ghi)
            </button>
          )}
        </div>
      </div>

      {/* Import */}
      <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-5">
        <h3 className="text-sm font-semibold mb-4">📥 Import</h3>
        <div className="space-y-3">
          <div className="flex gap-3 items-end">
            <div>
              <label className="block text-xs text-[var(--color-text-dim)] mb-1">File (JSON/CSV)</label>
              <input type="file" accept=".json,.csv" onChange={handleFileUpload}
                className="text-xs text-[var(--color-text-dim)]" />
            </div>
          </div>
          <textarea value={importData} onChange={e => setImportData(e.target.value)} rows={8} placeholder="Hoặc dán JSON vào đây..."
            className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-xs font-mono text-[var(--color-text)]" />
          <button onClick={handleImport} disabled={!importData.trim() || loading !== ''}
            className="px-4 py-2 rounded-lg bg-[var(--color-accent)] text-black text-xs font-semibold cursor-pointer disabled:opacity-50">
            {loading === 'import' ? '⏳' : '📥'} Import vào {entity}
          </button>

          {error && <div className="text-sm text-[var(--color-red)]">❌ {error}</div>}

          {importResult && (
            <div className="bg-[var(--color-bg)] rounded-lg p-3 text-xs space-y-1">
              <div className="text-[var(--color-accent)]">✅ Inserted: {importResult.inserted}, Updated: {importResult.updated}</div>
              {importResult.rejected > 0 && (
                <div className="text-[var(--color-red)]">❌ Rejected: {importResult.rejected}</div>
              )}
              {importResult.errorDetails?.length > 0 && (
                <ul className="text-[var(--color-red)] space-y-0.5">
                  {importResult.errorDetails.map((e, i) => <li key={i}>Dòng {e.row}: {e.error}</li>)}
                </ul>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// GUIDE TAB
// ═══════════════════════════════════════════════════════════════
function GuideTab() {
  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-6 space-y-6 text-sm leading-relaxed">
      <h2 className="text-lg font-bold flex items-center gap-2"><span>📖</span> Hướng dẫn Admin Portal</h2>

      <section>
        <h3 className="font-semibold text-[var(--color-accent)] mb-2">1. Chuẩn dữ liệu</h3>
        <ul className="list-disc ml-5 space-y-1 text-[var(--color-text-dim)]">
          <li>Mọi bản ghi bắt buộc có: <code className="text-[var(--color-text)]">ownerUid</code>, <code className="text-[var(--color-text)]">createdAt</code>, <code className="text-[var(--color-text)]">updatedAt</code>, <code className="text-[var(--color-text)]">isDeleted</code></li>
          <li>Thời gian chuẩn <b>UTC ISO 8601</b> (VD: <code className="text-[var(--color-text)]">2026-04-07T08:30:00Z</code>)</li>
          <li>Pin: 0–100%, Speed ≥ 0, Altitude hợp lệ</li>
          <li>Bản ghi lỗi sẽ bị bỏ qua khi normalize</li>
        </ul>
      </section>

      <section>
        <h3 className="font-semibold text-[var(--color-accent)] mb-2">2. Quy trình Train AI</h3>
        <ol className="list-decimal ml-5 space-y-1 text-[var(--color-text-dim)]">
          <li>Vào tab <b>AI Lab</b>, nhập Vehicle ID</li>
          <li>Bấm <b>Load Dataset</b> để lấy charge logs từ Firestore</li>
          <li>Bấm <b>Normalize</b> để chuẩn hóa (bỏ lỗi, gắn metadata)</li>
          <li>Bấm <b>Train</b> để train profile cá nhân hóa</li>
          <li>Bấm <b>Test</b> để kiểm tra model trên dataset đó</li>
          <li>Xem <b>Check Profile</b> để theo dõi trạng thái model</li>
        </ol>
      </section>

      <section>
        <h3 className="font-semibold text-[var(--color-accent)] mb-2">3. Đồng bộ App ↔ Web</h3>
        <ul className="list-disc ml-5 space-y-1 text-[var(--color-text-dim)]">
          <li>Cùng dùng Firestore làm nguồn sự thật duy nhất</li>
          <li>App ghi dữ liệu có <code className="text-[var(--color-text)]">ownerUid</code> → Web admin thấy ngay</li>
          <li>Admin sửa dữ liệu → App user nhận real-time qua snapshots</li>
          <li>Dùng <b>soft delete</b> — không mất dữ liệu gốc</li>
        </ul>
      </section>

      <section>
        <h3 className="font-semibold text-[var(--color-accent)] mb-2">4. Import/Export</h3>
        <ul className="list-disc ml-5 space-y-1 text-[var(--color-text-dim)]">
          <li>Hỗ trợ JSON và CSV</li>
          <li>Import mode <b>upsert</b>: cập nhật nếu trùng ID, tạo mới nếu chưa có</li>
          <li>Export filter theo user, vehicle, date range</li>
          <li>Bản ghi lỗi sẽ được báo chi tiết theo dòng</li>
        </ul>
      </section>

      <section>
        <h3 className="font-semibold text-[var(--color-accent)] mb-2">5. Dữ liệu Legacy</h3>
        <ul className="list-disc ml-5 space-y-1 text-[var(--color-text-dim)]">
          <li>Bản ghi cũ không có <code className="text-[var(--color-text)]">ownerUid</code> được đánh dấu <b>legacy</b></li>
          <li>Legacy hiển thị ở Web Admin nhưng <b>không hiện trong App</b></li>
          <li>Dùng nút <b>Migrate Legacy</b> trong settings API để batch tag</li>
        </ul>
      </section>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// MAIN APP
// ═══════════════════════════════════════════════════════════════
export default function AdminPortal() {
  const [user, setUser] = useState(null)
  const [authLoading, setAuthLoading] = useState(true)
  const [activeTab, setActiveTab] = useState('dashboard')
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [authInfo, setAuthInfo] = useState(null)
  const [toasts, setToasts] = useState([])

  const pushToast = useCallback((type, message) => {
    const id = `${Date.now()}-${Math.random().toString(16).slice(2)}`
    setToasts(prev => [...prev, { id, type, message }])
    window.setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== id))
    }, 4200)
  }, [])

  useEffect(() => {
    const onError = (e) => pushToast('error', e?.detail?.message || 'Đã xảy ra lỗi không xác định')
    const onSuccess = (e) => pushToast('success', e?.detail?.message || 'Thao tác thành công')
    const onUnhandledRejection = (e) => pushToast('error', e?.reason?.message || 'Lỗi promise chưa xử lý')
    const onWindowError = (e) => pushToast('error', e?.message || 'Lỗi runtime trên trình duyệt')

    window.addEventListener('vf:error', onError)
    window.addEventListener('vf:success', onSuccess)
    window.addEventListener('unhandledrejection', onUnhandledRejection)
    window.addEventListener('error', onWindowError)
    return () => {
      window.removeEventListener('vf:error', onError)
      window.removeEventListener('vf:success', onSuccess)
      window.removeEventListener('unhandledrejection', onUnhandledRejection)
      window.removeEventListener('error', onWindowError)
    }
  }, [pushToast])

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u) => {
      setUser(u)
      setAuthLoading(false)
      if (u) {
        try {
          const res = await api.authMe()
          setAuthInfo(res.data)
        } catch {
          setAuthInfo(null)
        }
      } else {
        setAuthInfo(null)
      }
    })
    return unsub
  }, [])

  if (authLoading) {
    return <div className="min-h-screen bg-[var(--color-bg)] flex items-center justify-center text-[var(--color-text-dim)]">⏳ Loading...</div>
  }

  if (!user) {
    return <LoginScreen />
  }

  // Check admin role
  if (authInfo && authInfo.role !== 'admin') {
    return (
      <div className="min-h-screen bg-[var(--color-bg)] flex items-center justify-center p-4">
        <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-6 text-center max-w-sm">
          <div className="text-3xl mb-3">🚫</div>
          <h2 className="font-bold mb-2">Không có quyền truy cập</h2>
          <p className="text-sm text-[var(--color-text-dim)] mb-4">Tài khoản <b>{user.email}</b> không phải Admin.</p>
          <button onClick={() => signOut(auth)}
            className="px-4 py-2 rounded-lg bg-[var(--color-red)] text-white text-sm cursor-pointer">Đăng xuất</button>
        </div>
      </div>
    )
  }

  return (
    <div className="portal-shell flex h-screen overflow-hidden">
      <ToastCenter items={toasts} onClose={(id) => setToasts(prev => prev.filter(t => t.id !== id))} />
      <Sidebar activeTab={activeTab} setActiveTab={setActiveTab} user={user} open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <main className="flex-1 overflow-y-auto">
        {/* Top bar */}
        <header className="sticky top-0 z-30 bg-[var(--color-bg)]/80 backdrop-blur-md border-b border-[var(--color-border)] px-4 lg:px-6 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button onClick={() => setSidebarOpen(true)} className="lg:hidden p-1.5 rounded-lg hover:bg-[var(--color-surface-hover)] cursor-pointer">☰</button>
            <h1 className="text-base font-bold">{TABS.find(t => t.id === activeTab)?.label || 'Dashboard'}</h1>
          </div>
          <div className="flex items-center gap-2 text-xs text-[var(--color-text-dim)]">
            {authInfo && <span className="hidden sm:inline px-2 py-1 rounded-md bg-[var(--color-accent-dim)] text-[var(--color-accent)] font-medium">{authInfo.role}</span>}
            <span className="hidden sm:inline">{user.email}</span>
          </div>
        </header>

        <div className="p-4 lg:p-6 portal-content-in">
          {activeTab === 'dashboard' && <TelemetryDashboard />}
          {activeTab === 'data' && <DataManagerTab />}
          {activeTab === 'ai' && <AiLabTab />}
          {activeTab === 'import' && <ImportExportTab />}
          {activeTab === 'guide' && <GuideTab />}
        </div>
      </main>
    </div>
  )
}
