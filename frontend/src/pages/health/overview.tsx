import { useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ChevronRight, Footprints, MoonStar, Pill, Timer } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
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

type Body = {
  id: number
  record_date: string
  height_cm?: number
  weight_kg?: number
  bmi?: number
  body_fat_percent?: number
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
  latest_body: Body | null
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
  to,
}: {
  icon: typeof Footprints
  label: string
  value: string
  hint?: string
  to?: string
}) {
  const body = (
    <Card className="h-full transition-colors hover:border-foreground/20 hover:bg-muted/40">
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
  if (to) {
    return <Link to={to} className="block">{body}</Link>
  }
  return body
}

function SectionCard({
  title,
  to,
  children,
}: {
  title: string
  to?: string
  children: ReactNode
}) {
  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-sm">
          <span>{title}</span>
          {to && (
            <Link to={to} className="flex items-center gap-0.5 text-xs text-muted-foreground hover:text-foreground">
              查看
              <ChevronRight className="size-3.5" />
            </Link>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
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
  const body = data.latest_body
  const med = data.today_medication

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">健康总览</h1>
        <p className="text-sm text-muted-foreground">
          汇总最近的健康数据，快速了解当前状态。点击板块可跳转到对应页面。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={Footprints}
          label="本周步数"
          value={data.week_summary.steps_total.toLocaleString()}
          hint={data.week_summary.steps_avg ? `日均 ${data.week_summary.steps_avg.toLocaleString()} 步` : '暂无数据'}
          to="/health/steps"
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
          to="/health/vitals-sleep"
        />
        <StatCard
          icon={Timer}
          label="本周运动"
          value={`${data.week_summary.fitness_count} 次`}
          hint={`消耗 ${data.week_summary.fitness_calories} kcal`}
          to="/health/fitness?tab=exercise"
        />
        <StatCard
          icon={Pill}
          label="今日用药"
          value={`${med.pending_count} 项待服`}
          hint={`已服 ${med.taken_count} 项`}
          to="/health/medication"
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="最近体征" to="/health/vitals-sleep">
          {v ? (
            <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
              {[
                ['血压', v.blood_pressure_high && v.blood_pressure_low ? `${v.blood_pressure_high}/${v.blood_pressure_low}` : '—'],
                ['心率', v.heart_rate ? `${v.heart_rate} bpm` : '—'],
                ['血氧', v.blood_oxygen ? `${v.blood_oxygen}%` : '—'],
                ['睡眠', v.sleep_duration_min ? `${Math.floor(v.sleep_duration_min / 60)}h${v.sleep_duration_min % 60}m` : '—'],
                ['睡眠质量', v.sleep_quality ? `${v.sleep_quality}/10` : '—'],
                // 体重接入健身运动的体重记录
                body && ['体重', body.weight_kg ? `${body.weight_kg} kg` : '—'],
              ]
                .filter((t): t is [string, string] => !!t)
                .map(([label, value]) =>
                  label === '体重' ? (
                    <Link
                      key={label}
                      to="/health/fitness?tab=body"
                      className="rounded-lg bg-muted/50 p-3 transition-colors hover:bg-muted"
                      title="点击前往健身运动 → 体重记录"
                    >
                      <div className="text-xs text-muted-foreground">{label}</div>
                      <div className="mt-1 font-medium">{value}</div>
                    </Link>
                  ) : (
                    <div key={label} className="rounded-lg bg-muted/50 p-3">
                      <div className="text-xs text-muted-foreground">{label}</div>
                      <div className="mt-1 font-medium">{value}</div>
                    </div>
                  ),
                )}
            </div>
          ) : (
            <p className="py-8 text-center text-sm text-muted-foreground">
              前往「睡眠体征」录入第一条数据
            </p>
          )}
        </SectionCard>

        <SectionCard title="今日用药" to="/health/medication">
          {med.items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              前往「用药跟踪」记录今日用药
            </p>
          ) : (
            <div className="space-y-2">
              {med.items.map((item) => (
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
              ))}
            </div>
          )}
        </SectionCard>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="最近体检指标" to="/health/checkup">
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
        </SectionCard>

        <SectionCard title="最新健康报告" to="/health/reports">
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
        </SectionCard>
      </section>
    </div>
  )
}
