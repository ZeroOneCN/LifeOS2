import { useEffect, useState } from 'react'
import {
  AlertTriangle,
  Banknote,
  CalendarClock,
  HandCoins,
  Home,
  PiggyBank,
  Plane,
  Receipt,
  ShoppingCart,
  TrendingUp,
  Wallet,
} from 'lucide-react'

import { PageHeader } from '@/components/page-header'
import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardHeaderActions,
  CardTitle,
} from '@/components/ui/card'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { DASH, formatCny, formatInt, formatUsdSigned } from '@/lib/format'

type PendingItem = { id: number; bill_type: string; amount: number; remaining?: number; due_date?: string }
type UpcomingSub = { id: number; title: string; category: string; amount?: number; due_date?: string }
type ActivePlan = { id: number; title: string; plan_type: string; target_amount?: number; saved_amount?: number }

type FinanceOverviewData = {
  month_expense: number
  month_purchase_count: number
  month_travel_count: number
  month_bill_count: number
  utility_count: number
  sub_count: number
  unpaid_bills: number
  outstanding_loans: number
  outstanding_debt: number
  borrow_total: number
  lend_total: number
  invest_pnl: number
  invest_count: number
  deposit_total: number
  categories: { label: string; amount: number }[]
  week_trend: { date: string; amount: number }[]
  pending_bills: PendingItem[]
  pending_utils: PendingItem[]
  upcoming_subs: UpcomingSub[]
  active_plans: ActivePlan[]
}

const fmt = formatCny

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  valueCls,
}: {
  icon: typeof Wallet
  label: string
  value: string
  hint?: string
  valueCls?: string
}) {
  const numeric = Number(value.replace(/[^0-9.-]/g, '')) || 0
  // 盈亏类按数值符号着色（0 中性）；显式 valueCls 优先且不与符号色叠加
  const signTone = label.includes('盈亏')
    ? numeric > 0
      ? 'text-success'
      : numeric < 0
        ? 'text-danger'
        : 'text-muted-foreground'
    : ''
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground min-w-0 max-w-[55%] truncate">{label}</CardTitle>
        <CardHeaderActions>
          <Icon className="size-4 text-muted-foreground" />
        </CardHeaderActions>
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${valueCls || signTone}`}>
          {value}
        </div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

function ItemRow({ item }: { item: PendingItem }) {
  return (
    <div className="flex items-center justify-between rounded-lg border px-3 py-2">
      <div>
        <div className="text-sm font-medium">{item.bill_type}</div>
        <div className="text-xs text-muted-foreground">到期 {item.due_date ?? '—'}</div>
      </div>
      <span className="text-sm font-medium text-danger">{fmt(item.remaining ?? item.amount)}</span>
    </div>
  )
}

export function FinanceOverviewPage() {
  const realtimeTick = useRealtime(30_000)
  const [data, setData] = useState<FinanceOverviewData | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    api
      .query<FinanceOverviewData>('/finance/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [realtimeTick])

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
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
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
        title="财务总览"
        description="汇总本月收支、负债与投资快照，快速掌握整体资金状况。"
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon={Wallet} label="本月支出" value={fmt(data.month_expense)} hint="购/旅/水电/订阅/租/贷" valueCls="text-warning" />
        <StatCard icon={ShoppingCart} label="购物记录" value={`${formatInt(data.month_purchase_count)} 笔`} hint="本月消费笔数" />
        <StatCard icon={Plane} label="旅行开支" value={`${formatInt(data.month_travel_count)} 笔`} hint="本月旅行费用笔数" />
        <StatCard icon={Receipt} label="网贷未还" value={fmt(data.unpaid_bills)} hint={`本月 ${formatInt(data.month_bill_count)} 笔账单`} />
        <StatCard icon={HandCoins} label="累计待还" value={fmt(data.outstanding_loans + data.outstanding_debt)} hint={`网贷 ${fmt(data.outstanding_loans)} + 民间 ${fmt(data.outstanding_debt)}`} />
        <StatCard icon={Home} label="组合房租" value={fmt(data.categories.find((c) => c.label === '住房月租')?.amount ?? 0)} hint="当月折算" />
        <StatCard icon={Banknote} label="借贷往来" value={fmt(data.lend_total)} hint={`借出 ${fmt(data.lend_total)} / 借入 ${fmt(data.borrow_total)}`} />
        <StatCard icon={TrendingUp} label="投资盈亏" value={formatUsdSigned(data.invest_pnl)} hint={`共 ${formatInt(data.invest_count)} 项持仓`} />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">本月支出构成</CardTitle>
            <CardDescription>按类别汇总本月支出</CardDescription>
          </CardHeader>
          <CardContent>
            {data.categories.length > 0 ? (
              <ul className="grid gap-2 sm:grid-cols-2">
                {data.categories.map((c) => (
                  <li key={c.label} className="flex items-center justify-between rounded-lg border px-3 py-2">
                    <span className="truncate text-sm text-muted-foreground">{c.label}</span>
                    <span className="shrink-0 text-sm font-medium">{fmt(c.amount)}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">暂无支出数据</p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">近 7 天支出趋势</CardTitle>
            <CardDescription>每日支出金额</CardDescription>
          </CardHeader>
          <CardContent>
            {data.week_trend.length > 0 ? (
              <ul className="grid gap-2 sm:grid-cols-2">
                {data.week_trend.map((d) => (
                  <li key={d.date} className="flex items-center justify-between rounded-lg border px-3 py-2">
                    <span className="truncate text-sm text-muted-foreground">{d.date}</span>
                    <span className="shrink-0 text-sm font-medium">{fmt(d.amount)}</span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="py-8 text-center text-sm text-muted-foreground">暂无趋势数据</p>
            )}
          </CardContent>
        </Card>
      </section>

      <section className="grid items-start gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-warning" />
              待支付网贷账单
            </CardTitle>
            <CardDescription>按到期日排序，请及时处理</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.pending_bills.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">暂无待支付榜单</p>
            ) : (
              data.pending_bills.map((b) => <ItemRow key={b.id} item={b} />)
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <CalendarClock className="size-4 text-decor-violet" />
              即将续费订阅
            </CardTitle>
            <CardDescription>临近到期，记得续费</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.upcoming_subs.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">暂无临期订阅</p>
            ) : (
              data.upcoming_subs.map((s) => (
                <div key={s.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{s.title}</div>
                    <div className="text-xs text-muted-foreground">
                      {s.category} · 到期 {s.due_date ?? '—'}
                    </div>
                  </div>
                  {s.amount != null && <span className="text-sm font-medium">{fmt(s.amount)}</span>}
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Banknote className="size-4 text-info" />
              待缴水电账单
            </CardTitle>
            <CardDescription>按到期日排序，请及时处理</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.pending_utils.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted-foreground">暂无待缴水电账单</p>
            ) : (
              data.pending_utils.map((u) => <ItemRow key={u.id} item={u} />)
            )}
          </CardContent>
        </Card>
      </section>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <PiggyBank className="size-4 text-success" />
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
                    ? Math.min(100, (p.saved_amount / p.target_amount) * 100)
                    : 0
                return (
                  <div key={p.id} className="rounded-lg border px-3 py-2">
                    <div className="flex items-center justify-between">
                      <div>
                        <span className="text-sm font-medium">{p.title}</span>
                        <Badge className="ml-2 bg-info-muted text-info-muted-foreground">{p.plan_type}</Badge>
                      </div>
                      <span className="text-xs text-muted-foreground">
                        {p.saved_amount != null ? fmt(p.saved_amount) : DASH} /{' '}
                        {p.target_amount != null ? fmt(p.target_amount) : DASH}
                      </span>
                    </div>
                    {p.target_amount && p.saved_amount ? (
                      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-full rounded-full bg-success-muted"
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