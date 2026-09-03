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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { api } from '@/lib/api'

type Series = { key: string; name: string; color?: string }

/** 统计天数：数字表示近 N 天，'all' 表示全部历史 */
export type StatsDays = number | 'all'

const STORAGE_KEY = 'lifeos_stats_days'

function readDefaultStatsDays(): StatsDays {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw === 'all') return 'all'
    const n = Number(raw)
    if (Number.isInteger(n) && n >= 1) return n
  } catch {
    /* localStorage 不可用时回退默认 */
  }
  return 30
}

/** 读取全局默认统计天数（localStorage 持久化，各页初始一致） */
export function getDefaultStatsDays(): StatsDays {
  return readDefaultStatsDays()
}

/** 设置全局默认统计天数（localStorage 持久化） */
export function setGlobalStatsDays(d: StatsDays) {
  try {
    localStorage.setItem(STORAGE_KEY, String(d))
  } catch {
    /* ignore */
  }
}

/** 统计天数选择器：近 7/30/90 天 / 全部 */
export function StatsPeriodPicker({
  value,
  onChange,
}: {
  value: StatsDays
  onChange: (d: StatsDays) => void
}) {
  return (
    <Select
      value={value === 'all' ? 'all' : String(value)}
      onValueChange={(v) => onChange(v === 'all' ? 'all' : Number(v))}
    >
      <SelectTrigger className="w-36">
        <SelectValue placeholder="统计天数" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="7">近 7 天</SelectItem>
        <SelectItem value="30">近 30 天</SelectItem>
        <SelectItem value="90">近 90 天</SelectItem>
        <SelectItem value="all">全部</SelectItem>
      </SelectContent>
    </Select>
  )
}

export function useStats<T>(path: string, days: StatsDays = 30, refresh?: number) {
  const [data, setData] = useState<T | null>(null)
  useEffect(() => {
    api
      .stats<T>(path, days)
      .then(setData)
      .catch(() => setData(null))
  }, [path, days, refresh])
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
