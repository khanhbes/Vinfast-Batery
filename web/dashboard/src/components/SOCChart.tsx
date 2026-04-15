import React from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface SOCChartProps {
  data: number[];
  title?: string;
  height?: number;
}

const SOCChart: React.FC<SOCChartProps> = ({ 
  data, 
  title = "Dự đoán SOC theo thời gian", 
  height = 300 
}) => {
  // Convert time series data to chart format
  const chartData = data.map((soc, index) => ({
    hour: `${index}:00`,
    soc: soc,
    hourNum: index
  }));

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-background border border-border rounded-lg p-3 shadow-lg">
          <p className="text-sm font-medium">{`Thời gian: ${label}`}</p>
          <p className="text-sm text-primary">{`SOC: ${payload[0].value.toFixed(1)}%`}</p>
        </div>
      );
    }
    return null;
  };

  return (
    <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
      <CardHeader>
        <CardTitle className="text-lg">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <LineChart data={chartData} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" className="opacity-30" />
            <XAxis 
              dataKey="hour" 
              tick={{ fontSize: 12 }}
              stroke="hsl(var(--muted-foreground))"
            />
            <YAxis 
              domain={[0, 100]}
              tick={{ fontSize: 12 }}
              stroke="hsl(var(--muted-foreground))"
              label={{ value: 'SOC (%)', angle: -90, position: 'insideLeft' }}
            />
            <Tooltip content={<CustomTooltip />} />
            <Legend />
            <Line 
              type="monotone" 
              dataKey="soc" 
              stroke="hsl(var(--primary))"
              strokeWidth={2}
              dot={{ fill: 'hsl(var(--primary))', strokeWidth: 2, r: 4 }}
              activeDot={{ r: 6 }}
              name="SOC (%)"
            />
          </LineChart>
        </ResponsiveContainer>
        
        {/* Summary Statistics */}
        <div className="mt-4 grid grid-cols-3 gap-4">
          <div className="text-center">
            <p className="text-sm text-muted-foreground">SOC ban đầu</p>
            <p className="text-lg font-bold text-primary">{data[0]?.toFixed(1)}%</p>
          </div>
          <div className="text-center">
            <p className="text-sm text-muted-foreground">SOC cuối cùng</p>
            <p className="text-lg font-bold text-primary">{data[data.length - 1]?.toFixed(1)}%</p>
          </div>
          <div className="text-center">
            <p className="text-sm text-muted-foreground">Mức tiêu hao</p>
            <p className="text-lg font-bold text-orange-600">
              {data[0] && data[data.length - 1] ? (data[0] - data[data.length - 1]).toFixed(1) : '0'}%
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default SOCChart;
