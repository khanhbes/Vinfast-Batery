import { useMemo } from 'react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  Cell,
} from 'recharts';
import { ChartData } from './types';

interface PredictionResultChartProps {
  chartData: ChartData;
  height?: number;
  accent?: 'emerald' | 'blue' | 'violet' | 'amber' | 'rose' | 'slate';
}

const ACCENT_COLORS: Record<string, { fill: string; stroke: string }> = {
  emerald: { fill: '#10b981', stroke: '#059669' },
  blue: { fill: '#3b82f6', stroke: '#2563eb' },
  violet: { fill: '#8b5cf6', stroke: '#7c3aed' },
  amber: { fill: '#f59e0b', stroke: '#d97706' },
  rose: { fill: '#f43f5e', stroke: '#e11d48' },
  slate: { fill: '#64748b', stroke: '#475569' },
};

export default function PredictionResultChart({
  chartData,
  height = 200,
  accent = 'blue',
}: PredictionResultChartProps) {
  const colors = ACCENT_COLORS[accent] || ACCENT_COLORS.blue;

  // Format numbers for display
  const formatValue = (value: number | undefined): string => {
    if (value === undefined || value === null) return '-';
    if (Math.abs(value) >= 1000) {
      return value.toLocaleString('vi-VN', { maximumFractionDigits: 0 });
    }
    if (Math.abs(value) < 0.01 && value !== 0) {
      return value.toExponential(2);
    }
    return value.toLocaleString('vi-VN', { maximumFractionDigits: 2 });
  };

  // Build appropriate chart based on type
  const chart = useMemo(() => {
    const data = chartData.data || [];

    if (chartData.type === 'scalar' || chartData.type === 'class') {
      // Bar chart for scalar values
      return (
        <ResponsiveContainer width="100%" height={height}>
          <BarChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis
              dataKey="name"
              tick={{ fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: '#d1d5db' }}
            />
            <YAxis
              tick={{ fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: '#d1d5db' }}
              tickFormatter={formatValue}
            />
            <Tooltip
              formatter={(value) => [formatValue(value as number), chartData.unit || 'Giá trị']}
              labelStyle={{ fontSize: 12 }}
              contentStyle={{ fontSize: 12, borderRadius: 6 }}
            />
            <Bar dataKey="value" radius={[4, 4, 0, 0]}>
              {data.map((_, index) => (
                <Cell key={`cell-${index}`} fill={colors.fill} stroke={colors.stroke} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      );
    }

    if (chartData.type === 'vector') {
      // Line chart for vector/time series values
      return (
        <ResponsiveContainer width="100%" height={height}>
          <LineChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
            <XAxis
              dataKey="name"
              tick={{ fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: '#d1d5db' }}
            />
            <YAxis
              tick={{ fontSize: 11 }}
              tickLine={false}
              axisLine={{ stroke: '#d1d5db' }}
              tickFormatter={formatValue}
            />
            <Tooltip
              formatter={(value) => [formatValue(value as number), chartData.unit || 'Giá trị']}
              labelStyle={{ fontSize: 12 }}
              contentStyle={{ fontSize: 12, borderRadius: 6 }}
            />
            <Line
              type="monotone"
              dataKey="value"
              stroke={colors.stroke}
              strokeWidth={2}
              dot={{ fill: colors.fill, stroke: colors.stroke, strokeWidth: 2, r: 3 }}
              activeDot={{ r: 5, fill: colors.fill }}
            />
          </LineChart>
        </ResponsiveContainer>
      );
    }

    // Fallback: show as simple value
    if (data.length === 1) {
      return (
        <div className="flex items-center justify-center h-full">
          <div className="text-center">
            <div className="text-3xl font-bold" style={{ color: colors.stroke }}>
              {formatValue(data[0].value)}
            </div>
            <div className="text-sm text-muted-foreground">{data[0].name}</div>
          </div>
        </div>
      );
    }

    return (
      <div className="flex items-center justify-center h-full text-muted-foreground text-sm">
        Không có dữ liệu biểu đồ
      </div>
    );
  }, [chartData, height, colors]);

  // Calculate summary statistics
  const stats = useMemo(() => {
    const values = chartData.data.map((d) => d.value);
    if (values.length === 0) return null;

    const max = Math.max(...values);
    const min = Math.min(...values);
    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const sum = values.reduce((a, b) => a + b, 0);

    return { max, min, avg, sum, count: values.length };
  }, [chartData.data]);

  return (
    <div className="space-y-3">
      <div className="text-sm font-medium text-muted-foreground">Kết quả dự đoán</div>
      <div className="rounded-md border bg-card p-3">
        {chart}
      </div>

      {/* Statistics summary */}
      {stats && stats.count > 1 && (
        <div className="grid grid-cols-4 gap-2 text-xs">
          <div className="rounded-md bg-muted/50 p-2 text-center">
            <div className="text-muted-foreground">Max</div>
            <div className="font-medium">{formatValue(stats.max)}</div>
          </div>
          <div className="rounded-md bg-muted/50 p-2 text-center">
            <div className="text-muted-foreground">Min</div>
            <div className="font-medium">{formatValue(stats.min)}</div>
          </div>
          <div className="rounded-md bg-muted/50 p-2 text-center">
            <div className="text-muted-foreground">Avg</div>
            <div className="font-medium">{formatValue(stats.avg)}</div>
          </div>
          <div className="rounded-md bg-muted/50 p-2 text-center">
            <div className="text-muted-foreground">Sum</div>
            <div className="font-medium">{formatValue(stats.sum)}</div>
          </div>
        </div>
      )}

      {/* Single value display with unit */}
      {stats && stats.count === 1 && chartData.unit && (
        <div className="text-center">
          <span className="text-sm text-muted-foreground">{chartData.unit}</span>
        </div>
      )}
    </div>
  );
}
