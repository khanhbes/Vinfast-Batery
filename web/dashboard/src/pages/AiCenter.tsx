import { useState, useEffect } from 'react';
import { BrainCircuit, Zap, TrendingUp, Settings, Play, RotateCcw } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Progress } from '@/components/ui/progress';
import {
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart
} from 'recharts';
import { motion } from 'motion/react';
import { cn } from '@/lib/utils';
import { firebaseService, AiVehicleInsight, SOCPredictionResult, SOCPredictionInput } from '@/services/firebaseService';
import SOCChart from '@/components/SOCChart';

export default function AiCenter() {
  const [aiInsights, setAiInsights] = useState<AiVehicleInsight[]>([]);
  const [performanceData, setPerformanceData] = useState<any[]>([]);
  const [selectedInsight, setSelectedInsight] = useState<AiVehicleInsight | null>(null);
  const [loading, setLoading] = useState(true);
  
  // SOC Prediction states
  const [socPredictions, setSocPredictions] = useState<SOCPredictionResult[]>([]);
  const [socModelStatus, setSocModelStatus] = useState<any>(null);
  const [selectedVehicle, setSelectedVehicle] = useState<string>('');

  useEffect(() => {
    loadAiData();
  }, []);

  const loadAiData = async () => {
    try {
      setLoading(true);
      const insights = await firebaseService.getAiInsights();
      
      // Generate performance data from insights
      const newPerformanceData = insights.slice(0, 7).reverse().map((insight) => ({
        time: new Date(insight.updatedAt || '').toLocaleTimeString('vi-VN', { 
          hour: '2-digit', 
          minute: '2-digit' 
        }),
        accuracy: insight.confidence,
        predictions: insight.dataPoints,
      }));

      setAiInsights(insights);
      setPerformanceData(newPerformanceData);
      if (insights.length > 0) {
        setSelectedInsight(insights[0]);
      }

      // Load SOC model status
      try {
        const status = await firebaseService.getSOCModelStatus();
        setSocModelStatus(status);
      } catch (error) {
        console.error('Error loading SOC model status:', error);
      }

      // Load SOC predictions
      try {
        const predictions = await firebaseService.getSOCPredictions();
        setSocPredictions(predictions.slice(0, 10));
      } catch (error) {
        console.error('Error loading SOC predictions:', error);
      }
    } catch (error) {
      console.error('Error loading AI data:', error);
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (insight: AiVehicleInsight) => {
    if (!insight.hasTrained) {
      return <Badge className="bg-gray-100 text-gray-800 hover:bg-gray-200">Chưa huấn luyện</Badge>;
    }
    if (insight.displayStatus === 'stale') {
      return <Badge className="bg-yellow-100 text-yellow-800 hover:bg-yellow-200">Cần cập nhật</Badge>;
    }
    return <Badge className="bg-green-100 text-green-800 hover:bg-green-200">Đang hoạt động</Badge>;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Đang tải dữ liệu AI...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">AI Center</h1>
          <p className="text-muted-foreground mt-1">Quản lý và giám sát các mô hình AI dự đoán pin</p>
        </div>
        <div className="flex gap-3">
          <Button variant="outline" className="gap-2">
            <Settings className="w-4 h-4" />
            Cài đặt
          </Button>
          <Button className="gap-2" onClick={loadAiData}>
            <Play className="w-4 h-4" />
            Làm mới dữ liệu
          </Button>
        </div>
      </div>

      {/* AI Insights Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {aiInsights.map((insight) => (
          <motion.div
            key={insight.vehicleId}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            whileHover={{ scale: 1.02 }}
            className={`cursor-pointer ${selectedInsight?.vehicleId === insight.vehicleId ? 'ring-2 ring-primary' : ''}`}
            onClick={() => setSelectedInsight(insight)}
          >
            <Card className="border-border/50 bg-surface/50 backdrop-blur-sm hover:shadow-lg transition-all duration-300">
              <CardHeader>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="p-2 bg-primary/10 rounded-lg">
                      <BrainCircuit className="w-6 h-6 text-primary" />
                    </div>
                    <div>
                      <CardTitle className="text-lg">Xe {insight.vehicleId}</CardTitle>
                      <CardDescription className="text-sm">
                        Health Score: {insight.healthScore.toFixed(1)}%
                      </CardDescription>
                    </div>
                  </div>
                  {getStatusBadge(insight)}
                </div>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-muted-foreground">Độ tin cậy</span>
                    <span className="text-sm font-medium">{insight.confidence.toFixed(1)}%</span>
                  </div>
                  <Progress value={insight.confidence} className="h-2" />
                  <div className="flex items-center justify-between text-xs text-muted-foreground">
                    <span>Data Points:</span>
                    <span>{insight.dataPoints}</span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-muted-foreground">
                    <span>Trạng thái:</span>
                    <span>{insight.healthStatus}</span>
                  </div>
                  {insight.estimatedLifeMonths && (
                    <div className="flex items-center justify-between text-xs text-muted-foreground">
                      <span>Tuổi thọ dự kiến:</span>
                      <span>{insight.estimatedLifeMonths.toFixed(0)} tháng</span>
                    </div>
                  )}
                  <div className="flex gap-2 pt-2">
                    <Button size="sm" variant="outline" className="flex-1">
                      <Play className="w-3 h-3 mr-1" />
                      Huấn luyện
                    </Button>
                    <Button size="sm" variant="outline" className="flex-1">
                      <RotateCcw className="w-3 h-3 mr-1" />
                      Đặt lại
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          </motion.div>
        ))}
        {aiInsights.length === 0 && (
          <div className="col-span-3 text-center py-12">
            <BrainCircuit className="w-16 h-16 text-muted-foreground mx-auto mb-4" />
            <h3 className="text-lg font-medium text-foreground mb-2">Chưa có dữ liệu AI</h3>
            <p className="text-muted-foreground">Chưa có mô hình AI nào được huấn luyện</p>
          </div>
        )}
      </div>

      {/* Performance Chart and Selected Insight Details */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Performance Chart */}
        <Card className="lg:col-span-2 border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-primary" />
              Hiệu suất mô hình
            </CardTitle>
            <CardDescription>
              Độ tin cậy và số lượng dữ liệu theo thời gian
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="h-[300px]">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={performanceData}>
                  <defs>
                    <linearGradient id="colorAccuracy" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.8}/>
                      <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0.1}/>
                    </linearGradient>
                    <linearGradient id="colorPredictions" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="hsl(var(--chart-2))" stopOpacity={0.8}/>
                      <stop offset="95%" stopColor="hsl(var(--chart-2))" stopOpacity={0.1}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-border/30" />
                  <XAxis 
                    dataKey="time" 
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
                    dataKey="accuracy" 
                    stroke="hsl(var(--primary))" 
                    fillOpacity={1} 
                    fill="url(#colorAccuracy)"
                    strokeWidth={2}
                    name="Độ tin cậy (%)"
                  />
                  <Area 
                    type="monotone" 
                    dataKey="predictions" 
                    stroke="hsl(var(--chart-2))" 
                    fillOpacity={1} 
                    fill="url(#colorPredictions)"
                    strokeWidth={2}
                    name="Data Points"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        {/* Selected Insight Details */}
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Zap className="w-5 h-5 text-primary" />
              Chi tiết AI Insight
            </CardTitle>
            <CardDescription>
              Thông tin chi tiết về insight được chọn
            </CardDescription>
          </CardHeader>
          <CardContent>
            {selectedInsight ? (
              <div className="space-y-4">
                <div className="p-3 rounded-lg bg-surface-light/50">
                  <h4 className="text-sm font-medium text-foreground mb-2">Xe {selectedInsight.vehicleId}</h4>
                  <div className="space-y-2">
                    <div className="flex justify-between text-xs">
                      <span className="text-muted-foreground">Health Score:</span>
                      <span className="font-medium">{selectedInsight.healthScore.toFixed(1)}%</span>
                    </div>
                    <div className="flex justify-between text-xs">
                      <span className="text-muted-foreground">Health Status:</span>
                      <span className="font-medium">{selectedInsight.healthStatus}</span>
                    </div>
                    <div className="flex justify-between text-xs">
                      <span className="text-muted-foreground">Confidence:</span>
                      <span className="font-medium">{selectedInsight.confidence.toFixed(1)}%</span>
                    </div>
                    {selectedInsight.estimatedLifeMonths && (
                      <div className="flex justify-between text-xs">
                        <span className="text-muted-foreground">RUL:</span>
                        <span className="font-medium">{selectedInsight.estimatedLifeMonths.toFixed(0)} tháng</span>
                      </div>
                    )}
                    {selectedInsight.chargeFrequencyPerWeek && (
                      <div className="flex justify-between text-xs">
                        <span className="text-muted-foreground">Tần suất sạc:</span>
                        <span className="font-medium">{selectedInsight.chargeFrequencyPerWeek.toFixed(1)}/tuần</span>
                      </div>
                    )}
                  </div>
                </div>
                
                {selectedInsight.recommendations.length > 0 && (
                  <div className="p-3 rounded-lg bg-surface-light/50">
                    <h4 className="text-sm font-medium text-foreground mb-2">Khuyến nghị</h4>
                    <ul className="space-y-1">
                      {selectedInsight.recommendations.slice(0, 3).map((rec, index) => (
                        <li key={index} className="text-xs text-muted-foreground">• {rec}</li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="flex items-center gap-1 text-xs text-muted-foreground">
                  <Clock className="w-3 h-3" />
                  <span>
                    Cập nhật: {selectedInsight.updatedAt 
                      ? new Date(selectedInsight.updatedAt).toLocaleString('vi-VN')
                      : 'Chưa có'
                    }
                  </span>
                </div>
              </div>
            ) : (
              <div className="text-center py-8">
                <BrainCircuit className="w-8 h-8 text-muted-foreground mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">Chọn một insight để xem chi tiết</p>
              </div>
            )}
          </CardContent>
        </Card>

      {/* SOC Prediction Section */}
      <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <BrainCircuit className="w-5 h-5 text-primary" />
            Mô hình dự đoán SOC (State of Charge)
          </CardTitle>
          <CardDescription>
            Mô hình AI ev_soc_pipeline.pkl dự đoán mức sạc pin dựa trên dữ liệu vận hành
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Model Status */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-foreground">Trạng thái mô hình</h3>
              {socModelStatus ? (
                <div className="space-y-3">
                  <div className="flex items-center justify-between p-3 rounded-lg bg-surface-light/50">
                    <span className="text-sm text-muted-foreground">Trạng thái:</span>
                    <Badge className={socModelStatus.isLoaded ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"}>
                      {socModelStatus.isLoaded ? "Đã tải" : "Chưa tải"}
                    </Badge>
                  </div>
                  <div className="flex items-center justify-between p-3 rounded-lg bg-surface-light/50">
                    <span className="text-sm text-muted-foreground">Phiên bản:</span>
                    <span className="text-sm font-medium">{socModelStatus.modelVersion}</span>
                  </div>
                  <div className="flex items-center justify-between p-3 rounded-lg bg-surface-light/50">
                    <span className="text-sm text-muted-foreground">File model:</span>
                    <span className="text-xs font-mono text-muted-foreground">
                      {socModelStatus.modelPath?.split('/').pop()}
                    </span>
                  </div>
                </div>
              ) : (
                <div className="text-center py-4">
                  <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-2"></div>
                  <p className="text-sm text-muted-foreground">Đang tải trạng thái mô hình...</p>
                </div>
              )}
            </div>

            {/* Recent Predictions */}
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-foreground">Dự đoán gần đây</h3>
              {socPredictions.length > 0 ? (
                <div className="space-y-2 max-h-48 overflow-y-auto">
                  {socPredictions.slice(0, 5).map((prediction, index) => (
                    <div key={index} className="p-3 rounded-lg bg-surface-light/50">
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium">SOC dự đoán:</span>
                        <span className="text-sm font-bold text-primary">{prediction.predictedSOC.toFixed(1)}%</span>
                      </div>
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium">Độ tin cậy:</span>
                        <span className="text-sm font-medium">{prediction.confidence.toFixed(1)}%</span>
                      </div>
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium">Sức khỏe pin:</span>
                        <span className={`text-sm font-medium ${
                          prediction.batteryHealth >= 80 ? 'text-green-600' :
                          prediction.batteryHealth >= 60 ? 'text-yellow-600' : 'text-red-600'
                        }`}>
                          {prediction.batteryHealth.toFixed(1)}%
                        </span>
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {new Date(prediction.timestamp).toLocaleString('vi-VN')}
                      </div>
                      {prediction.recommendations.length > 0 && (
                        <div className="mt-2 pt-2 border-t border-border/50">
                          <p className="text-xs font-medium text-foreground mb-1">Khuyến nghị:</p>
                          <ul className="space-y-1">
                            {prediction.recommendations.slice(0, 2).map((rec, recIndex) => (
                              <li key={recIndex} className="text-xs text-muted-foreground">• {rec}</li>
                            ))}
                          </ul>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="text-center py-4">
                  <BrainCircuit className="w-8 h-8 text-muted-foreground mx-auto mb-2" />
                  <p className="text-sm text-muted-foreground">Chưa có dự đoán nào</p>
                </div>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* SOC Visualization */}
      {socPredictions.length > 0 && (
        <SOCChart 
          data={socPredictions[0].timeSeries}
          title="Dự đoán SOC trong 24 giờ tiếp theo"
          height={350}
        />
      )}
      </div>
    </div>
  );
}
