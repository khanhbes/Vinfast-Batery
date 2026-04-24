/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  LayoutDashboard, 
  MapPin, 
  Battery, 
  Wrench, 
  User, 
  Zap, 
  Navigation,
  Cloud,
  Thermometer,
  ChevronRight,
  TrendingUp,
  AlertCircle,
  Trophy,
  History,
  Settings,
  Plus,
  Info,
  Car,
  Bell,
  Languages,
  BookOpen,
  HelpCircle,
  ChevronRight as ChevronRightIcon
} from 'lucide-react';
import { cn } from './lib/utils';
import { BatteryState, Trip, MaintenanceItem, UserProfile } from './types';
import { predictBatteryConsumption } from './services/geminiService';
import { 
  LineChart, 
  Line, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer,
  AreaChart,
  Area
} from 'recharts';

// --- Mock Data ---
const INITIAL_BATTERY: BatteryState = {
  percentage: 78,
  soh: 96,
  estimatedRange: 62,
  temp: 32
};

const INITIAL_USER: UserProfile = {
  name: "Khanh Nhim",
  weight: 65,
  vehicleModel: "VinFast Feliz Neo",
  totalOdo: 1245
};

const INITIAL_MAINTENANCE: MaintenanceItem[] = [
  { id: '1', name: 'Lốp xe (Tires)', currentKm: 1245, limitKm: 10000, status: 'good', icon: '🛞' },
  { id: '2', name: 'Má phanh (Brakes)', currentKm: 1245, limitKm: 5000, status: 'good', icon: '🛑' },
  { id: '3', name: 'Dầu láp (Gear Oil)', currentKm: 1245, limitKm: 3000, status: 'warning', icon: '⚙️' },
];

const MOCK_HISTORY = [
  { day: 'Mon', usage: 12 },
  { day: 'Tue', usage: 15 },
  { day: 'Wed', usage: 8 },
  { day: 'Thu', usage: 20 },
  { day: 'Fri', usage: 18 },
  { day: 'Sat', usage: 25 },
  { day: 'Sun', usage: 10 },
];

// --- Components ---

const TripPlanner = ({ user, battery }: { user: UserProfile, battery: BatteryState }) => {
  const [destination, setDestination] = useState('');
  const [prediction, setPrediction] = useState<{ consumption: number, reasoning: string } | null>(null);
  const [loading, setLoading] = useState(false);

  const handlePredict = async () => {
    if (!destination) return;
    setLoading(true);
    const distance = Math.floor(Math.random() * 20) + 5;
    const res = await predictBatteryConsumption(distance, user.weight, "Sunny", 32);
    setPrediction({ ...res, consumption: Math.round(res.consumption) });
    setLoading(false);
  };

  return (
    <div className="space-y-6">
      <div className="panel">
        <div className="panel-header">
          <span>Dự đoán hành trình</span>
          <span>AI ENGINE</span>
        </div>
        <div className="relative">
          <input 
            type="text" 
            placeholder="Bạn muốn đi đâu?"
            className="w-full bg-white/5 border border-white/10 rounded-xl py-3 px-10 text-sm text-white focus:outline-none focus:ring-1 focus:ring-accent"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
          />
          <MapPin className="absolute left-3 top-1/2 -translate-y-1/2 text-text-dim" size={16} />
          <button 
            onClick={handlePredict}
            disabled={loading}
            className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 bg-accent rounded-lg text-white disabled:opacity-50"
          >
            {loading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <ChevronRight size={16} />}
          </button>
        </div>
      </div>

      <AnimatePresence>
        {prediction && (
          <motion.div 
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="panel space-y-4"
          >
            <div className="flex items-center justify-between text-[11px] text-text-dim uppercase tracking-wider">
              <span>Kết quả dự báo</span>
              <span className="text-accent">Optimized</span>
            </div>
            
            <div className="bg-white/[0.03] p-4 rounded-xl border border-white/5">
              <div className="text-[11px] text-text-dim mb-1 uppercase">Dự báo tiêu hao</div>
              <div className="text-3xl font-bold text-warning">{prediction.consumption}%</div>
              <div className="text-[10px] mt-1">
                An toàn (Còn <span className={cn(battery.percentage - prediction.consumption < 15 ? "text-danger" : "text-success")}>{battery.percentage - prediction.consumption}%</span> lúc đến nơi)
              </div>
            </div>

            <p className="text-[12px] text-text-dim leading-relaxed italic">
              "{prediction.reasoning}"
            </p>

            <button className="w-full py-3 bg-accent rounded-xl text-white text-sm font-bold shadow-lg shadow-accent/20">
              XÁC NHẬN & BẮT ĐẦU
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="space-y-3">
        <h3 className="text-[11px] font-bold text-text-dim uppercase tracking-widest">Chuyến đi gần đây</h3>
        {[1, 2].map((i) => (
          <div key={i} className="flex items-center justify-between p-4 bg-white/[0.03] rounded-xl border border-white/5">
            <div className="flex items-center gap-3">
              <History size={16} className="text-text-dim" />
              <div>
                <p className="text-sm font-medium text-white">Nhà &rarr; Công ty</p>
                <p className="text-[10px] text-text-dim">12 km | 24 phút</p>
              </div>
            </div>
            <span className="text-sm font-bold text-warning">11.4%</span>
          </div>
        ))}
      </div>
    </div>
  );
};

const BatteryHealth = ({ battery }: { battery: BatteryState }) => (
  <div className="space-y-6">
    <div className="panel text-center py-8">
      <div className="panel-header">
        <span>Sức khỏe Pin (SoH)</span>
        <span>LFP TECH</span>
      </div>
      <div className="text-5xl font-bold text-success mb-2">{battery.soh}%</div>
      <p className="text-[11px] text-text-dim uppercase tracking-widest">Trạng thái: Rất tốt</p>
    </div>

    <div className="panel space-y-4">
      <div className="panel-header">
        <span>Lịch sử sử dụng</span>
        <span>7 NGÀY</span>
      </div>
      <div className="h-40 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={MOCK_HISTORY}>
            <defs>
              <linearGradient id="colorUsage" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#008DFF" stopOpacity={0.3}/>
                <stop offset="95%" stopColor="#008DFF" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
            <XAxis dataKey="day" stroke="#888" fontSize={10} tickLine={false} axisLine={false} />
            <Area type="monotone" dataKey="usage" stroke="#008DFF" fillOpacity={1} fill="url(#colorUsage)" strokeWidth={2} />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>

    <div className="panel">
      <div className="panel-header">
        <span>Gamification</span>
        <span>DRIVER SCORE</span>
      </div>
      <div className="text-center mb-6">
        <div className="text-5xl font-bold text-white">88</div>
        <div className="text-[11px] text-success font-bold uppercase tracking-widest mt-1">Tay lái sinh thái (Eco)</div>
      </div>
      
      <div className="space-y-3 mb-6">
        <div className="flex justify-between text-[12px]">
          <span className="text-text-dim">Thốc ga</span>
          <span className="text-warning">12% thời gian</span>
        </div>
        <div className="flex justify-between text-[12px]">
          <span className="text-text-dim">Phanh gấp</span>
          <span className="text-danger">4% thời gian</span>
        </div>
      </div>

      <div className="text-[11px] text-text-dim uppercase tracking-widest mb-3">Huy hiệu đã đạt</div>
      <div className="flex gap-3">
        {['🌿', '⚡', '🏆'].map((emoji, i) => (
          <div key={i} className="w-10 h-10 bg-white/5 rounded-xl flex items-center justify-center text-xl border border-white/10">
            {emoji}
          </div>
        ))}
      </div>
    </div>
  </div>
);

const Maintenance = ({ items: initialItems }: { items: MaintenanceItem[] }) => {
  const [items, setItems] = useState(initialItems);
  const [isAdding, setIsAdding] = useState(false);
  const [newItem, setNewItem] = useState({ name: '', limitKm: '' });

  const handleAddItem = () => {
    if (!newItem.name || !newItem.limitKm) return;
    const item: MaintenanceItem = {
      id: Date.now().toString(),
      name: newItem.name,
      currentKm: 0,
      limitKm: parseInt(newItem.limitKm),
      status: 'good',
      icon: '🔧'
    };
    setItems([...items, item]);
    setNewItem({ name: '', limitKm: '' });
    setIsAdding(false);
  };

  return (
    <div className="space-y-6">
      <div className="panel flex-1">
        <div className="panel-header">
          <span>Bảo dưỡng cơ học</span>
          <button 
            onClick={() => setIsAdding(!isAdding)}
            className="flex items-center gap-1 text-accent font-bold text-[10px] uppercase tracking-wider"
          >
            <Plus size={14} />
            Thêm mục
          </button>
        </div>

        <AnimatePresence>
          {isAdding && (
            <motion.div 
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              className="overflow-hidden mb-6"
            >
              <div className="bg-white/[0.03] border border-white/10 rounded-2xl p-4 space-y-3">
                <input 
                  type="text" 
                  placeholder="Tên linh kiện (VD: Xích tải)"
                  className="w-full bg-white/5 border border-white/10 rounded-xl py-2.5 px-4 text-sm text-white focus:outline-none focus:ring-1 focus:ring-accent"
                  value={newItem.name}
                  onChange={(e) => setNewItem({...newItem, name: e.target.value})}
                />
                <input 
                  type="number" 
                  placeholder="Định mức bảo dưỡng (km)"
                  className="w-full bg-white/5 border border-white/10 rounded-xl py-2.5 px-4 text-sm text-white focus:outline-none focus:ring-1 focus:ring-accent"
                  value={newItem.limitKm}
                  onChange={(e) => setNewItem({...newItem, limitKm: e.target.value})}
                />
                <div className="flex gap-2">
                  <button 
                    onClick={handleAddItem}
                    className="flex-1 py-2.5 bg-accent rounded-xl text-white text-xs font-bold"
                  >
                    XÁC NHẬN
                  </button>
                  <button 
                    onClick={() => setIsAdding(false)}
                    className="flex-1 py-2.5 bg-white/5 rounded-xl text-white text-xs font-bold"
                  >
                    HỦY
                  </button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        <div className="space-y-5">
          {items.map((item) => (
            <div key={item.id} className="maintenance-item">
              <div className="flex justify-between items-end mb-1.5">
                <div className="flex items-center gap-2">
                  <span className="text-lg">{item.icon}</span>
                  <label className="text-[12px] text-white font-medium">{item.name}</label>
                </div>
                <span className="text-[10px] text-text-dim">{item.limitKm - item.currentKm} km còn lại</span>
              </div>
              <div className="h-1 bg-white/5 rounded-full overflow-hidden">
                <motion.div 
                  initial={{ width: 0 }}
                  animate={{ width: `${(item.currentKm / item.limitKm) * 100}%` }}
                  className={cn(
                    "h-full rounded-full",
                    item.status === 'good' ? "bg-success" : item.status === 'warning' ? "bg-warning" : "bg-danger"
                  )}
                />
              </div>
              {item.status === 'critical' && (
                <p className="text-[10px] text-danger mt-1 font-medium">Cần kiểm tra ngay (Hard-brake detected)</p>
              )}
            </div>
          ))}
        </div>
      </div>

      <div className="panel bg-accent/10 border-accent/20">
        <div className="flex items-center gap-3 mb-2">
          <Settings className="text-accent" size={18} />
          <p className="text-sm font-bold text-white">Cập nhật Phần mềm</p>
        </div>
        <p className="text-[11px] text-text-dim mb-4">Phiên bản v2.4.1 sẵn sàng cho Feliz Neo. Tối ưu hóa hiệu suất pin LFP.</p>
        <button className="w-full py-3 bg-accent rounded-xl text-white text-xs font-bold">
          CẬP NHẬT NGAY
        </button>
      </div>
    </div>
  );
};

const Home = ({ battery, user }: { battery: BatteryState, user: UserProfile }) => (
  <div className="space-y-8 flex flex-col items-center">
    {/* Vehicle Visual Section */}
    <div className="relative w-full aspect-square max-w-[300px] flex items-center justify-center">
      {/* Glow effect behind vehicle */}
      <div className="absolute inset-0 bg-accent/20 blur-[80px] rounded-full" />
      
      {/* Mock 3D Vehicle Visual (Using a high-quality placeholder image or stylized representation) */}
      <motion.div 
        initial={{ y: 10, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ duration: 0.8, ease: "easeOut" }}
        className="relative z-10"
      >
        <img 
          src="https://picsum.photos/seed/scooter/600/400" 
          alt="VinFast Feliz Neo" 
          className="w-full h-auto drop-shadow-[0_20px_50px_rgba(0,141,255,0.3)] rounded-2xl"
          referrerPolicy="no-referrer"
        />
      </motion.div>

      {/* Floating Info Tags */}
      <motion.div 
        initial={{ x: -20, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        transition={{ delay: 0.5 }}
        className="absolute left-0 top-1/4 glass px-3 py-1.5 rounded-full text-[10px] font-bold flex items-center gap-2"
      >
        <div className="w-2 h-2 bg-success rounded-full animate-pulse" />
        SYSTEM READY
      </motion.div>

      <motion.div 
        initial={{ x: 20, opacity: 0 }}
        animate={{ x: 0, opacity: 1 }}
        transition={{ delay: 0.7 }}
        className="absolute right-0 bottom-1/4 glass px-3 py-1.5 rounded-full text-[10px] font-bold flex items-center gap-2"
      >
        <Thermometer size={12} className="text-warning" />
        {battery.temp}°C
      </motion.div>
    </div>

    {/* Quick Stats */}
    <div className="w-full grid grid-cols-3 gap-4">
      <div className="panel flex flex-col items-center justify-center p-4 text-center">
        <span className="text-2xl font-bold text-white">{battery.percentage}%</span>
        <span className="text-[10px] text-text-dim uppercase tracking-wider">Battery</span>
      </div>
      <div className="panel flex flex-col items-center justify-center p-4 text-center border-accent/30 bg-accent/5">
        <span className="text-2xl font-bold text-accent">{battery.estimatedRange}</span>
        <span className="text-[10px] text-accent uppercase tracking-wider">Range (km)</span>
      </div>
      <div className="panel flex flex-col items-center justify-center p-4 text-center">
        <span className="text-2xl font-bold text-white">{user.totalOdo}</span>
        <span className="text-[10px] text-text-dim uppercase tracking-wider">ODO (km)</span>
      </div>
    </div>

    {/* Status Message */}
    <div className="w-full p-4 bg-white/[0.03] rounded-2xl border border-white/5 flex items-center gap-4">
      <div className="w-10 h-10 bg-success/10 rounded-full flex items-center justify-center text-success">
        <Zap size={20} />
      </div>
      <div>
        <p className="text-sm font-bold text-white">LFP Battery Optimized</p>
        <p className="text-xs text-text-dim">Your vehicle is in peak condition.</p>
      </div>
    </div>
  </div>
);

const SettingsPage = ({ user }: { user: UserProfile }) => {
  const sections = [
    {
      title: "Thông tin",
      icon: Info,
      items: [
        { label: "Thông tin cá nhân", value: user.name },
        { label: "Tài khoản", value: "khanhnhim2110@gmail.com" }
      ]
    },
    {
      title: "Garage",
      icon: Car,
      items: [
        { label: "Thông tin xe", value: "Đã kết nối" },
        { label: "Tên xe", value: user.vehicleModel },
        { label: "Thêm xe mới", value: "Thêm", action: true }
      ]
    },
    {
      title: "Ứng dụng",
      icon: Settings,
      items: [
        { label: "Phiên bản", value: "v2.4.1" },
        { label: "Bật thông báo", toggle: true },
        { label: "Đổi ngôn ngữ", value: "Tiếng Việt" },
        { label: "Hướng dẫn sử dụng", value: "Xem", action: true },
        { label: "Trợ giúp", value: "Liên hệ", action: true }
      ]
    }
  ];

  return (
    <div className="space-y-6 flex flex-col items-center pt-4 pb-10">
      {/* New Settings Sections */}
      <div className="w-full space-y-4 px-2">
        {sections.map((section, idx) => (
          <div key={idx} className="space-y-3">
            <div className="flex items-center gap-2 px-2 pt-4">
              <section.icon size={16} className="text-accent" />
              <h3 className="text-[11px] font-bold text-text-dim uppercase tracking-widest">{section.title}</h3>
            </div>
            <div className="bg-white/[0.03] border border-white/5 rounded-[32px] overflow-hidden">
              {section.items.map((item, i) => (
                <div 
                  key={i} 
                  className={cn(
                    "flex items-center justify-between p-5 active:bg-white/5 transition-colors",
                    i !== section.items.length - 1 && "border-b border-white/5"
                  )}
                >
                  <span className="text-sm text-white/80 font-medium">{item.label}</span>
                  <div className="flex items-center gap-2">
                    {item.toggle ? (
                      <div className="w-10 h-5 bg-accent rounded-full relative">
                        <div className="absolute right-1 top-1 w-3 h-3 bg-white rounded-full" />
                      </div>
                    ) : (
                      <span className={cn("text-xs", item.action ? "text-accent font-bold" : "text-text-dim")}>
                        {item.value}
                      </span>
                    )}
                    {!item.toggle && <ChevronRightIcon size={14} className="text-text-dim" />}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* About Card matching the provided image exactly - Moved to bottom */}
      <div className="w-full bg-gradient-to-b from-[#E3F2FD]/10 to-[#BBDEFB]/5 backdrop-blur-3xl border border-white/20 rounded-[48px] p-12 flex flex-col items-center text-center shadow-[0_20px_50px_rgba(0,0,0,0.3)] relative overflow-hidden mt-8">
        {/* Soft blue glow */}
        <div className="absolute -top-24 -right-24 w-48 h-48 bg-blue-500/20 blur-[60px] rounded-full" />
        <div className="absolute -bottom-24 -left-24 w-48 h-48 bg-blue-400/10 blur-[60px] rounded-full" />
        
        <div className="w-24 h-24 bg-[#0D47A1] rounded-[32px] flex items-center justify-center shadow-2xl mb-8 relative z-10">
          <Zap size={48} className="text-white fill-white" />
        </div>

        <h2 className="text-[32px] font-bold text-white mb-2 relative z-10 tracking-tight">VinFast Battery</h2>
        <p className="text-gray-400 text-base mb-10 relative z-10 font-medium">Quản lý pin xe máy điện thông minh</p>

        <div className="w-full h-[1px] bg-white/10 mb-8 relative z-10" />

        <p className="text-gray-500 text-sm flex items-center gap-2 relative z-10 font-medium">
          <span className="text-lg leading-none">©</span> 2026 VinFast Battery Team
        </p>
      </div>

      {/* Logout Button matching the image exactly */}
      <button className="w-full py-6 border border-red-500/20 bg-red-500/[0.03] rounded-[32px] flex items-center justify-center gap-4 text-red-500 font-bold text-lg active:scale-[0.98] transition-transform mt-8">
        <div className="rotate-180">
          <History size={24} />
        </div>
        <span>Đăng xuất</span>
      </button>

      {/* App Version Info */}
      <div className="text-center pt-4 pb-6">
        <p className="text-[10px] text-text-dim uppercase tracking-[0.2em] font-bold opacity-50">Build v2.4.1-stable</p>
      </div>
    </div>
  );
};

export default function App() {
  const [activeTab, setActiveTab] = useState('home');
  const [battery] = useState<BatteryState>(INITIAL_BATTERY);
  const [user] = useState<UserProfile>(INITIAL_USER);
  const [maintenance] = useState<MaintenanceItem[]>(INITIAL_MAINTENANCE);

  const tabs = [
    { id: 'home', icon: LayoutDashboard, label: 'Home' },
    { id: 'planner', icon: MapPin, label: 'Trip' },
    { id: 'health', icon: Battery, label: 'Health' },
    { id: 'maintenance', icon: Wrench, label: 'Service' },
    { id: 'settings', icon: User, label: 'Settings' },
  ];

  return (
    <div className="min-h-screen flex items-center justify-center p-4 lg:p-8 bg-black">
      <div className="w-full max-w-[1200px] h-full lg:h-[800px] grid grid-cols-1 lg:grid-cols-[320px_1fr_320px] gap-6">
        
        {/* Title Area - Desktop Only */}
        <div className="hidden lg:flex col-span-3 justify-between items-end mb-2">
          <div className="text-2xl font-light text-white">VinFast <span className="font-bold text-accent">Feliz Neo</span></div>
          <div className="text-right">
            <div className="text-[12px] text-text-dim uppercase tracking-wider">Hệ thống AI</div>
            <div className="text-[14px] text-success font-medium">● Hoạt động ổn định</div>
          </div>
        </div>

        {/* Left Column - Desktop Only */}
        <aside className="hidden lg:flex flex-col gap-6 overflow-y-auto pr-2">
          <div className="panel">
            <div className="panel-header">
              <span>Quick Actions</span>
            </div>
            <div className="grid gap-3">
              <button className="w-full py-3 bg-accent rounded-xl text-white text-xs font-bold">START TRIP</button>
              <button className="w-full py-3 bg-white/5 border border-white/10 rounded-xl text-white text-xs font-bold">CHARGE PIN</button>
            </div>
          </div>
          <Maintenance items={maintenance} />
        </aside>

        {/* Center: Main Dashboard (Phone Mockup) */}
        <div className="flex justify-center items-center">
          <div className="phone-mockup w-full max-w-[360px] h-[720px] flex flex-col bg-black">
            <div className="flex-1 flex flex-col p-6 pt-10 overflow-y-auto">
              {/* Android Status Bar Mockup */}
              <div className="flex justify-between text-[12px] text-text-dim mb-8 px-2">
                <span className="font-bold">22:25</span>
                <div className="flex items-center gap-2">
                  <Cloud size={14} />
                  <Zap size={14} className="text-accent" />
                  <div className="w-6 h-3 border border-text-dim rounded-[2px] relative">
                    <div className="absolute left-0 top-0 bottom-0 bg-accent w-[80%]" />
                  </div>
                </div>
              </div>

              <AnimatePresence mode="wait">
                <motion.div
                  key={activeTab}
                  initial={{ opacity: 0, scale: 0.98 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.98 }}
                  transition={{ duration: 0.2 }}
                  className="flex-1"
                >
                  {activeTab === 'home' && <Home battery={battery} user={user} />}
                  {activeTab === 'planner' && <TripPlanner user={user} battery={battery} />}
                  {activeTab === 'health' && <BatteryHealth battery={battery} />}
                  {activeTab === 'maintenance' && <Maintenance items={maintenance} />}
                  {activeTab === 'settings' && <SettingsPage user={user} />}
                </motion.div>
              </AnimatePresence>

              {/* Bottom Navigation - Android Style (Multi-item layout) */}
              <nav className="mt-auto pt-6 pb-4 border-t border-white/10 flex items-center justify-around relative">
                {tabs.map((tab) => (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id)}
                    className={cn(
                      "flex flex-col items-center gap-1 transition-all relative px-2",
                      activeTab === tab.id ? "text-accent" : "text-text-dim hover:text-white"
                    )}
                  >
                    <tab.icon size={20} className={cn(
                      "transition-transform",
                      activeTab === tab.id && "scale-110"
                    )} />
                    <span className="text-[10px] font-bold uppercase tracking-widest">{tab.label}</span>
                    {activeTab === tab.id && (
                      <motion.div 
                        layoutId="activeTab"
                        className="absolute -top-6 left-0 right-0 h-0.5 bg-accent rounded-full shadow-[0_0_10px_rgba(0,141,255,0.5)]"
                      />
                    )}
                  </button>
                ))}
              </nav>
            </div>
          </div>
        </div>

        {/* Right Column - Desktop Only */}
        <aside className="hidden lg:flex flex-col gap-6 overflow-y-auto pl-2">
          <BatteryHealth battery={battery} />
          <div className="panel bg-accent text-white border-none">
            <div className="text-[13px] font-bold">Zero-Touch Sync</div>
            <div className="text-[11px] opacity-80 mt-1">Đang tự động ghi nhận chuyến đi ngầm...</div>
          </div>
        </aside>

      </div>
    </div>
  );
}
