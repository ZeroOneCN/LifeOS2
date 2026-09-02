import { useEffect, useState } from 'react'

import { Card, CardContent } from '@/components/ui/card'
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'

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

export function FitnessDashboardPage() {
  const [data, setData] = useState<DashboardData | null>(null)

  useEffect(() => {
    api.query<DashboardData>('/health/fitness/dashboard').then(setData).catch(() => setData(null))
  }, [])

  if (!data) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">健身-数据看板</h1>
        <p className="text-sm text-muted-foreground">汇总饮食摄入与运动消耗、身材趋势分析。加载中...</p>
      </div>
    )
  }

  const latest = data.latest_body
  const bmi = latest?.bmi

  return (
    <div className="flex flex-col gap-4">
      <section>
        <h1 className="font-heading text-2xl font-semibold tracking-tight">健身-数据看板</h1>
        <p className="text-sm text-muted-foreground">
          汇总饮食摄入与运动消耗，结合体重/体成分进行身材趋势分析。
        </p>
      </section>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">总摄入</div>
            <div className="mt-1 text-2xl font-semibold text-orange-500">{data.intake_total} kcal</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">总消耗(运动)</div>
            <div className="mt-1 text-2xl font-semibold text-emerald-500">{data.expenditure_total} kcal</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">净结余</div>
            <div className="mt-1 text-2xl font-semibold text-sky-500">{data.series.at(-1)?.balance ?? '-'} kcal</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="py-4">
            <div className="text-sm text-muted-foreground">运动次数 / 步数</div>
            <div className="mt-1 text-2xl font-semibold">
              {data.exercise_count} 次 <span className="text-base text-muted-foreground">/ {data.step_total} 步</span>
            </div>
          </CardContent>
        </Card>
      </div>

      {latest && (
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">当前体重</div>
              <div className="mt-1 text-2xl font-semibold">{latest.weight_kg ?? '-'} kg</div>
              <div className="text-xs text-muted-foreground">身高 {latest.height_cm ?? '-'} cm</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">BMI</div>
              <div className="mt-1 text-2xl font-semibold">{bmi ?? '-'}</div>
              <div className="text-xs text-muted-foreground">
                {typeof bmi === 'number'
                  ? bmi < 18.5 ? '偏瘦' : bmi < 24 ? '正常' : bmi < 28 ? '超重' : '肥胖'
                  : '-'}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">体脂率</div>
              <div className="mt-1 text-2xl font-semibold">
                {latest.body_fat_percent != null ? `${latest.body_fat_percent}%` : '-'}
              </div>
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
            { key: 'intake', name: '摄入(kcal)', color: '#f59e0b' },
            { key: 'expenditure', name: '消耗(kcal)', color: '#10b981' },
          ]}
        />
        <LineChartCard
          title="运动消耗趋势"
          data={data.expenditure_trend}
          xKey="record_date"
          series={[{ key: 'calories', name: '消耗(kcal)', color: '#10b981' }]}
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

      {data.body_trend.length > 0 && (
        <LineChartCard
          title="身材趋势（体重 / 体脂率）"
          data={data.body_trend}
          xKey="record_date"
          height={280}
          series={[
            { key: 'weight_kg', name: '体重(kg)', color: '#6366f1' },
            { key: 'body_fat_percent', name: '体脂率(%)', color: '#f43f5e' },
          ]}
        />
      )}
    </div>
  )
}