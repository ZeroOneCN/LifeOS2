import { useEffect, useState } from 'react'
import { Footprints, MoonStar, Pill, Timer } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { api } from '@/lib/api'

type Vitals = {
  id: number
  record_date: string
  blood_pressure_high?: number
  blood_pressure_low?: number
  heart_rate?: number
  blood_oxygen?: number
  weight?: number
  sleep_duration_min?: number
  sleep_quality?: number
}

type MedItem = {
  id: number
  medicine_name: string
  dosage?: string
  frequency?: string
  taken: boolean
}

type OverviewData = {
  latest_steps: { steps: number; record_date: string } | null
  latest_vitals: Vitals | null
  today_medication: { taken_count: number; pending_count: number; items: MedItem[] }
  recent_checkup: {
    id: number
    check_date: string
    item_name: string
    value?: number
    unit?: string
    result?: string
  }[]
  latest_report: { id: number; report_date: string; title: string; summary?: string } | null
  week_summary: {
    steps_total: number
    steps_avg?: number
    sleep_avg_min?: number
    fitness_count: number
    fitness_calories: number
  }
}

const resultMeta: Record<string, { label: string; className: string }> = {
  normal: { label: '正常', className: 'bg-green-100 text-green-700' },
  high: { label: '偏高', className: 'bg-red-100 text-red-700' },
  low: { label: '偏低', className: 'bg-amber-100 text-amber-700' },
}

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: typeof Footprints
  label: string
  value: string
  hint?: string
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {label}
        </CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function HealthOverviewPage() {
  const [data, setData] = useState<OverviewData | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    api
      .query<OverviewData>('/health/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [])

  if (error) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          健康数据加载失败，请确认后端服务已启动。
        </CardContent>
      </Card>
    )
  }

  if (!data) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i}>
            <CardContent className="h-24 animate-pulse bg-muted/50" />
          </Card>
        ))}
      </div>
    )
  }

  const v = data.latest_vitals
  const med = data.today_medication

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">健康总览</h1>
        <p className="text-sm text-muted-foreground">
          汇总最近的健康数据，快速了解当前状态。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={Footprints}
          label="本周步数"
          value={data.week_summary.steps_total.toLocaleString()}
          hint={data.week_summary.steps_avg ? `日均 ${data.week_summary.steps_avg.toLocaleString()} 步` : '暂无数据'}
        />
        <StatCard
          icon={MoonStar}
          label="平均睡眠"
          value={
            data.week_summary.sleep_avg_min != null
              ? `${Math.floor(data.week_summary.sleep_avg_min / 60)}h${data.week_summary.sleep_avg_min % 60}m`
              : '—'
          }
          hint="近 7 天"
        />
        <StatCard
          icon={Timer}
          label="本周运动"
          value={`${data.week_summary.fitness_count} 次`}
          hint={`消耗 ${data.week_summary.fitness_calories} kcal`}
        />
        <StatCard
          icon={Pill}
          label="今日用药"
          value={`${med.pending_count} 项待服`}
          hint={`已服 ${med.taken_count} 项`}
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">最近体征</CardTitle>
            <CardDescription>
              {v ? `${v.record_date} 记录` : '暂无体征数据'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {v ? (
              <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
                {[
                  ['血压', v.blood_pressure_high && v.blood_pressure_low ? `${v.blood_pressure_high}/${v.blood_pressure_low}` : '—'],
                  ['心率', v.heart_rate ? `${v.heart_rate} bpm` : '—'],
                  ['血氧', v.blood_oxygen ? `${v.blood_oxygen}%` : '—'],
                  ['体重', v.weight ? `${v.weight} kg` : '—'],
                  ['睡眠', v.sleep_duration_min ? `${Math.floor(v.sleep_duration_min / 60)}h${v.sleep_duration_min % 60}m` : '—'],
                  ['睡眠质量', v.sleep_quality ? `${v.sleep_quality}/10` : '—'],
                ].map(([label, value]) => (
                  <div key={label} className="rounded-lg bg-muted/50 p-3">
                    <div className="text-xs text-muted-foreground">{label}</div>
                    <div className="mt-1 font-medium">{value}</div>
                  </div>
                ))}
              </div>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">
                前往「睡眠体征」录入第一条数据
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">今日用药</CardTitle>
            <CardDescription>
              {med.items.length > 0 ? `共 ${med.items.length} 项` : '今日暂无用药记录'}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {med.items.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                前往「用药跟踪」记录今日用药
              </p>
            ) : (
              med.items.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between rounded-lg border px-3 py-2"
                >
                  <div>
                    <div className="text-sm font-medium">{item.medicine_name}</div>
                    <div className="text-xs text-muted-foreground">
                      {[item.dosage, item.frequency].filter(Boolean).join(' · ') || '—'}
                    </div>
                  </div>
                  <Badge className={item.taken ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}>
                    {item.taken ? '已服' : '待服'}
                  </Badge>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">最近体检指标</CardTitle>
          </CardHeader>
          <CardContent>
            {data.recent_checkup.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                暂无体检数据
              </p>
            ) : (
              <div className="divide-y">
                {data.recent_checkup.map((c) => (
                  <div key={c.id} className="flex items-center justify-between py-2">
                    <div>
                      <div className="text-sm">{c.item_name}</div>
                      <div className="text-xs text-muted-foreground">{c.check_date}</div>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium">
                        {c.value != null ? `${c.value} ${c.unit ?? ''}` : '—'}
                      </span>
                      {c.result && (
                        <Badge className={resultMeta[c.result]?.className}>
                          {resultMeta[c.result]?.label ?? c.result}
                        </Badge>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm">最新健康报告</CardTitle>
          </CardHeader>
          <CardContent>
            {data.latest_report ? (
              <div className="space-y-1">
                <div className="text-sm font-medium">{data.latest_report.title}</div>
                <div className="text-xs text-muted-foreground">
                  {data.latest_report.report_date}
                </div>
                {data.latest_report.summary && (
                  <p className="text-sm text-muted-foreground">
                    {data.latest_report.summary}
                  </p>
                )}
              </div>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">
                暂无健康报告
              </p>
            )}
          </CardContent>
        </Card>
      </section>
    </div>
  )
}
