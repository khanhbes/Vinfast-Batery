import { useState, useEffect } from 'react';
import { 
  Users, 
  Car, 
  Battery, 
  AlertTriangle, 
  CheckCircle2, 
  Clock,
  TrendingUp,
  ArrowUpRight,
  ArrowDownRight,
  Zap,
  PlugZap,
  Activity,
  Cpu
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer 
} from 'recharts';
import { motion } from 'framer-motion';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { KpiCard, AlertItem } from '@/types';
import { firebaseService } from '@/services/firebaseService';
import { useNavigate } from 'react-router-dom';

interface TrendDataPoint {
  name: string;
  powerKw: number;
}

export default function Dashboard() {
  const navigate = useNavigate();
  const [kpis, setKpis] = useState<KpiCard[]>([]);
  const [trendData, setTrendData] = useState<TrendDataPoint[]>([]);
  const [alerts, setAlerts] = useState<AlertItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeVehiclesCount, setActiveVehiclesCount] = useState(0);
  const [avgSoH, setAvgSoH] = useState(97.2);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      setLoading(true);
      
      // Get dashboard stats from Firebase
      const stats = await firebaseService.getDashboardStats();
      const vehicles = await firebaseService.getVehicles();
      const maintenanceTasks = await firebaseService.getMaintenanceTasks();
      
      setActiveVehiclesCount(stats.activeVehicles);
      if (stats.avgSoH > 0) setAvgSoH(stats.avgSoH);

      // Create synchronized KPIs with Emerald & EV tokens
      const newKpis: KpiCard[] = [
        { 
          label: 'Xe kết nối hoạt động', 
          value: stats.activeVehicles.toString(), 
          change: '+2 xe', 
          trend: 'up', 
          icon: Car, 
          color: 'text-emerald-500', 
          bg: 'bg-emerald-500/10' 
        },
        { 
          label: 'Sức khỏe pin TB (SoH)', 
          value: `${stats.avgSoH || 97.2}%`, 
          change: '+0.4%', 
          trend: 'up', 
          icon: Battery, 
          color: 'text-emerald-500', 
          bg: 'bg-emerald-500/10' 
        },
        { 
          label: 'Năng lượng nạp (24h)', 
          value: '48.6 kWh', 
          change: '+14.2%', 
          trend: 'up', 
          icon: Zap, 
          color: 'text-amber-500', 
          bg: 'bg-amber-500/10' 
        },
        { 
          label: 'Cảnh báo an toàn', 
          value: stats.alertsToday.toString(), 
          change: stats.alertsToday === 0 ? 'Tất cả an toàn' : '-2 cảnh báo', 
          trend: 'down', 
          icon: AlertTriangle, 
          color: stats.alertsToday > 0 ? 'text-red-500' : 'text-emerald-500', 
          bg: stats.alertsToday > 0 ? 'bg-red-500/10' : 'bg-emerald-500/10' 
        },
      ];

      // Simulated 24-hour charging telemetry curve
      const newTrendData: TrendDataPoint[] = [
        { name: '00:00', powerKw: 0.0 },
        { name: '02:00', powerKw: 0.0 },
        { name: '04:00', powerKw: 0.0 },
        { name: '06:00', powerKw: 1.2 },
        { name: '08:00', powerKw: 2.8 },
        { name: '10:00', powerKw: 3.4 },
        { name: '12:00', powerKw: 2.1 },
        { name: '14:00', powerKw: 1.8 },
        { name: '16:00', powerKw: 2.5 },
        { name: '18:00', powerKw: 3.5 },
        { name: '20:00', powerKw: 3.4 },
        { name: '22:00', powerKw: 2.2 },
      ];

      // Generate alerts from real data
      const newAlerts: AlertItem[] = [];
      
      const lowBatteryVehicles = vehicles.filter(v => v.currentBattery < 20);
      lowBatteryVehicles.forEach((vehicle, index) => {
        newAlerts.push({
          id: `low-battery-${index}`,
          type: 'warning',
          title: `Mức pin thấp trên ${vehicle.vinfastModelName || vehicle.vehicleName}`,
          description: `Pin còn ${vehicle.currentBattery}%, SoH: ${vehicle.stateOfHealth.toFixed(1)}%`,
          timestamp: new Date().toISOString(),
          vehicle: vehicle.vinfastModelName || vehicle.vehicleName
        });
      });

      const lowSoHVehicles = vehicles.filter(v => v.stateOfHealth < 80);
      lowSoHVehicles.forEach((vehicle, index) => {
        newAlerts.push({
          id: `low-soh-${index}`,
          type: 'error',
          title: `SoH pin cần kiểm tra trên ${vehicle.vinfastModelName || vehicle.vehicleName}`,
          description: `SoH còn ${vehicle.stateOfHealth.toFixed(1)}%, khuyến nghị hiệu chuẩn`,
          timestamp: new Date().toISOString(),
          vehicle: vehicle.vinfastModelName || vehicle.vehicleName
        });
      });

      const overdueMaintenance = maintenanceTasks.filter(t => t.status === 'overdue');
      overdueMaintenance.forEach((task, index) => {
        newAlerts.push({
          id: `maintenance-${index}`,
          type: 'info',
          title: 'Lịch bảo dưỡng',
          description: `${task.description} - ${task.taskType}`,
          timestamp: task.dueDate?.toDate().toISOString() || new Date().toISOString()
        });
      });

      setKpis(newKpis);
      setTrendData(newTrendData);
      setAlerts(newAlerts.slice(0, 5));
    } catch (error) {
      console.error('Error loading dashboard data:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-emerald-500/20 border-t-emerald-500 rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-sm text-muted-foreground font-medium">Đang tải trung tâm điều khiển Cockpit...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6 animate-fadeIn">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-foreground tracking-tight">
            Tổng quan hệ thống
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Trung tâm điều khiển pin & Smart Charger đa nền tảng
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <Button 
            variant="outline" 
            className="h-10 px-4 rounded-xl gap-2 font-medium border-border/70 hover:border-emerald-500/50"
            onClick={() => navigate('/settings')}
          >
            <PlugZap className="w-4 h-4 text-emerald-500" />
            Smart Charger
          </Button>
          <Button 
            className="h-10 px-4 rounded-xl gap-2 font-semibold bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-600/20"
            onClick={loadDashboardData}
          >
            <Activity className="w-4 h-4" />
            Đồng bộ thời gian thực
          </Button>
        </div>
      </div>

      {/* Hero EV Cockpit Status Banner */}
      <Card className="border-border/60 bg-gradient-to-r from-card via-card to-emerald-950/20 overflow-hidden relative shadow-md">
        <div className="absolute top-0 right-0 w-96 h-96 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />
        <CardContent className="p-6">
          <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6">
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <span className="relative flex h-3 w-3">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
                </span>
                <Badge variant="outline" className="border-emerald-500/40 text-emerald-400 bg-emerald-500/10 font-semibold text-xs px-2.5 py-0.5">
                  Cockpit Live · Trực tuyến
                </Badge>
                <span className="text-xs text-muted-foreground">Firebase Firestore Real-time</span>
              </div>
              <div>
                <h2 className="text-xl sm:text-2xl font-extrabold text-foreground">
                  VinFast Battery Management System
                </h2>
                <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
                  Giám sát {activeVehiclesCount} xe kết nối, tự động dự đoán thời gian sạc bằng mô hình Gradient Boosting và bảo vệ ngắt rơ-le Shelly tự động.
                </p>
              </div>
            </div>

            <div className="flex items-center gap-4 bg-muted/40 p-4 rounded-2xl border border-border/50">
              <div className="p-3 bg-emerald-500/10 rounded-xl border border-emerald-500/20">
                <Battery className="w-8 h-8 text-emerald-500" />
              </div>
              <div>
                <div className="text-2xl font-black text-foreground">{avgSoH.toFixed(1)}%</div>
                <div className="text-xs font-semibold text-muted-foreground">SoH trung bình đội xe</div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* KPI Cards Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {kpis.map((kpi, index) => (
          <motion.div
            key={kpi.label}
            initial={{ opacity: 0.8, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25, delay: index * 0.04 }}
            className="min-w-0"
          >
            <Card className="border-border/60 bg-card hover:border-emerald-500/40 transition-colors shadow-sm">
              <CardContent className="p-5">
                <div className="flex items-center justify-between">
                  <div className={cn("p-2.5 rounded-xl", kpi.bg)}>
                    <kpi.icon className={cn("w-5 h-5", kpi.color)} />
                  </div>
                  <div className="flex items-center gap-1 text-xs font-semibold">
                    {kpi.trend === 'up' ? (
                      <ArrowUpRight className="w-3.5 h-3.5 text-emerald-500" />
                    ) : (
                      <ArrowDownRight className="w-3.5 h-3.5 text-emerald-500" />
                    )}
                    <span className="text-emerald-500">{kpi.change}</span>
                  </div>
                </div>
                <div className="mt-4">
                  <p className="text-2xl font-extrabold tracking-tight text-foreground">{kpi.value}</p>
                  <p className="text-xs font-medium text-muted-foreground mt-1">{kpi.label}</p>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        ))}
      </div>

      {/* Quick Action Toolbar */}
      <div className="flex flex-wrap items-center gap-3 p-3 bg-card border border-border/60 rounded-2xl">
        <span className="text-xs font-bold uppercase tracking-wider text-muted-foreground px-2">Thao tác nhanh:</span>
        <Button 
          variant="outline" 
          size="sm" 
          className="h-9 px-3.5 rounded-xl gap-2 text-xs font-semibold border-border/70 hover:bg-emerald-500/10 hover:text-emerald-500 hover:border-emerald-500/30"
          onClick={() => navigate('/charging')}
        >
          <Zap className="w-3.5 h-3.5 text-emerald-500" />
          Phiên sạc pin
        </Button>
        <Button 
          variant="outline" 
          size="sm" 
          className="h-9 px-3.5 rounded-xl gap-2 text-xs font-semibold border-border/70 hover:bg-emerald-500/10 hover:text-emerald-500 hover:border-emerald-500/30"
          onClick={() => navigate('/settings')}
        >
          <Cpu className="w-3.5 h-3.5 text-indigo-400" />
          Developer AI Studio
        </Button>
        <Button 
          variant="outline" 
          size="sm" 
          className="h-9 px-3.5 rounded-xl gap-2 text-xs font-semibold border-border/70 hover:bg-emerald-500/10 hover:text-emerald-500 hover:border-emerald-500/30"
          onClick={() => navigate('/trip-planner')}
        >
          <TrendingUp className="w-3.5 h-3.5 text-amber-400" />
          Lập kế hoạch lộ trình
        </Button>
      </div>

      {/* Charts and Alerts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Activity Chart */}
        <Card className="lg:col-span-2 border-border/60 bg-card shadow-sm">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-base font-bold flex items-center gap-2">
                <TrendingUp className="w-4 h-4 text-emerald-500" />
                Công suất sạc thực tế (kW) 24h
              </CardTitle>
              <Badge variant="outline" className="text-xs border-emerald-500/30 text-emerald-400">
                Đỉnh 3.5 kW
              </Badge>
            </div>
            <CardDescription className="text-xs">
              Mức tiêu thụ và công suất nạp rơ-le Shelly ghi nhận theo mốc thời gian
            </CardDescription>
          </CardHeader>
          <CardContent className="pt-4">
            <div className="h-[280px]">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={trendData}>
                  <defs>
                    <linearGradient id="emeraldGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#10B981" stopOpacity={0.4}/>
                      <stop offset="95%" stopColor="#10B981" stopOpacity={0.0}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#262626" opacity={0.5} />
                  <XAxis 
                    dataKey="name" 
                    stroke="#737373"
                    tick={{ fontSize: 11 }}
                  />
                  <YAxis 
                    stroke="#737373"
                    tick={{ fontSize: 11 }}
                    unit=" kW"
                  />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: '#121212',
                      border: '1px solid #262626',
                      borderRadius: '10px',
                      fontSize: '12px'
                    }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="powerKw" 
                    stroke="#10B981" 
                    strokeWidth={2.5}
                    fillOpacity={1} 
                    fill="url(#emeraldGradient)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Recent Alerts */}
        <Card className="border-border/60 bg-card shadow-sm">
          <CardHeader className="pb-2">
            <CardTitle className="text-base font-bold flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-500" />
              Cảnh báo & sự kiện gần đây
            </CardTitle>
            <CardDescription className="text-xs">
              Các thông báo an toàn pin và hệ thống
            </CardDescription>
          </CardHeader>
          <CardContent className="pt-2">
            <div className="space-y-3">
              {alerts.map((alert) => (
                <div key={alert.id} className="flex items-start gap-3 p-3 rounded-xl bg-muted/30 border border-border/40 hover:bg-muted/50 transition-colors">
                  <div className={cn(
                    "w-2 h-2 rounded-full mt-1.5 flex-shrink-0",
                    alert.type === 'error' && "bg-red-500",
                    alert.type === 'warning' && "bg-amber-500",
                    alert.type === 'info' && "bg-blue-500"
                  )} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-semibold text-foreground truncate">
                      {alert.title}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">
                      {alert.description}
                    </p>
                    <div className="flex items-center gap-2 mt-1.5">
                      <Clock className="w-3 h-3 text-muted-foreground" />
                      <span className="text-[10px] text-muted-foreground">
                        {new Date(alert.timestamp).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })}
                      </span>
                      {alert.vehicle && (
                        <Badge variant="outline" className="text-[10px] py-0 px-1.5 border-border">
                          {alert.vehicle}
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>
              ))}
              {alerts.length === 0 && (
                <div className="text-center py-8">
                  <CheckCircle2 className="w-8 h-8 text-emerald-500 mx-auto mb-2" />
                  <p className="text-xs text-muted-foreground">Không có cảnh báo nào · Hệ thống an toàn</p>
                </div>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
