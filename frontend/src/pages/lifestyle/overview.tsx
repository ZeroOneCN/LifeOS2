import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AlertTriangle,
  CalendarClock,
  CreditCard,
  FileText,
  Package,
  Smartphone,
} from 'lucide-react'

import { PageHeader } from '@/components/page-header'
import { Card, CardContent, CardDescription, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { formatCny, formatInt, reportSummary, reportTitle } from '@/lib/format'

type LatestReport = { id: number; title: string; period_label?: string; summary?: string }

type OverviewData = {
  item_total: number
  item_in_use: number
  item_value: number
  item_avg_daily_cost: number
  item_expiring: number
  item_expired: number
  phone_total: number
  phone_active: number
  phone_monthly_fee: number
  phone_unpaid: number
  bank_total: number
  bank_active: number
  month_deduct: number
  month_deduct_count: number
  latest_report: LatestReport | null
}

const fmt = formatCny

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  to,
}: {
  icon: typeof Package
  label: string
  value: string
  hint?: string
  to?: string
}) {
  const body = (
    <Card className="h-full transition-colors hover:border-foreground/20 hover:bg-muted/40">
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground min-w-0 max-w-[55%] truncate">{label}</CardTitle>
        <CardHeaderActions>
          <Icon className="size-4 text-muted-foreground" />
        </CardHeaderActions>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
  if (to) return <Link to={to} className="block">{body}</Link>
  return body
}

export function LifestyleOverviewPage() {
  const realtimeTick = useRealtime(30_000)
  const [data, setData] = useState<OverviewData | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    api
      .query<OverviewData>('/lifestyle/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [realtimeTick])

  if (error) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          生活数据加载失败，请确认后端服务已启动。
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

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="生活总览"
        description="汇总物品、卡片、待办与扣账情况，快速掌握生活资产与待办。点击板块可跳转到对应页面。"
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          icon={Package}
          label="物品追踪"
          value={`${data.item_total} 件`}
          hint={`使用中 ${data.item_in_use} 件 · 总值 ${fmt(data.item_value)}`}
          to="/lifestyle/items"
        />
        <StatCard
          icon={Smartphone}
          label="手机卡"
          value={`${formatInt(data.phone_total)} 张`}
          hint={`正常 ${formatInt(data.phone_active)} 张 · 月租 ${fmt(data.phone_monthly_fee)}`}
          to="/lifestyle/cards"
        />
        <StatCard
          icon={CreditCard}
          label="银行卡"
          value={`${formatInt(data.bank_total)} 张`}
          hint={`正常 ${formatInt(data.bank_active)} 张 · 本月扣账 ${fmt(data.month_deduct)}`}
          to="/lifestyle/cards"
        />
        <StatCard
          icon={AlertTriangle}
          label="临期物品"
          value={`${formatInt(data.item_expiring)} 件`}
          hint={data.item_expired > 0 ? `另有 ${formatInt(data.item_expired)} 件已过期` : '30 天内到期'}
          to="/lifestyle/items"
        />
      </section>

      <section className="grid items-start gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-warning" />
              卡片待办
            </CardTitle>
            <CardDescription>本月尚未扣账的手机卡与临期提醒</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <span className="text-muted-foreground">本月未扣账手机卡</span>
              <span className="font-medium">{formatInt(data.phone_unpaid)} 张</span>
            </div>
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <span className="text-muted-foreground">本月累计扣账</span>
              <span className="font-medium text-danger">{fmt(data.month_deduct)}</span>
            </div>
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <span className="text-muted-foreground">有效物品日均成本（平均）</span>
              <span className="font-medium">{data.item_avg_daily_cost ? fmt(data.item_avg_daily_cost) + '/天' : '—'}</span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <FileText className="size-4 text-success" />
              最新生活报告
            </CardTitle>
          </CardHeader>
          <CardContent>
            {data.latest_report ? (
              <div className="space-y-1">
                <div className="text-sm font-medium">{reportTitle(data.latest_report.title)}</div>
                <div className="text-xs text-muted-foreground">{data.latest_report.period_label ?? ''}</div>
                {data.latest_report.summary && (
                  <p className="text-sm text-muted-foreground">{reportSummary(data.latest_report.summary)}</p>
                )}
                <Link
                  to="/lifestyle/reports"
                  className="mt-2 inline-flex items-center gap-1 text-xs text-success hover:underline"
                >
                  <CalendarClock className="size-3.5" />
                  前往生活报告
                </Link>
              </div>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">
                暂无生活报告，前往「生活报告」生成
              </p>
            )}
          </CardContent>
        </Card>
      </section>
    </div>
  )
}