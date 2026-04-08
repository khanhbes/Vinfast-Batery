import { useState, useEffect, useMemo, useCallback } from 'react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend,
} from 'recharts'

// ═══════════════════════════════════════════════════════════════
// ENV CONFIG
// ═══════════════════════════════════════════════════════════════
const API_BASE = import.meta.env.VITE_API_BASE_URL || ''
const AI_API_BASE = import.meta.env.VITE_AI_API_BASE_URL || 'http://localhost:5001'

// ═══════════════════════════════════════════════════════════════
// MOCK DATA — 15 bản ghi chuẩn schema telemetry
// ═══════════════════════════════════════════════════════════════
const mockData = [
  { trip_id: 'TRIP-001', timestamp: '2026-04-07T06:00:00Z', latitude: 21.0285, longitude: 105.8542, speed_kmh: 0, altitude_m: 12, current_soc: 95 },
  { trip_id: 'TRIP-001', timestamp: '2026-04-07T06:05:00Z', latitude: 21.0301, longitude: 105.8490, speed_kmh: 32, altitude_m: 14, current_soc: 93 },
  { trip_id: 'TRIP-001', timestamp: '2026-04-07T06:10:00Z', latitude: 21.0350, longitude: 105.8430, speed_kmh: 45, altitude_m: 18, current_soc: 90 },
  { trip_id: 'TRIP-001', timestamp: '2026-04-07T06:15:00Z', latitude: 21.0400, longitude: 105.8370, speed_kmh: 38, altitude_m: 22, current_soc: 88 },
  { trip_id: 'TRIP-001', timestamp: '2026-04-07T06:20:00Z', latitude: 21.0420, longitude: 105.8310, speed_kmh: 50, altitude_m: 25, current_soc: 85 },
  { trip_id: 'TRIP-002', timestamp: '2026-04-07T08:00:00Z', latitude: 21.0285, longitude: 105.8542, speed_kmh: 0, altitude_m: 12, current_soc: 82 },
  { trip_id: 'TRIP-002', timestamp: '2026-04-07T08:05:00Z', latitude: 21.0260, longitude: 105.8600, speed_kmh: 28, altitude_m: 10, current_soc: 80 },
  { trip_id: 'TRIP-002', timestamp: '2026-04-07T08:10:00Z', latitude: 21.0230, longitude: 105.8670, speed_kmh: 42, altitude_m: 8, current_soc: 77 },
  { trip_id: 'TRIP-002', timestamp: '2026-04-07T08:15:00Z', latitude: 21.0190, longitude: 105.8730, speed_kmh: 55, altitude_m: 6, current_soc: 74 },
  { trip_id: 'TRIP-002', timestamp: '2026-04-07T08:20:00Z', latitude: 21.0160, longitude: 105.8800, speed_kmh: 35, altitude_m: 9, current_soc: 72 },
  { trip_id: 'TRIP-003', timestamp: '2026-04-07T14:00:00Z', latitude: 21.0350, longitude: 105.8400, speed_kmh: 0, altitude_m: 15, current_soc: 68 },
  { trip_id: 'TRIP-003', timestamp: '2026-04-07T14:05:00Z', latitude: 21.0380, longitude: 105.8340, speed_kmh: 25, altitude_m: 20, current_soc: 66 },
  { trip_id: 'TRIP-003', timestamp: '2026-04-07T14:10:00Z', latitude: 21.0410, longitude: 105.8280, speed_kmh: 60, altitude_m: 30, current_soc: 63 },
  { trip_id: 'TRIP-003', timestamp: '2026-04-07T14:15:00Z', latitude: 21.0450, longitude: 105.8220, speed_kmh: 48, altitude_m: 35, current_soc: 60 },
  { trip_id: 'TRIP-003', timestamp: '2026-04-07T14:20:00Z', latitude: 21.0490, longitude: 105.8160, speed_kmh: 20, altitude_m: 28, current_soc: 58 },
]

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════
function fmtTime(iso) {
  try {
    const d = new Date(iso)
    return d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  } catch { return iso }
}
function fmtDateTime(iso) {
  try {
    const d = new Date(iso)
    return d.toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
  } catch { return iso }
}

// ═══════════════════════════════════════════════════════════════
// SIDEBAR
// ═══════════════════════════════════════════════════════════════
function Sidebar({ open, onClose }) {
  return (
    <>
      {/* Overlay mobile */}
      {open && (
        <div className="fixed inset-0 bg-black/50 z-40 lg:hidden" onClick={onClose} />
      )}
      <aside className={`
        fixed top-0 left-0 h-full w-64 z-50 
        bg-[var(--color-surface)] border-r border-[var(--color-border)]
        transform transition-transform duration-200
        ${open ? 'translate-x-0' : '-translate-x-full'}
        lg:translate-x-0 lg:static lg:z-auto
        flex flex-col
      `}>
        {/* Logo */}
        <div className="p-5 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-[var(--color-accent)] flex items-center justify-center text-black font-bold text-lg">⚡</div>
            <div>
              <div className="font-bold text-[var(--color-text)] text-sm">VinFast Battery</div>
              <div className="text-[10px] text-[var(--color-text-dim)]">Telemetry Dashboard</div>
            </div>
          </div>
        </div>
        {/* Nav */}
        <nav className="flex-1 p-4 space-y-1">
          {[
            { icon: '📊', label: 'Dashboard', active: true },
            { icon: '🗺️', label: 'Bản đồ' },
            { icon: '🔋', label: 'Pin & Sạc' },
            { icon: '🤖', label: 'AI Analysis' },
          ].map(item => (
            <div key={item.label} className={`
              flex items-center gap-3 px-3 py-2.5 rounded-lg cursor-pointer text-sm
              ${item.active
                ? 'bg-[var(--color-accent-dim)] text-[var(--color-accent)]'
                : 'text-[var(--color-text-dim)] hover:bg-[var(--color-surface-hover)] hover:text-[var(--color-text)]'
              }
            `}>
              <span>{item.icon}</span>
              <span className="truncate">{item.label}</span>
            </div>
          ))}
        </nav>
        {/* Footer */}
        <div className="p-4 border-t border-[var(--color-border)] text-[11px] text-[var(--color-text-dim)]">
          v1.0 — React + Recharts
        </div>
      </aside>
    </>
  )
}

// ═══════════════════════════════════════════════════════════════
// METRIC CARDS
// ═══════════════════════════════════════════════════════════════
function MetricCards({ records }) {
  const latest = records[records.length - 1]
  const avgSpeed = records.length
    ? (records.reduce((s, r) => s + r.speed_kmh, 0) / records.length).toFixed(1)
    : 0
  const maxAlt = records.length ? Math.max(...records.map(r => r.altitude_m)) : 0
  const trips = [...new Set(records.map(r => r.trip_id))].length

  const cards = [
    { label: 'Bản ghi', value: records.length, icon: '📋', color: 'var(--color-blue)' },
    { label: 'Chuyến đi', value: trips, icon: '🛣️', color: 'var(--color-accent)' },
    { label: 'Tốc độ TB', value: `${avgSpeed} km/h`, icon: '⚡', color: 'var(--color-amber)' },
    { label: 'Pin hiện tại', value: latest ? `${latest.current_soc}%` : '—', icon: '🔋', color: latest && latest.current_soc < 30 ? 'var(--color-red)' : 'var(--color-accent)' },
  ]

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {cards.map(c => (
        <div key={c.label} className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs text-[var(--color-text-dim)]">{c.label}</span>
            <span className="text-lg">{c.icon}</span>
          </div>
          <div className="text-xl font-bold" style={{ color: c.color }}>{c.value}</div>
        </div>
      ))}
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// TELEMETRY CHARTS — 3 line charts
// ═══════════════════════════════════════════════════════════════
function TelemetryCharts({ records }) {
  // Sort ascending by timestamp for chart
  const sorted = useMemo(() =>
    [...records].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp)),
    [records]
  )

  const chartDefs = [
    { key: 'speed_kmh', label: 'Vận tốc (km/h)', color: '#ffab40', unit: 'km/h' },
    { key: 'altitude_m', label: 'Độ cao (m)', color: '#448aff', unit: 'm' },
    { key: 'current_soc', label: '% Pin (SoC)', color: '#00c853', unit: '%' },
  ]

  return (
    <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
      {chartDefs.map(def => (
        <div key={def.key} className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-4">
          <h3 className="text-sm font-semibold mb-3 text-[var(--color-text)]">{def.label}</h3>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={sorted}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
              <XAxis
                dataKey="timestamp"
                tickFormatter={fmtTime}
                tick={{ fontSize: 10, fill: 'var(--color-text-dim)' }}
                interval="preserveStartEnd"
              />
              <YAxis
                tick={{ fontSize: 10, fill: 'var(--color-text-dim)' }}
                width={40}
                unit={` ${def.unit}`}
              />
              <Tooltip
                labelFormatter={fmtDateTime}
                formatter={(v) => [`${v} ${def.unit}`, def.label]}
              />
              <Line
                type="monotone"
                dataKey={def.key}
                stroke={def.color}
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 4 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ))}
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// TELEMETRY TABLE + PAGINATION
// ═══════════════════════════════════════════════════════════════
function TelemetryTable({ records, currentPage, setCurrentPage, pageSize }) {
  // Sort descending for table display
  const sorted = useMemo(() =>
    [...records].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp)),
    [records]
  )
  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize))
  const page = Math.min(currentPage, totalPages)
  const paged = sorted.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--color-border)] text-[var(--color-text-dim)] text-xs">
              <th className="text-left px-4 py-3 font-medium">Thời gian</th>
              <th className="text-left px-4 py-3 font-medium">ID Chuyến đi</th>
              <th className="text-right px-4 py-3 font-medium">Vận tốc</th>
              <th className="text-right px-4 py-3 font-medium">Độ cao</th>
              <th className="text-right px-4 py-3 font-medium">% Pin</th>
            </tr>
          </thead>
          <tbody>
            {paged.map((r, i) => (
              <tr key={i} className="border-b border-[var(--color-border)] hover:bg-[var(--color-surface-hover)] transition-colors">
                <td className="px-4 py-2.5 whitespace-nowrap">{fmtDateTime(r.timestamp)}</td>
                <td className="px-4 py-2.5">
                  <span className="inline-block bg-[var(--color-accent-dim)] text-[var(--color-accent)] text-xs px-2 py-0.5 rounded-md font-mono">
                    {r.trip_id}
                  </span>
                </td>
                <td className="px-4 py-2.5 text-right font-mono">{r.speed_kmh} km/h</td>
                <td className="px-4 py-2.5 text-right font-mono">{r.altitude_m} m</td>
                <td className="px-4 py-2.5 text-right">
                  <span className={`font-mono font-semibold ${r.current_soc < 30 ? 'text-[var(--color-red)]' : r.current_soc < 60 ? 'text-[var(--color-amber)]' : 'text-[var(--color-accent)]'}`}>
                    {r.current_soc}%
                  </span>
                </td>
              </tr>
            ))}
            {paged.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-8 text-center text-[var(--color-text-dim)]">Không có dữ liệu</td></tr>
            )}
          </tbody>
        </table>
      </div>
      {/* Pagination */}
      <div className="flex items-center justify-between px-4 py-3 border-t border-[var(--color-border)] text-xs text-[var(--color-text-dim)]">
        <span>{sorted.length} bản ghi</span>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="px-3 py-1 rounded-md bg-[var(--color-surface-hover)] disabled:opacity-30 hover:bg-[var(--color-border)] transition-colors cursor-pointer disabled:cursor-not-allowed"
          >← Trước</button>
          <span>Trang {page}/{totalPages}</span>
          <button
            onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
            disabled={page >= totalPages}
            className="px-3 py-1 rounded-md bg-[var(--color-surface-hover)] disabled:opacity-30 hover:bg-[var(--color-border)] transition-colors cursor-pointer disabled:cursor-not-allowed"
          >Sau →</button>
        </div>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// AI PANEL V1
// ═══════════════════════════════════════════════════════════════
function AiPanel() {
  const [vehicleId, setVehicleId] = useState('VF-OPES-001')
  const [loading, setLoading] = useState(null) // 'check' | 'train' | 'predict' | 'analyze'
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  const callAi = useCallback(async (action) => {
    setLoading(action)
    setError(null)
    setResult(null)

    try {
      if (action === 'check') {
        const res = await fetch(`${AI_API_BASE}/api/profile-status/${encodeURIComponent(vehicleId)}`)
        const json = await res.json()
        if (!json.success) throw new Error(json.error || 'Unknown error')
        setResult({ type: 'check', data: json.data })

      } else {
        // Lấy charge logs từ main API
        const logsRes = await fetch(`${API_BASE}/api/charge-logs?vehicleId=${encodeURIComponent(vehicleId)}`)
        const logsJson = await logsRes.json()
        const chargeLogs = logsJson.data || logsJson || []

        let endpoint = ''
        if (action === 'train') endpoint = '/api/train-vehicle-profile'
        else if (action === 'predict') endpoint = '/api/predict-degradation'
        else if (action === 'analyze') endpoint = '/api/analyze-patterns'

        const res = await fetch(`${AI_API_BASE}${endpoint}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ vehicleId, chargeLogs }),
        })
        const json = await res.json()
        if (!json.success) throw new Error(json.error || 'Unknown error')
        setResult({ type: action, data: json.data, message: json.message })
      }
    } catch (err) {
      setError(err.message || 'Lỗi kết nối')
    } finally {
      setLoading(null)
    }
  }, [vehicleId])

  return (
    <div className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-xl p-5">
      <h3 className="text-sm font-semibold mb-4 flex items-center gap-2">
        <span className="text-lg">🤖</span> AI Battery Analysis
      </h3>

      {/* Input + Actions */}
      <div className="flex flex-wrap items-end gap-3 mb-4">
        <div className="flex-1 min-w-[180px]">
          <label className="block text-xs text-[var(--color-text-dim)] mb-1">Vehicle ID</label>
          <input
            type="text"
            value={vehicleId}
            onChange={e => setVehicleId(e.target.value)}
            className="w-full bg-[var(--color-bg)] border border-[var(--color-border)] rounded-lg px-3 py-2 text-sm text-[var(--color-text)] focus:outline-none focus:border-[var(--color-accent)]"
            placeholder="VF-OPES-001"
          />
        </div>
        {[
          { key: 'check', label: 'Check Profile', icon: '🔍' },
          { key: 'train', label: 'Train Profile', icon: '🎯' },
          { key: 'predict', label: 'Predict', icon: '📈' },
          { key: 'analyze', label: 'Analyze', icon: '🔬' },
        ].map(btn => (
          <button
            key={btn.key}
            onClick={() => callAi(btn.key)}
            disabled={!vehicleId.trim() || loading !== null}
            className="px-3 py-2 rounded-lg text-xs font-medium bg-[var(--color-surface-hover)] border border-[var(--color-border)] hover:border-[var(--color-accent)] hover:text-[var(--color-accent)] disabled:opacity-40 transition-colors cursor-pointer disabled:cursor-not-allowed whitespace-nowrap"
          >
            {loading === btn.key ? '⏳' : btn.icon} {btn.label}
          </button>
        ))}
      </div>

      {/* Error */}
      {error && (
        <div className="bg-[var(--color-red)]/10 border border-[var(--color-red)]/30 rounded-lg p-3 mb-4 text-sm text-[var(--color-red)]">
          ❌ {error}
        </div>
      )}

      {/* Results */}
      {result && (
        <div className="space-y-3">
          {result.message && (
            <div className="bg-[var(--color-accent-dim)] border border-[var(--color-accent)]/30 rounded-lg p-3 text-sm text-[var(--color-accent)]">
              ✅ {result.message}
            </div>
          )}
          {result.type === 'check' && <ProfileStatusCard data={result.data} />}
          {result.type === 'predict' && <PredictionCard data={result.data} />}
          {result.type === 'analyze' && <PatternsCard data={result.data} />}
          {result.type === 'train' && <TrainResultCard data={result.data} />}
        </div>
      )}
    </div>
  )
}

// ── AI result sub-cards ──

function ProfileStatusCard({ data }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      <MiniCard label="Đã train" value={data.hasTrained ? '✅ Có' : '❌ Chưa'} />
      <MiniCard label="Data Points" value={data.dataPoints || 0} />
      <MiniCard label="Version" value={data.version || '—'} />
      <MiniCard label="Trained At" value={data.trainedAt ? fmtDateTime(data.trainedAt) : '—'} />
    </div>
  )
}

function PredictionCard({ data }) {
  const scoreColor = data.healthScore >= 80 ? 'var(--color-accent)' : data.healthScore >= 60 ? 'var(--color-amber)' : 'var(--color-red)'
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MiniCard label="Health Score" value={`${data.healthScore}%`} valueColor={scoreColor} />
        <MiniCard label="Trạng thái" value={data.healthStatus} />
        <MiniCard label="Model Source" value={data.modelSource || 'rule-based'} />
        <MiniCard label="Chu kỳ tương đương" value={data.equivalentCycles} />
      </div>
      {data.recommendations?.length > 0 && (
        <div className="bg-[var(--color-bg)] rounded-lg p-3">
          <div className="text-xs font-medium text-[var(--color-text-dim)] mb-2">Đề xuất</div>
          <ul className="space-y-1 text-sm">
            {data.recommendations.map((r, i) => <li key={i} className="break-words">{r}</li>)}
          </ul>
        </div>
      )}
    </div>
  )
}

function PatternsCard({ data }) {
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MiniCard label="Giờ sạc phổ biến" value={data.peakChargingHour || '—'} />
        <MiniCard label="Ngày sạc nhiều" value={data.peakChargingDay || '—'} />
        <MiniCard label="Tần suất/tuần" value={data.chargeFrequencyPerWeek ? `${data.chargeFrequencyPerWeek} lần` : '—'} />
        <MiniCard label="Thời gian TB" value={data.avgSessionDuration ? `${data.avgSessionDuration}h` : '—'} />
      </div>
      {data.patterns?.length > 0 && (
        <div className="bg-[var(--color-bg)] rounded-lg p-3">
          <div className="text-xs font-medium text-[var(--color-text-dim)] mb-2">Patterns</div>
          <ul className="space-y-1 text-sm">
            {data.patterns.map((p, i) => <li key={i} className="break-words">{p}</li>)}
          </ul>
        </div>
      )}
    </div>
  )
}

function TrainResultCard({ data }) {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      <MiniCard label="Vehicle" value={data.vehicleId} />
      <MiniCard label="Data Points" value={data.dataPoints} />
      <MiniCard label="Health Adj." value={data.healthAdjustment > 0 ? `+${data.healthAdjustment}` : data.healthAdjustment} />
      <MiniCard label="Version" value={data.version} />
    </div>
  )
}

function MiniCard({ label, value, valueColor }) {
  return (
    <div className="bg-[var(--color-bg)] rounded-lg p-3">
      <div className="text-[10px] text-[var(--color-text-dim)] mb-1 truncate">{label}</div>
      <div className="text-sm font-semibold truncate" style={valueColor ? { color: valueColor } : undefined}>{value}</div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════
// MAIN DASHBOARD
// ═══════════════════════════════════════════════════════════════
export default function TelemetryDashboard() {
  const [records, setRecords] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [selectedTripId, setSelectedTripId] = useState('')
  const [currentPage, setCurrentPage] = useState(1)
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [refreshAt, setRefreshAt] = useState(null)
  const pageSize = 10

  // ── Load telemetry data ──
  const loadTelemetry = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`${API_BASE}/api/telemetry`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      const arr = Array.isArray(data) ? data : (data.data || [])
      if (arr.length === 0) throw new Error('empty')
      setRecords(arr)
    } catch {
      // Fallback to mock
      setRecords(mockData)
      setError('Dùng dữ liệu mẫu (API chưa khả dụng)')
    } finally {
      setLoading(false)
      setRefreshAt(new Date().toLocaleTimeString('vi-VN'))
    }
  }, [])

  useEffect(() => { loadTelemetry() }, [loadTelemetry])

  // ── Filter by trip_id ──
  const tripIds = useMemo(() => [...new Set(records.map(r => r.trip_id))].sort(), [records])
  const filtered = useMemo(() =>
    selectedTripId ? records.filter(r => r.trip_id === selectedTripId) : records,
    [records, selectedTripId]
  )

  // Reset page khi filter thay đổi
  useEffect(() => { setCurrentPage(1) }, [selectedTripId])

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar open={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <main className="flex-1 overflow-y-auto">
        {/* Top bar */}
        <header className="sticky top-0 z-30 bg-[var(--color-bg)]/80 backdrop-blur-md border-b border-[var(--color-border)] px-4 lg:px-6 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setSidebarOpen(true)}
              className="lg:hidden p-1.5 rounded-lg hover:bg-[var(--color-surface-hover)] cursor-pointer"
            >☰</button>
            <h1 className="text-base font-bold">Telemetry Dashboard</h1>
            {refreshAt && (
              <span className="text-[10px] text-[var(--color-text-dim)] hidden sm:inline">
                Cập nhật: {refreshAt}
              </span>
            )}
          </div>
          <div className="flex items-center gap-3">
            {/* Trip filter */}
            <select
              value={selectedTripId}
              onChange={e => setSelectedTripId(e.target.value)}
              className="bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg px-3 py-1.5 text-xs text-[var(--color-text)] focus:outline-none focus:border-[var(--color-accent)] cursor-pointer"
            >
              <option value="">Tất cả chuyến</option>
              {tripIds.map(id => <option key={id} value={id}>{id}</option>)}
            </select>
            {/* Refresh */}
            <button
              onClick={loadTelemetry}
              disabled={loading}
              className="px-3 py-1.5 rounded-lg bg-[var(--color-accent)] text-black text-xs font-semibold hover:opacity-90 disabled:opacity-50 transition-opacity cursor-pointer disabled:cursor-not-allowed"
            >
              {loading ? '⏳' : '🔄'} Refresh
            </button>
          </div>
        </header>

        {/* Content */}
        <div className="p-4 lg:p-6 space-y-5 min-w-0">
          {/* Warning banner */}
          {error && (
            <div className="bg-[var(--color-amber)]/10 border border-[var(--color-amber)]/30 rounded-lg px-4 py-2 text-sm text-[var(--color-amber)]">
              ⚠ {error}
            </div>
          )}

          {/* Metric cards */}
          <MetricCards records={filtered} />

          {/* Charts */}
          <TelemetryCharts records={filtered} />

          {/* Table */}
          <TelemetryTable
            records={filtered}
            currentPage={currentPage}
            setCurrentPage={setCurrentPage}
            pageSize={pageSize}
          />

          {/* AI Panel */}
          <AiPanel />
        </div>
      </main>
    </div>
  )
}
