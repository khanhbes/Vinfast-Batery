import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Code, Wifi, Cpu, Sparkles, Activity, ShieldCheck, Copy, Check, Lock, Terminal, RefreshCw } from 'lucide-react';

interface DeveloperSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onLockDeveloperMode: () => void;
}

export const DeveloperSettingsModal: React.FC<DeveloperSettingsModalProps> = ({
  isOpen,
  onClose,
  onLockDeveloperMode,
}) => {
  const [copied, setCopied] = useState(false);
  const [activeTab, setActiveTab] = useState<'network' | 'ai' | 'relay' | 'safety' | 'logs'>('network');
  const [cacheCleared, setCacheCleared] = useState(false);

  const handleCopyReport = () => {
    const report = `[EV_DEV_REPORT]
Timestamp: ${new Date().toISOString()}
App Version: 1.4.0 (Build 2026.08.31-PROD)
Platform: Android WebView API 34
Network: Gateway 38ms, Shelly LAN 192.168.1.188:80 (200 OK), Cloud MQTT Active
Device Binding: VINFAST_FELIZ_2025 -> shellyplus1pm-e86beae8
Capabilities: [relay, power_meter, thermal_sensor, bms_ble]
AI Model: FusionEngine v4.2.1 (MAPE 2.1%, weights: AI 0.65, Physics 0.35)
Safety Thresholds: Max 250V, Max 16A, Cutoff Temp 45°C
Relay State: CLOSED, HW Auto-cutoff Timer: 7200s
Security: Token REDACTED (Bearer ***)
Error Logs: 0 Fatal, 0 Warning`;

    navigator.clipboard?.writeText(report);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleClearCache = () => {
    setCacheCleared(true);
    setTimeout(() => setCacheCleared(false), 2000);
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/80 backdrop-blur-md"
          />

          <motion.div
            initial={{ scale: 0.95, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.95, opacity: 0 }}
            className="relative w-full max-w-md bg-[#080808] border border-emerald-500/30 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[88vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/10">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Terminal className="w-4 h-4" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-bold text-white">Tùy chọn nhà phát triển</h3>
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/40">
                      DEV_MODE
                    </span>
                  </div>
                  <p className="text-[11px] text-slate-400">Telemetry chuyên sâu & Chẩn đoán phần cứng</p>
                </div>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Sub-tabs for Developer Mode */}
            <div className="flex items-center gap-1.5 mt-4 p-1 bg-white/5 rounded-2xl border border-white/5 overflow-x-auto text-[11px] font-mono">
              {[
                { id: 'network', label: 'Mạng & Thiết bị' },
                { id: 'ai', label: 'AI Fusion' },
                { id: 'relay', label: 'Rơ le & Sạc' },
                { id: 'safety', label: 'An toàn' },
              ].map(t => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setActiveTab(t.id as any)}
                  className={`px-3 py-1.5 rounded-xl whitespace-nowrap font-bold transition-colors ${
                    activeTab === t.id
                      ? 'bg-emerald-500 text-slate-950 shadow'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {t.label}
                </button>
              ))}
            </div>

            {/* Content per Tab */}
            <div className="mt-4 space-y-3 font-mono text-xs">
              {activeTab === 'network' && (
                <div className="space-y-2.5">
                  <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Gateway Latency</span>
                      <span className="text-emerald-400 font-bold">38 ms</span>
                    </div>
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Shelly LAN Host</span>
                      <span className="text-white">192.168.1.188:80</span>
                    </div>
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Cloud MQTT Broker</span>
                      <span className="text-emerald-400">wss://mqtt.ev-cloud.internal (200 OK)</span>
                    </div>
                  </div>

                  <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Device ID</span>
                      <span className="text-white">shellyplus1pm-e86beae8</span>
                    </div>
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Active Binding</span>
                      <span className="text-emerald-400">VINFAST_FELIZ_2025</span>
                    </div>
                    <div className="flex items-center justify-between text-slate-400">
                      <span>Hardware Capabilities</span>
                      <span className="text-slate-300">[relay, pm, bms, thermal]</span>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'ai' && (
                <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Fusion Model Version</span>
                    <span className="text-emerald-400 font-bold">v4.2.1-prod</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Base AI ETA</span>
                    <span className="text-white">48 phút</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Physics CC-CV Model</span>
                    <span className="text-white">45 phút</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Personalized ETA Output</span>
                    <span className="text-emerald-400 font-bold">52 phút (Balancing)</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Model MAPE (Mean Error)</span>
                    <span className="text-emerald-400 font-bold">2.1%</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Fusion Weight Ratio</span>
                    <span className="text-white">AI: 0.65 / Physics: 0.35</span>
                  </div>
                </div>
              )}

              {activeTab === 'relay' && (
                <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Relay Hardware State</span>
                    <span className="text-emerald-400 font-bold">CLOSED (Energized)</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>HW Safety Auto-Cutoff Timer</span>
                    <span className="text-white">7200s (2.0 hrs remaining)</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Energy Baseline (kWh)</span>
                    <span className="text-white">3.250 kWh</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Telemetry Packet Rate</span>
                    <span className="text-emerald-400">1.0 Hz (99.8% coverage)</span>
                  </div>
                </div>
              )}

              {activeTab === 'safety' && (
                <div className="p-3.5 rounded-2xl bg-[#111] border border-white/5 space-y-2">
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Safety Policy Version</span>
                    <span className="text-emerald-400 font-bold">Policy v4.1 (Strict)</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Thermal Cutoff Threshold</span>
                    <span className="text-red-400 font-bold">45.0 °C</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Overvoltage Protection</span>
                    <span className="text-amber-400 font-bold">&gt; 250.0 V</span>
                  </div>
                  <div className="flex items-center justify-between text-slate-400">
                    <span>Max Overcurrent Limit</span>
                    <span className="text-amber-400 font-bold">16.0 A</span>
                  </div>
                </div>
              )}
            </div>

            {/* Actions & Report Export */}
            <div className="mt-5 space-y-2">
              <button
                type="button"
                onClick={handleCopyReport}
                className="w-full py-3 rounded-2xl bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-400 font-bold text-xs border border-emerald-500/30 flex items-center justify-center gap-2 transition-colors"
              >
                {copied ? <Check className="w-3.5 h-3.5 stroke-[3]" /> : <Copy className="w-3.5 h-3.5" />}
                {copied ? 'Đã sao chép báo cáo (Đã che token)' : 'Sao chép báo cáo chẩn đoán'}
              </button>

              <button
                type="button"
                onClick={handleClearCache}
                className="w-full py-2.5 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 text-xs font-bold border border-white/5 transition-colors"
              >
                {cacheCleared ? 'Đã xóa bộ nhớ đệm chẩn đoán!' : 'Xóa bộ nhớ đệm chẩn đoán cục bộ'}
              </button>

              <button
                type="button"
                onClick={() => {
                  onLockDeveloperMode();
                  onClose();
                }}
                className="w-full py-2.5 rounded-2xl bg-red-500/10 hover:bg-red-500/20 text-red-400 text-xs font-bold border border-red-500/20 flex items-center justify-center gap-2 transition-colors"
              >
                <Lock className="w-3.5 h-3.5" />
                Khóa lại Chế độ Nhà phát triển
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
