import { useEffect, useState } from 'react'
import { AlertTriangle, PiggyBank, Plane, Receipt, ShoppingCart, Wallet } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { BarChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'

type PendingBill = { id: number; bill_type: string; amount: number; due_date?: string }
type PendingReminder = { id: number; title: string; category: string; amount?: number; due_date?: string }
type ActivePlan = { id: number; title: string; plan_type: string; target_amount?: number; saved_amount?: number }

type FinanceOverviewData = {
  month_expense: number
  month_purchase_count: number
  month_travel_count: number
  month_bill_count: number
  unpaid_bills: number
  week_trend: { date: string; amount: number }[]
  pending_bills: PendingBill[]
  pending_reminders: PendingReminder[]
  active_plans: ActivePlan[]
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: typeof Wallet
  label: string
  value: string
  hint?: string
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function FinanceOverviewPage() {
  const [data, setData] = useState<FinanceOverviewData | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    api
      .query<FinanceOverviewData>('/finance/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [])

  if (error) {
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          财务数据加载失败，请确认后端服务已启动。
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
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">财务总览</h1>
        <p className="text-sm text-muted-foreground">
          汇总本月收支与待办财务事项，快速掌握资金状况。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={Wallet}
          label="本月支出"
          value={fmt(data.month_expense)}
          hint="购买 + 旅行 + 账单"
        />
        <StatCard
          icon={ShoppingCart}
          label="购买记录"
          value={`${data.month_purchase_count} 笔`}
          hint="本月消费笔数"
        />
        <StatCard
          icon={Plane}
          label="旅行开支"
          value={`${data.month_travel_count} 笔`}
          hint="本月旅行费用笔数"
        />
        <StatCard
          icon={Receipt}
          label="待付账单"
          value={fmt(data.unpaid_bills)}
          hint={`共 ${data.month_bill_count} 笔账单`}
        />
      </section>

      {data.week_trend.length > 0 && (
        <BarChartCard
          title="近 7 天支出趋势"
          data={data.week_trend}
          xKey="date"
          series={[{ key: 'amount', name: '支出', color: '#ef4444' }]}
        />
      )}

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-amber-500" />
              待支付账单
            </CardTitle>
            <CardDescription>按到期日排序，请及时处理</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.pending_bills.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                暂无待支付账单
              </p>
            ) : (
              data.pending_bills.map((b) => (
                <div
                  key={b.id}
                  className="flex items-center justify-between rounded-lg border px-3 py-2"
                >
                  <div>
                    <div className="text-sm font-medium">{b.bill_type}</div>
                    <div className="text-xs text-muted-foreground">
                      到期 {b.due_date ?? '—'}
                    </div>
                  </div>
                  <span className="text-sm font-medium">{fmt(b.amount)}</span>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-red-500" />
              待办提醒
            </CardTitle>
            <CardDescription>缴费、还款等未处理事项</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.pending_reminders.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">
                暂无待办提醒
              </p>
            ) : (
              data.pending_reminders.map((r) => (
                <div
                  key={r.id}
                  className="flex items-center justify-between rounded-lg border px-3 py-2"
                >
                  <div>
                    <div className="text-sm font-medium">{r.title}</div>
                    <div className="text-xs text-muted-foreground">
                      {r.category} · 截止 {r.due_date ?? '—'}
                    </div>
                  </div>
                  {r.amount != null && (
                    <span className="text-sm font-medium">{fmt(r.amount)}</span>
                  )}
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </section>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <PiggyBank className="size-4 text-emerald-500" />
            进行中的财务规划
          </CardTitle>
        </CardHeader>
        <CardContent>
          {data.active_plans.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              暂无进行中的规划，前往「财务规划」制定目标
            </p>
          ) : (
            <div className="space-y-2">
              {data.active_plans.map((p) => {
                const pct =
                  p.target_amount && p.saved_amount
                    ? Math.min(100, Math.round((p.saved_amount / p.target_amount) * 100))
                    : 0
                return (
                  <div key={p.id} className="rounded-lg border px-3 py-2">
                    <div className="flex items-center justify-between">
                      <div>
                        <span className="text-sm font-medium">{p.title}</span>
                        <Badge className="ml-2 bg-blue-100 text-blue-700">{p.plan_type}</Badge>
                      </div>
                      <span className="text-xs text-muted-foreground">
                        {p.saved_amount != null ? fmt(p.saved_amount) : '—'} /{' '}
                        {p.target_amount != null ? fmt(p.target_amount) : '—'}
                      </span>
                    </div>
                    {p.target_amount && p.saved_amount ? (
                      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-full rounded-full bg-emerald-500"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    ) : null}
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
