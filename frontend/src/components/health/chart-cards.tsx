import { type CSSProperties, type ReactNode } from 'react'
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
  Sector,
  Tooltip,
  XAxis,
  YAxis,
  type PieSectorShapeProps,
} from 'recharts'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { resolveChartColor, useChartColors, type ChartColorToken } from '@/lib/chart-theme'
import { formatDecimal, formatInt, formatPercent } from '@/lib/format'

import { ChartEmptyCard } from './chart-empty-card'

/** 坐标轴整数刻度：统一千分位，如 4,277 */
const intTickFormatter = (v: number) => (Number.isInteger(v) ? formatInt(v) : '')

/** Tooltip 数值：整数千分位，小数固定 2 位，与表格口径一致 */
const tooltipNumber = (v: unknown) => {
  const num = Number(v ?? 0)
  return Number.isInteger(num) ? formatInt(num) : formatDecimal(num, 2)
}

/** 图表系列配置；color 使用主题色板令牌，由图表组件按当前深浅色解析为具体颜色 */
export type Series = { key: string; name: string; color?: ChartColorToken }

/**
 * Recharts Tooltip 深色适配：内联样式优先于 CSS，故在此用主题变量（真 DOM 节点可解析 var）。
 * 深色下若沿用默认白底+继承浅色文字，会导致"浅字白底"同色不可见。
 */
const TOOLTIP_STYLE: CSSProperties = {
  backgroundColor: 'var(--popover)',
  border: '1px solid var(--border)',
  borderRadius: '0.5rem',
  color: 'var(--popover-foreground)',
  fontSize: '12px',
  boxShadow: '0 4px 14px rgba(0,0,0,0.18)',
}

/** 折线图卡片入参 */
export type LineChartCardProps = {
  title: string
  data: Record<string, unknown>[]
  xKey: string
  series: Series[]
  height?: number
  /** Y 轴使用整数刻度（步数等离散较大数值时避免小数刻度） */
  intTick?: boolean
  /** 非零基线有意义的折线（体重/BMI/体脂）传 auto，避免 0 起点把曲线压扁 */
  yDomain?: [number | 'auto', number | 'auto']
  /** 空数据时的说明文案 */
  emptyMessage?: string
  /** 空数据时的记录入口按钮 */
  emptyAction?: ReactNode
}

export function LineChartCard({
  title,
  data,
  xKey,
  series,
  height = 240,
  intTick = false,
  yDomain,
  emptyMessage,
  emptyAction,
}: LineChartCardProps) {
  const palette = useChartColors()
  if (data.length === 0) {
    return <ChartEmptyCard title={title} message={emptyMessage} action={emptyAction} />
  }
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <LineChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: 8 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette['chart-grid']} />
            <XAxis
              dataKey={xKey}
              minTickGap={24}
              stroke={palette['chart-axis']}
              tick={{ fontSize: 12, fill: palette['chart-axis'] }}
            />
            <YAxis
              domain={yDomain}
              allowDecimals={!intTick}
              stroke={palette['chart-axis']}
              tick={{ fontSize: 12, fill: palette['chart-axis'] }}
              tickFormatter={intTick ? intTickFormatter : undefined}
            />
            <Tooltip contentStyle={TOOLTIP_STYLE} formatter={tooltipNumber} />
            <Legend wrapperStyle={{ fontSize: 12, color: palette['chart-axis'] }} />
            {series.map((s) => (
              <Line
                key={s.key}
                type="monotone"
                dataKey={s.key}
                name={s.name}
                stroke={resolveChartColor(s.color, palette)}
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

/** 柱状图卡片入参 */
export type BarChartCardProps = {
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
  /** 空数据时的说明文案 */
  emptyMessage?: string
  /** 空数据时的记录入口按钮 */
  emptyAction?: ReactNode
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
  emptyMessage,
  emptyAction,
}: BarChartCardProps) {
  const palette = useChartColors()
  if (data.length === 0) {
    return <ChartEmptyCard title={title} message={emptyMessage} action={emptyAction} />
  }
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={height}>
          <BarChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: 8 }}>
            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette['chart-grid']} />
            <XAxis
              dataKey={xKey}
              stroke={palette['chart-axis']}
              tick={{ fontSize: 12, fill: palette['chart-axis'] }}
            />
            <YAxis
              allowDecimals={!intTick}
              stroke={palette['chart-axis']}
              tick={{ fontSize: 12, fill: palette['chart-axis'] }}
              tickFormatter={intTick ? intTickFormatter : undefined}
            />
            <Tooltip contentStyle={TOOLTIP_STYLE} formatter={tooltipNumber} />
            <Legend wrapperStyle={{ fontSize: 12, color: palette['chart-axis'] }} />
            {series.map((s) => (
              <Bar
                key={s.key}
                dataKey={s.key}
                name={s.name}
                fill={resolveChartColor(s.color, palette)}
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
                      fill={
                        String(d[xKey]) === String(selectedKey)
                          ? palette.warning
                          : resolveChartColor(s.color, palette)
                      }
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

const DEFAULT_PIE_OUTER_RADIUS = '80%'
const DEFAULT_PIE_INNER_RADIUS = '55%'
/** 悬停扇区相对基准半径的外扩像素值，用于形成放大反馈 */
const PIE_HOVER_OUTER_OFFSET = 6

/**
 * 饼图扇区渲染：悬停（active）时外扩半径形成放大反馈。
 * recharts 内部由 Tooltip 的悬停状态驱动 active 扇区并通过 isActive 传入，
 * 因此无需自行维护悬停索引；扇区颜色来自 <Cell> 的 fill。
 */
const renderPieSector = ({ isActive, ...sector }: PieSectorShapeProps) => (
  <Sector
    {...sector}
    outerRadius={
      isActive ? sector.outerRadius + PIE_HOVER_OUTER_OFFSET : sector.outerRadius
    }
  />
)

/** 饼图卡片入参 */
export type PieChartCardProps = {
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
}

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
 * @param colors    可选：扇区颜色数组，缺省用当前主题的 10 色顺序色板
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
  colors,
  onClick,
  centerValue,
  centerLabel,
}: PieChartCardProps) {
  const palette = useChartColors()
  // 未显式传入色板时，使用当前主题的顺序色板（深浅色由 CSS 变量决定）
  const pieColors = colors ?? palette.series

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
      `${tooltipNumber(num)}（${formatPercent(pct)}）`,
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
              shape={renderPieSector}
              onClick={
                onClick
                  ? (entry) => {
                      onClick(entry?.payload ?? {})
                    }
                  : undefined
              }
            >
              {data.map((_, i) => (
                <Cell
                  key={i}
                  fill={pieColors[i % pieColors.length]}
                  stroke="transparent"
                  style={onClick ? { cursor: 'pointer' } : undefined}
                />
              ))}
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
