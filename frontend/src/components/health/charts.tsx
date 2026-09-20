import { useEffect, useState, type CSSProperties } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
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
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'

type Series = { key: string; name: string; color?: string }

/** 统计天数：数字表示近 N 天，'all' 表示全部历史 */
export type StatsDays = number | 'all'

const STORAGE_KEY = 'lifeos_stats_days'

/** Recharts Tooltip 深色适配：内联样式优先于 CSS，故在此用主题变量（真 DOM 节点可解析 var）。
    深色下若沿用默认白底+继承浅色文字，会导致"浅字白底"同色不可见。 */
const TOOLTIP_STYLE: CSSProperties = {
  backgroundColor: 'var(--popover)',
  border: '1px solid var(--border)',
  borderRadius: '0.5rem',
  color: 'var(--popover-foreground)',
  fontSize: '12px',
  boxShadow: '0 4px 14px rgba(0,0,0,0.18)',
}

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

/**
 * 拉取统计数据。默认每 30 秒 + 窗口聚焦 + 数据变更时自动刷新（无感实时）；
 * intervalMs 传 0 则关闭定时轮询，仅保留聚焦与变更刷新。
 */
export function useStats<T>(
  path: string,
  days: StatsDays = 30,
  refresh?: number,
  intervalMs = 30_000,
) {
  const realtimeTick = useRealtime(intervalMs)
  const [data, setData] = useState<T | null>(null)
  useEffect(() => {
    api
      .stats<T>(path, days)
      .then(setData)
      .catch(() => setData(null))
  }, [path, days, refresh, realtimeTick])
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
            <Tooltip contentStyle={TOOLTIP_STYLE} />
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
            <Tooltip contentStyle={TOOLTIP_STYLE} />
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

/** 默认饼图配色：一组对深色友好的鲜艳色 */
const DEFAULT_PIE_COLORS = [
  '#6366f1',
  '#16a34a',
  '#f59e0b',
  '#dc2626',
  '#06b6d4',
  '#8b5cf6',
  '#ec4899',
  '#84cc16',
  '#f97316',
  '#14b8a6',
]

const DEFAULT_PIE_OUTER_RADIUS = '80%'
const DEFAULT_PIE_INNER_RADIUS = '55%'

/**
 * 饼图卡片：展示分类占比。自带深色 tooltip（复用 TOOLTIP_STYLE），
 * 扇区使用透明描边避免深色下出现黑色边框，支持悬停扇区外扩高亮与中心汇总文案。
 *
 * @param title     卡片标题
 * @param data      构成饼图的数组，每项包含 nameKey 与 dataKey 两个字段
 * @param dataKey   数值字段名（扇区大小依据）
 * @param nameKey   标签字段名
 * @param labels    可选：按 nameKey 值覆盖图例/悬浮文案
 * @param height    图表高度，默认 240
 * @param colors    可选：扇区颜色数组，缺省用一组深色友好色
 * @param onClick   可选：点击扇区回调用 payload（对应该项数据）
 * @param centerValue  可选：饼图中心显示总量文案
 * @param centerLabel  可选：饼图中心总量说明文案
 * @returns 渲染完成的饼图卡片 JSX（空数据时显示占位）
 */
export function PieChartCard({
  title,
  data,
  dataKey,
  nameKey,
  labels,
  height = 240,
  colors = DEFAULT_PIE_COLORS,
  onClick,
  centerValue,
  centerLabel,
}: {
  title: string
  data: Record<string, unknown>[]
  dataKey: string
  nameKey: string
  labels?: Record<string, string>
  height?: number
  colors?: string[]
  onClick?: (payload: Record<string, unknown>) => void
  centerValue?: string
  centerLabel?: string
}) {
  const [activeIndex, setActiveIndex] = useState<number | null>(null)

  // 当前数据解析后的名称（支持 labels 覆盖，用于图例与悬浮）
  const displayName = (raw: unknown) => {
    const s = String(raw)
    return labels?.[s] ?? s
  }

  // 总量用于计算占比
  const total = data.reduce((sum, d) => sum + (Number(d[dataKey] ?? 0) || 0), 0)

  // Tooltip formatter：显示原始数值 + 该分类占总量的百分比
  const tooltipFormatter = (value: unknown, name: unknown) => {
    const num = Number(value ?? 0)
    const pct = total > 0 ? (num / total) * 100 : 0
    return [
      `${Number.isInteger(num) ? num : num.toFixed(2)}（${pct.toFixed(1)}%）`,
      displayName(name),
    ]
  }

  if (data.length === 0) {
    return (
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">{title}</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center text-sm text-muted-foreground" style={{ height }}>
            暂无数据
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <PieChart>
            <Pie
              data={data}
              dataKey={dataKey}
              nameKey={nameKey}
              innerRadius={DEFAULT_PIE_INNER_RADIUS}
              outerRadius={DEFAULT_PIE_OUTER_RADIUS}
              paddingAngle={2}
              stroke="transparent"
              onMouseEnter={(_, idx) => setActiveIndex(idx)}
              onMouseLeave={() => setActiveIndex(null)}
              onClick={
                onClick
                  ? (entry) => {
                      onClick(entry?.payload ?? {})
                    }
                  : undefined
              }
            >
              {data.map((d, i) => {
                const active = activeIndex != null && activeIndex === i
                return (
                  <Cell
                    key={i}
                    fill={colors[i % colors.length]}
                    stroke="transparent"
                    style={onClick ? { cursor: 'pointer' } : undefined}
                    outerRadius={
                      active ? '78%' : DEFAULT_PIE_OUTER_RADIUS
                    }
                    innerRadius={
                      active ? '52%' : DEFAULT_PIE_INNER_RADIUS
                    }
                  />
                )
              })}
            </Pie>
            <Tooltip contentStyle={TOOLTIP_STYLE} formatter={tooltipFormatter} />
            {data.length > 0 && (
              <Legend
                wrapperStyle={{ fontSize: 12 }}
                formatter={(value) => displayName(value)}
              />
            )}
            {centerValue != null && (
              <text
                x="50%"
                y="46%"
                textAnchor="middle"
                dominantBaseline="middle"
                fill="var(--popover-foreground)"
                fontSize="20"
                fontWeight="600"
              >
                {centerValue}
              </text>
            )}
            {centerLabel != null && (
              <text
                x="50%"
                y="56%"
                textAnchor="middle"
                dominantBaseline="middle"
                fill="var(--muted-foreground)"
                fontSize="12"
              >
                {centerLabel}
              </text>
            )}
          </PieChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
