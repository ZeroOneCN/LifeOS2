import { useEffect, useState } from 'react'
import { Plus } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, type StatsDays } from '@/components/health/chart-utils'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { DASH, formatDecimal, formatHealth1, formatInt, formatPercent } from '@/lib/format'

type DashboardData = {
  series: { record_date: string; intake: number; expenditure: number; balance: number }[]
  nutrition: { calories: number; protein: number; carbs: number; fat: number }
  intake_total: number
  expenditure_total: number
  expenditure_trend: { record_date: string; calories: number }[]
  step_total: number
  exercise_count: number
  body_trend: { record_date: string; weight_kg?: number; bmi?: number; body_fat_percent?: number; muscle_percent?: number }[]
  latest_body?: {
    record_date: string
    height_cm?: number
    weight_kg?: number
    bmi?: number
    body_fat_percent?: number
  } | null
}

export function FitnessDashboardPage({
  onGoTo,
}: {
  /** 进入对应记录 Tab，供空态图表的记录入口使用 */
  onGoTo?: (tab: 'diet' | 'exercise' | 'body') => void
} = {}) {
  const realtimeTick = useRealtime(30_000)
  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const [data, setData] = useState<DashboardData | null>(null)

  useEffect(() => {
    const n = days === 'all' ? 0 : days
    api.query<DashboardData>(`/health/dashboard?days=${n}`).then(setData).catch(() => setData(null))
  }, [days, realtimeTick])

  if (!data) {
    // 与加载完成后的结构保持一致，避免数据到达时整页高度突变
    return (
      <div className="flex flex-col gap-4">
        <div className="grid gap-4 md:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="py-4">
                <Skeleton className="h-4 w-20" />
                <Skeleton className="mt-2 h-7 w-24" />
              </CardContent>
            </Card>
          ))}
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          {Array.from({ length: 2 }).map((_, i) => (
            <Card key={i}>
              <CardContent className="py-4">
                <Skeleton className="h-4 w-28" />
                <Skeleton className="mt-3 h-[240px] w-full" />
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    )
  }

  const latest = data.latest_body
  const bmi = latest?.bmi

  return (
    <div className="flex flex-col gap-4">

      <div className="flex justify-end">
        <StatsPeriodPicker
          value={days}
          onChange={(d) => {
            setDays(d)
            setGlobalStatsDays(d)
          }}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">总摄入</div>
            <div className="mt-1 text-2xl font-semibold text-warning">{formatInt(data.intake_total)} kcal</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">总消耗(运动)</div>
            <div className="mt-1 text-2xl font-semibold text-success">{formatInt(data.expenditure_total)} kcal</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">净结余</div>
            <div className="mt-1 text-2xl font-semibold text-info">{data.series.at(-1)?.balance != null ? `${formatInt(data.series.at(-1)?.balance)} kcal` : DASH}</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">运动次数 / 步数</div>
            <div className="mt-1 text-2xl font-semibold">
              {formatInt(data.exercise_count)} 次 <span className="text-base text-muted-foreground">/ {formatInt(data.step_total)} 步</span>
            </div>
          </CardContent>
        </Card>
      </div>

      {latest && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">当前体重</div>
              <div className="mt-1 text-2xl font-semibold">
                {typeof latest.weight_kg === 'number' ? `${formatDecimal(latest.weight_kg, 2)} kg` : DASH}
              </div>
              <div className="text-xs text-muted-foreground">身高 {typeof latest.height_cm === 'number' ? `${formatHealth1(latest.height_cm)} cm` : DASH}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">BMI</div>
              <div className="mt-1 text-2xl font-semibold">{typeof bmi === 'number' ? formatHealth1(bmi) : DASH}</div>
              <div className="text-xs text-muted-foreground">
                {typeof bmi === 'number'
                  ? bmi < 18.5 ? '偏瘦' : bmi < 24 ? '正常' : bmi < 28 ? '超重' : '肥胖'
                  : DASH}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">体脂率</div>
              <div className="mt-1 text-2xl font-semibold">
                {latest.body_fat_percent != null ? formatPercent(latest.body_fat_percent) : DASH}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">身高</div>
              <div className="mt-1 text-2xl font-semibold">
                {typeof latest.height_cm === 'number' ? `${formatHealth1(latest.height_cm)} cm` : DASH}
              </div>
              <div className="text-xs text-muted-foreground">用于 BMI 计算</div>
            </CardContent>
          </Card>
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <BarChartCard
          title="每日摄入 vs 消耗"
          data={data.series}
          xKey="record_date"
          series={[
            { key: 'intake', name: '摄入(kcal)', color: 'chart-3' },
            { key: 'expenditure', name: '消耗(kcal)', color: 'chart-2' },
          ]}
          emptyMessage="所选区间没有摄入与消耗记录"
          emptyAction={<Button size="sm" variant="outline" onClick={() => onGoTo?.('diet')}><Plus className="size-4" /> 去记录饮食</Button>}
        />
        <LineChartCard
          title="运动消耗趋势"
          data={data.expenditure_trend}
          xKey="record_date"
          series={[{ key: 'calories', name: '消耗(kcal)', color: 'chart-2' }]}
          emptyMessage="所选区间还没有运动记录"
          emptyAction={<Button size="sm" variant="outline" onClick={() => onGoTo?.('exercise')}><Plus className="size-4" /> 去记录运动</Button>}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {[
          { key: 'calories', label: '蛋白质', value: `${data.nutrition.protein} g` },
          { key: 'carbs', label: '碳水', value: `${data.nutrition.carbs} g` },
          { key: 'fat', label: '脂肪', value: `${data.nutrition.fat} g` },
          { key: 'total', label: '总热量', value: `${data.nutrition.calories} kcal` },
        ].map((x) => (
          <Card key={x.key}>
            <CardContent className="py-3 text-center">
              <div className="text-sm text-muted-foreground">{x.label}</div>
              <div className="mt-1 text-lg font-semibold">{x.value}</div>
            </CardContent>
          </Card>
        ))}
      </div>

      <LineChartCard
        title="身材趋势（体重 / 体脂率）"
        data={data.body_trend}
        xKey="record_date"
        height={280}
        series={[
          { key: 'weight_kg', name: '体重(kg)', color: 'chart-1' },
          { key: 'body_fat_percent', name: '体脂率(%)', color: 'chart-7' },
        ]}
        emptyMessage="所选区间还没有体重记录"
        emptyAction={<Button size="sm" variant="outline" onClick={() => onGoTo?.('body')}><Plus className="size-4" /> 去记录体重</Button>}
      />
    </div>
  )
}