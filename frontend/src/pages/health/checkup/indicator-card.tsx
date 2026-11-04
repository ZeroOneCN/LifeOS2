import type { ReactNode } from 'react'
import { ArrowDownRight, ArrowUpRight, Minus } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Tip } from '@/components/ui/tip'

import { STAT_TONE, deltaOf, fmtRange, resultMeta, type CheckupStats } from './shared'

/** 顶部概览统计卡：点击可按该状态筛选下方指标概览。 */
export function StatCard({
  label,
  value,
  tone = 'neutral',
  icon,
  active,
  onClick,
}: {
  label: string
  value: number
  tone?: 'danger' | 'success' | 'warn' | 'neutral'
  icon: ReactNode
  active?: boolean
  onClick?: () => void
}) {
  return (
    <Card
      onClick={onClick}
      className={`transition-colors ${onClick ? 'cursor-pointer hover:border-foreground/25' : ''} ${
        active ? 'border-primary/60 ring-1 ring-primary/30' : ''
      }`}
    >
      <CardContent className="flex items-center justify-between py-4">
        <div>
          <div className="text-sm text-muted-foreground">{label}</div>
          <div className={`mt-1 text-2xl font-semibold tabular-nums ${STAT_TONE[tone]}`}>
            {value}
            <span className="ml-1 text-sm font-normal text-muted-foreground">项</span>
          </div>
        </div>
        <span className={`${STAT_TONE[tone]} opacity-70`}>{icon}</span>
      </CardContent>
    </Card>
  )
}

/** 趋势提示：展示最新值相较上一次的变化方向与幅度。 */
export function TrendHint({ delta }: { delta: number | null }) {
  if (delta == null) {
    return <div className="mt-0.5 text-xs text-muted-foreground">首次记录</div>
  }
  if (delta === 0) {
    return (
      <div className="mt-0.5 flex items-center justify-end gap-0.5 text-xs text-muted-foreground">
        <Minus className="size-3" /> 持平
      </div>
    )
  }
  const up = delta > 0
  return (
    <div className="mt-0.5 flex items-center justify-end gap-0.5 text-xs text-muted-foreground">
      {up ? <ArrowUpRight className="size-3" /> : <ArrowDownRight className="size-3" />}
      {up ? '+' : ''}
      {delta}
    </div>
  )
}

/** 指标概览卡：展示单个指标的最新值、参考范围、判定结果与较上次变化。 */
export function IndicatorCard({ item }: { item: CheckupStats['items'][number] }) {
  const meta = item.latest?.result ? resultMeta[item.latest.result] : undefined
  const delta = deltaOf(item.trend)
  const range = item.reference_range || fmtRange(item.ref_low, item.ref_high) || '—'
  return (
    <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <Tip label={item.item_name}>
            <span className="truncate text-sm font-medium">
              {item.item_name}
            </span>
          </Tip>
          {meta && <Badge className={meta.className}>{meta.label}</Badge>}
        </div>
        <Tip label={`参考 ${range} · 共 ${item.count} 次`}>
          <div className="mt-1 truncate text-xs text-muted-foreground">
            参考 {range} · {item.count} 次
          </div>
        </Tip>
      </div>
      <div className="shrink-0 text-right">
        <div className="text-lg font-semibold tabular-nums">
          {item.latest?.value != null ? item.latest.value : '—'}
          <span className="ml-1 text-xs font-normal text-muted-foreground">{item.unit ?? ''}</span>
        </div>
        <TrendHint delta={delta} />
      </div>
    </div>
  )
}
