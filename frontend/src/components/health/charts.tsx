import { lazy, Suspense } from 'react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

import type {
  BarChartCardProps,
  LineChartCardProps,
  PieChartCardProps,
} from './chart-cards'

/**
 * 图表卡片门面：recharts 只在真正渲染图表时才按需加载（React.lazy），
 * 避免仅使用统计工具函数的页面被拖入整个图表库。
 * 各页面的调用方式保持不变（组件名与入参一致）。
 *
 * 统计工具函数与状态色板无关，单独放在 chart-utils 中，
 * 页面若只需要 useStats / StatsPeriodPicker 等，应直接 import 该模块。
 */

const LazyLineChartCard = lazy(() =>
  import('./chart-cards').then((m) => ({ default: m.LineChartCard })),
)
const LazyBarChartCard = lazy(() =>
  import('./chart-cards').then((m) => ({ default: m.BarChartCard })),
)
const LazyPieChartCard = lazy(() =>
  import('./chart-cards').then((m) => ({ default: m.PieChartCard })),
)

/**
 * 图表加载占位：保持与真实图表卡片一致的外框（标题 + 固定高度内容区），
 * 加载完成后尺寸不跳变，不会出现空白闪烁。
 */
function ChartSkeleton({ title, height }: { title: string; height: number }) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="animate-pulse rounded-md bg-muted/40" style={{ height }} />
      </CardContent>
    </Card>
  )
}

/** 折线图卡片（recharts 按需加载） */
export function LineChartCard({ title, height = 240, ...rest }: LineChartCardProps) {
  return (
    <Suspense fallback={<ChartSkeleton title={title} height={height} />}>
      <LazyLineChartCard title={title} height={height} {...rest} />
    </Suspense>
  )
}

/** 柱状图卡片（recharts 按需加载） */
export function BarChartCard({ title, height = 240, ...rest }: BarChartCardProps) {
  return (
    <Suspense fallback={<ChartSkeleton title={title} height={height} />}>
      <LazyBarChartCard title={title} height={height} {...rest} />
    </Suspense>
  )
}

/** 饼图卡片（recharts 按需加载） */
export function PieChartCard({ title, height = 240, ...rest }: PieChartCardProps) {
  return (
    <Suspense fallback={<ChartSkeleton title={title} height={height} />}>
      <LazyPieChartCard title={title} height={height} {...rest} />
    </Suspense>
  )
}
