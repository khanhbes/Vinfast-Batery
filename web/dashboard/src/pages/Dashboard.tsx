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
  ArrowDownRight
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

interface TrendDataPoint {
  name: string;
  value: number;
}

export default function Dashboard() {
  const [kpis, setKpis] = useState<KpiCard[]>([]);
  const [trendData, setTrendData] = useState<TrendDataPoint[]>([]);
  const [alerts, setAlerts] = useState<AlertItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      setLoading(true);
      
      // Get dashboard stats from Firebase
      const stats = await firebaseService.getDashboardStats();
      
      // Get vehicles for alerts
      const vehicles = await firebaseService.getVehicles();
      const maintenanceTasks = await firebaseService.getMaintenanceTasks();
      
      // Create KPIs from real data
      const newKpis: KpiCard[] = [
        { 
          label: 'Tổng người dùng', 
          value: stats.totalUsers.toString(), 
          change: '+8%', 
          trend: 'up', 
          icon: Users, 
          color: 'text-blue-600', 
          bg: 'bg-blue-50' 
        },
        { 
          label: 'Xe đang hoạt động', 
          value: stats.activeVehicles.toString(), 
          change: '+3.2%', 
          trend: 'up', 
          icon: Car, 
          color: 'text-emerald-600', 
          bg: 'bg-emerald-50' 
        },
        { 
          label: 'Pin trung bình (SoH)', 
          value: `${stats.avgSoH}%`, 
          change: '+0.5%', 
          trend: 'up', 
          icon: Battery, 
          color: 'text-green-600', 
          bg: 'bg-green-50' 
        },
        { 
          label: 'Cảnh báo hôm nay', 
          value: stats.alertsToday.toString(), 
          change: '-25%', 
          trend: 'down', 
          icon: AlertTriangle, 
          color: 'text-orange-600', 
          bg: 'bg-orange-50' 
        },
      ];

      // Generate trend data (mock hourly data)
      const newTrendData = Array.from({ length: 24 }, (_, i) => ({
        name: `${i.toString().padStart(2, '0')}:00`,
        value: Math.floor(Math.random() * 1000) + stats.activeVehicles * 10,
      }));

      // Generate alerts from real data
      const newAlerts: AlertItem[] = [];
      
      // Low battery alerts
      const lowBatteryVehicles = vehicles.filter(v => v.currentBattery < 20);
      lowBatteryVehicles.forEach((vehicle, index) => {
        newAlerts.push({
          id: `low-battery-${index}`,
          type: 'warning',
          title: `Pin yếu trên xe ${vehicle.vinfastModelName || vehicle.vehicleName}`,
          description: `Xe có pin còn ${vehicle.currentBattery}%, SoH: ${vehicle.stateOfHealth.toFixed(1)}%`,
          timestamp: new Date().toISOString(),
          vehicle: vehicle.vinfastModelName || vehicle.vehicleName
        });
      });

      // Low SoH alerts
      const lowSoHVehicles = vehicles.filter(v => v.stateOfHealth < 80);
      lowSoHVehicles.forEach((vehicle, index) => {
        newAlerts.push({
          id: `low-soh-${index}`,
          type: 'error',
          title: `SoH pin thấp ${vehicle.vinfastModelName || vehicle.vehicleName}`,
          description: `SoH pin xuống ${vehicle.stateOfHealth.toFixed(1)}%, cần kiểm tra`,
          timestamp: new Date().toISOString(),
          vehicle: vehicle.vinfastModelName || vehicle.vehicleName
        });
      });

      // Maintenance alerts
      const overdueMaintenance = maintenanceTasks.filter(t => t.status === 'overdue');
      overdueMaintenance.forEach((task, index) => {
        newAlerts.push({
          id: `maintenance-${index}`,
          type: 'info',
          title: 'Bảo dưỡng trễ hẹn',
          description: `${task.description} - ${task.taskType}`,
          timestamp: task.dueDate?.toDate().toISOString() || new Date().toISOString()
        });
      });

      setKpis(newKpis);
      setTrendData(newTrendData);
      setAlerts(newAlerts.slice(0, 5)); // Show only 5 most recent alerts
    } catch (error) {
      console.error('Error loading dashboard data:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Đang tải dữ liệu...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">Tổng quan hệ thống</h1>
          <p className="text-muted-foreground mt-1">Theo dõi trạng thái và hiệu suất hệ thống quản lý pin VinFast</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2">
            <TrendingUp className="w-4 h-4" />
            Xuất báo cáo
          </Button>
          <Button className="gap-2" onClick={loadDashboardData}>
            <CheckCircle2 className="w-4 h-4" />
            Làm mới dữ liệu
          </Button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        {kpis.map((kpi, index) => (
          <motion.div
            key={kpi.label}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, delay: index * 0.1 }}
          >
            <Card className="border-border/50 bg-surface/50 backdrop-blur-sm hover:shadow-lg transition-all duration-300">
              <CardContent className="p-6">
                <div className="flex items-center justify-between">
                  <div className={cn("p-3 rounded-lg", kpi.bg)}>
                    <kpi.icon className={cn("w-6 h-6", kpi.color)} />
                  </div>
                  <div className="flex items-center gap-1">
                    {kpi.trend === 'up' ? (
                      <ArrowUpRight className="w-4 h-4 text-emerald-600" />
                    ) : (
                      <ArrowDownRight className="w-4 h-4 text-red-600" />
                    )}
                    <span className={cn(
                      "text-sm font-medium",
                      kpi.trend === 'up' ? "text-emerald-600" : "text-red-600"
                    )}>
                      {kpi.change}
                    </span>
                  </div>
                </div>
                <div className="mt-4">
                  <p className="text-2xl font-bold text-foreground">{kpi.value}</p>
                  <p className="text-sm text-muted-foreground mt-1">{kpi.label}</p>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        ))}
      </div>

      {/* Charts and Alerts */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Activity Chart */}
        <Card className="lg:col-span-2 border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-primary" />
              Hoạt động hệ thống 24h
            </CardTitle>
            <CardDescription>
              Số lượng xe hoạt động và mức tiêu thụ pin theo thời gian
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-[300px]">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={trendData}>
                  <defs>
                    <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.8}/>
                      <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0.1}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border/30" />
                  <XAxis 
                    dataKey="name" 
                    className="text-muted-foreground"
                    tick={{ fontSize: 12 }}
                  />
                  <YAxis 
                    className="text-muted-foreground"
                    tick={{ fontSize: 12 }}
                  />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: 'hsl(var(--surface))',
                      border: '1px solid hsl(var(--border))',
                      borderRadius: '8px'
                    }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="value" 
                    stroke="hsl(var(--primary))" 
                    fillOpacity={1} 
                    fill="url(#colorValue)"
                    strokeWidth={2}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Recent Alerts */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-orange-600" />
              Cảnh báo gần đây
            </CardTitle>
            <CardDescription>
              Các sự kiện và cảnh báo hệ thống
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {alerts.map((alert) => (
                <div key={alert.id} className="flex items-start gap-3 p-3 rounded-lg bg-surface-light/50 hover:bg-surface-light transition-colors">
                  <div className={cn(
                    "w-2 h-2 rounded-full mt-2 flex-shrink-0",
                    alert.type === 'error' && "bg-red-500",
                    alert.type === 'warning' && "bg-orange-500",
                    alert.type === 'info' && "bg-blue-500"
                  )} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">
                      {alert.title}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                      {alert.description}
                    </p>
                    <div className="flex items-center gap-2 mt-2">
                      <Clock className="w-3 h-3 text-muted-foreground" />
                      <span className="text-xs text-muted-foreground">
                        {new Date(alert.timestamp).toLocaleString('vi-VN')}
                      </span>
                      {alert.vehicle && (
                        <Badge variant="outline" className="text-xs">
                          {alert.vehicle}
                        </Badge>
                      )}
                    </div>
                  </div>
                </div>
              ))}
              {alerts.length === 0 && (
                <div className="text-center py-8">
                  <CheckCircle2 className="w-8 h-8 text-green-600 mx-auto mb-2" />
                  <p className="text-sm text-muted-foreground">Không có cảnh báo nào</p>
                </div>
              )}
            </div>
            <Button variant="ghost" className="w-full mt-4 text-sm">
              Xem tất cả cảnh báo
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
