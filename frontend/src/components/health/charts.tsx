import { useEffect, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { api } from '@/lib/api'

type Series = { key: string; name: string; color?: string }

export function useStats<T>(path: string, days = 30) {
  const [data, setData] = useState<T | null>(null)
  useEffect(() => {
    api
      .stats<T>(path, days)
      .then(setData)
      .catch(() => setData(null))
  }, [path, days])
  return data
}

export function LineChartCard({
  title,
  data,
  xKey,
  series,
  height = 240,
}: {
  title: string
  data: Record<string, unknown>[]
  xKey: string
  series: Series[]
  height?: number
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <LineChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -16 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey={xKey} tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            {series.map((s) => (
              <Line
                key={s.key}
                type="monotone"
                dataKey={s.key}
                name={s.name}
                stroke={s.color ?? '#4f46e5'}
                strokeWidth={2}
                dot={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}

export function BarChartCard({
  title,
  data,
  xKey,
  series,
  height = 240,
}: {
  title: string
  data: Record<string, unknown>[]
  xKey: string
  series: Series[]
  height?: number
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <BarChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -16 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey={xKey} tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            {series.map((s) => (
              <Bar key={s.key} dataKey={s.key} name={s.name} fill={s.color ?? '#4f46e5'} radius={[4, 4, 0, 0]} />
            ))}
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
