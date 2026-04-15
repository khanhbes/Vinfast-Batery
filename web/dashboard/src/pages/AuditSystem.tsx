import { useState, useEffect } from 'react';
import { 
  Shield, 
  Search, 
  Filter, 
  Download, 
  User,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Clock,
  Activity,
  Battery,
  Car,
  Zap
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';

interface AuditLog {
  id: string;
  action: string;
  user: string;
  target: string;
  description: string;
  timestamp: string;
  status: 'success' | 'warning' | 'error';
  ip: string;
  userAgent: string;
}
import { firebaseService, MaintenanceTask } from '@/services/firebaseService';

export default function AuditSystem() {
  const [searchTerm, setSearchTerm] = useState('');
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [maintenanceTasks, setMaintenanceTasks] = useState<MaintenanceTask[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadAuditData();
  }, []);

  const loadAuditData = async () => {
    try {
      setLoading(true);
      
      // Get all data from Firebase
      const [vehicleData, chargeData, tripData, maintenanceData, aiData] = await Promise.all([
        firebaseService.getVehicles(),
        firebaseService.getRecentChargeLogs(20),
        firebaseService.getRecentTripLogs(20),
        firebaseService.getMaintenanceTasks(),
        firebaseService.getAiInsights()
      ]);

      setMaintenanceTasks(maintenanceData);

      // Generate audit logs from real data
      const logs: AuditLog[] = [];

      // Vehicle status logs
      vehicleData.forEach(vehicle => {
        if (vehicle.stateOfHealth < 80) {
          logs.push({
            id: `vehicle-soh-${vehicle.vehicleId}`,
            action: 'HEALTH_WARNING',
            user: vehicle.vinfastModelName || vehicle.vehicleName,
            target: `Vehicle ${vehicle.vehicleId}`,
            description: `SoH pin xuống ${vehicle.stateOfHealth.toFixed(1)}%`,
            timestamp: new Date().toISOString(),
            status: 'warning',
            ip: 'BMS System',
            userAgent: 'Battery Monitor'
          });
        }

        if (vehicle.currentBattery < 20) {
          logs.push({
            id: `vehicle-battery-${vehicle.vehicleId}`,
            action: 'LOW_BATTERY',
            user: vehicle.vinfastModelName || vehicle.vehicleName,
            target: `Vehicle ${vehicle.vehicleId}`,
            description: `Pin yếu còn ${vehicle.currentBattery}%`,
            timestamp: new Date().toISOString(),
            status: 'error',
            ip: 'BMS System',
            userAgent: 'Battery Monitor'
          });
        }
      });

      // Charge logs
      chargeData.slice(0, 10).forEach(charge => {
        logs.push({
          id: `charge-${charge.chargeId}`,
          action: 'CHARGE_SESSION',
          user: `Vehicle ${charge.vehicleId}`,
          target: `Charger ${charge.chargerType || 'Unknown'}`,
          description: `Sạc từ ${charge.startBatteryPercent}% đến ${charge.endBatteryPercent}%`,
          timestamp: charge.startAt.toDate().toISOString(),
          status: 'success',
          ip: 'Charging Station',
          userAgent: 'Charge Controller'
        });
      });

      // Trip logs
      tripData.slice(0, 10).forEach(trip => {
        logs.push({
          id: `trip-${trip.tripId}`,
          action: 'TRIP_COMPLETED',
          user: `Vehicle ${trip.vehicleId}`,
          target: `Trip ${trip.distance}km`,
          description: `Chuyến đi ${trip.distance}km, tiêu thụ ${((trip.startBatteryPercent - trip.endBatteryPercent) / trip.distance * 100).toFixed(1)}%/100km`,
          timestamp: trip.startAt.toDate().toISOString(),
          status: 'success',
          ip: 'Vehicle Telemetry',
          userAgent: 'Trip Logger'
        });
      });

      // Maintenance tasks
      maintenanceTasks.filter(task => task.status === 'overdue').forEach(task => {
        logs.push({
          id: `maintenance-${task.taskId}`,
          action: 'MAINTENANCE_OVERDUE',
          user: `Vehicle ${task.vehicleId}`,
          target: task.taskType,
          description: `Bảo dưỡng trễ: ${task.description}`,
          timestamp: task.dueDate?.toDate().toISOString() || new Date().toISOString(),
          status: 'error',
          ip: 'Maintenance System',
          userAgent: 'Maintenance Scheduler'
        });
      });

      // AI insights
      aiData.filter(insight => insight.hasTrained && insight.healthStatus === 'poor').forEach(insight => {
        logs.push({
          id: `ai-stale-${insight.vehicleId}`,
          action: 'AI_INSIGHT_STALE',
          user: `Vehicle ${insight.vehicleId}`,
          target: 'AI Model',
          description: `AI insight cần cập nhật, confidence: ${insight.confidence.toFixed(1)}%`,
          timestamp: insight.updatedAt || new Date().toISOString(),
          status: 'warning',
          ip: 'AI Service',
          userAgent: 'AI Training Engine'
        });
      });

      // Sort logs by timestamp (most recent first)
      logs.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
      setAuditLogs(logs);
    } catch (error) {
      console.error('Error loading audit data:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredLogs = auditLogs.filter(log =>
    log.action.toLowerCase().includes(searchTerm.toLowerCase()) ||
    log.user.toLowerCase().includes(searchTerm.toLowerCase()) ||
    log.description.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'success':
        return <Badge className="bg-green-100 text-green-800 hover:bg-green-200">Thành công</Badge>;
      case 'warning':
        return <Badge className="bg-yellow-100 text-yellow-800 hover:bg-yellow-200">Cảnh báo</Badge>;
      case 'error':
        return <Badge className="bg-red-100 text-red-800 hover:bg-red-200">Lỗi</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  const getActionIcon = (action: string) => {
    switch (action) {
      case 'HEALTH_WARNING':
      case 'LOW_BATTERY':
        return <Battery className="w-4 h-4 text-orange-600" />;
      case 'CHARGE_SESSION':
        return <Zap className="w-4 h-4 text-blue-600" />;
      case 'TRIP_COMPLETED':
        return <Car className="w-4 h-4 text-green-600" />;
      case 'MAINTENANCE_OVERDUE':
        return <AlertTriangle className="w-4 h-4 text-red-600" />;
      case 'AI_INSIGHT_STALE':
        return <Activity className="w-4 h-4 text-purple-600" />;
      default:
        return <Shield className="w-4 h-4 text-gray-600" />;
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('vi-VN', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const getStats = () => {
    const total = auditLogs.length;
    const success = auditLogs.filter(log => log.status === 'success').length;
    const warnings = auditLogs.filter(log => log.status === 'warning').length;
    const errors = auditLogs.filter(log => log.status === 'error').length;

    return { total, success, warnings, errors };
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Đang tải dữ liệu kiểm toán...</p>
        </div>
      </div>
    );
  }

  const stats = getStats();

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">Hệ thống kiểm toán</h1>
          <p className="text-muted-foreground mt-1">Theo dõi và ghi lại tất cả hoạt động hệ thống</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2">
            <Download className="w-4 h-4" />
            Xuất báo cáo
          </Button>
          <Button className="gap-2" onClick={loadAuditData}>
            <Shield className="w-4 h-4" />
            Làm mới
          </Button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-blue-100 rounded-lg">
                <Activity className="w-6 h-6 text-blue-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{stats.total}</p>
                <p className="text-sm text-muted-foreground">Tổng sự kiện</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-green-100 rounded-lg">
                <CheckCircle className="w-6 h-6 text-green-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{stats.success}</p>
                <p className="text-sm text-muted-foreground">Thành công</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-yellow-100 rounded-lg">
                <AlertTriangle className="w-6 h-6 text-yellow-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{stats.warnings}</p>
                <p className="text-sm text-muted-foreground">Cảnh báo</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-red-100 rounded-lg">
                <XCircle className="w-6 h-6 text-red-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{stats.errors}</p>
                <p className="text-sm text-muted-foreground">Lỗi</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Audit Logs Table */}
      <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <Shield className="w-5 h-5 text-primary" />
              Nhật ký hoạt động
            </CardTitle>
            <div className="flex items-center gap-2">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder="Tìm kiếm hoạt động..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10 bg-surface-light/50 border-border/50 w-64"
                />
              </div>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="icon">
                    <Filter className="w-4 h-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="bg-surface border-border">
                  <DropdownMenuItem>Tất cả</DropdownMenuItem>
                  <DropdownMenuItem>Thành công</DropdownMenuItem>
                  <DropdownMenuItem>Cảnh báo</DropdownMenuItem>
                  <DropdownMenuItem>Lỗi</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border/50">
                  <th className="text-left p-4 font-medium text-muted-foreground">Thời gian</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Hành động</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Người dùng</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Mục tiêu</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Mô tả</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Trạng thái</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">IP</th>
                </tr>
              </thead>
              <tbody>
                {filteredLogs.map((log) => (
                  <tr key={log.id} className="border-b border-border/30 hover:bg-surface-light/30 transition-colors">
                    <td className="p-4 text-muted-foreground">
                      <div className="flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {formatDate(log.timestamp)}
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-2">
                        {getActionIcon(log.action)}
                        <span className="font-medium">{log.action.replace(/_/g, ' ')}</span>
                      </div>
                    </td>
                    <td className="p-4">
                      <div className="flex items-center gap-1">
                        <User className="w-3 h-3 text-muted-foreground" />
                        {log.user}
                      </div>
                    </td>
                    <td className="p-4 text-muted-foreground">{log.target}</td>
                    <td className="p-4 text-muted-foreground max-w-xs truncate" title={log.description}>
                      {log.description}
                    </td>
                    <td className="p-4">{getStatusBadge(log.status)}</td>
                    <td className="p-4 text-muted-foreground font-mono text-xs">{log.ip}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {filteredLogs.length === 0 && (
              <div className="text-center py-8">
                <Shield className="w-8 h-8 text-muted-foreground mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">Không tìm thấy hoạt động nào</p>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
