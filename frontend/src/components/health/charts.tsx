import { useEffect, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
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
  intTick = false,
}: {
  title: string
  data: Record<string, unknown>[]
  xKey: string
  series: Series[]
  height?: number
  /** Y 轴使用整数刻度（步数等离散较大数值时避免小数刻度） */
  intTick?: boolean
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <LineChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: 8 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey={xKey} tick={{ fontSize: 12 }} />
            <YAxis
              tick={{ fontSize: 12 }}
              allowDecimals={!intTick}
              tickFormatter={intTick ? (v: number) => (Number.isInteger(v) ? String(v) : '') : undefined}
            />
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
  intTick = false,
  onBarClick,
  selectedKey,
}: {
  title: string
  data: Record<string, unknown>[]
  xKey: string
  series: Series[]
  height?: number
  /** Y 轴使用整数刻度 */
  intTick?: boolean
  /** 点击柱状图触发（payload 为柱数据） */
  onBarClick?: (payload: Record<string, unknown>) => void
  /** 选中条目的 key 值（用于高亮该柱） */
  selectedKey?: string
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <BarChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: 8 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey={xKey} tick={{ fontSize: 12 }} />
            <YAxis
              tick={{ fontSize: 12 }}
              allowDecimals={!intTick}
              tickFormatter={intTick ? (v: number) => (Number.isInteger(v) ? String(v) : '') : undefined}
            />
            <Tooltip />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            {series.map((s) => (
              <Bar
                key={s.key}
                dataKey={s.key}
                name={s.name}
                fill={s.color ?? '#4f46e5'}
                radius={[4, 4, 0, 0]}
                style={onBarClick ? { cursor: 'pointer' } : undefined}
                onClick={
                  onBarClick
                    ? (payload) => {
                        onBarClick(payload?.payload ?? payload ?? {})
                      }
                    : undefined
                }
              >
                {selectedKey &&
                  data.map((d) => (
                    <Cell
                      key={`cell-${String(d[xKey])}`}
                      fill={String(d[xKey]) === String(selectedKey) ? '#f59e0b' : (s.color ?? '#4f46e5')}
                    />
                  ))}
              </Bar>
            ))}
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
