import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AlertTriangle,
  CalendarClock,
  CreditCard,
  FileText,
  ListTodo,
  Package,
  Smartphone,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { api } from '@/lib/api'

type ExpiringItem = { id: number; item_name: string; category: string; expire_date?: string; days_left: number }
type PendingTodo = { id: number; title: string; category?: string; due_date?: string; priority: string }
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
  todo_total: number
  todo_pending: number
  todo_overdue: number
  expiring_items: ExpiringItem[]
  pending_todos: PendingTodo[]
  latest_report: LatestReport | null
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

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
  if (to) return <Link to={to} className="block">{body}</Link>
  return body
}

function SectionCard({ title, to, children }: { title: string; to?: string; children: React.ReactNode }) {
  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-sm">
          <span>{title}</span>
          {to && (
            <Link to={to} className="text-xs text-muted-foreground hover:text-foreground">
              查看
            </Link>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

const priortyMeta: Record<string, { label: string; className: string }> = {
  high: { label: '高', className: 'bg-red-100 text-red-700' },
  medium: { label: '中', className: 'bg-amber-100 text-amber-700' },
  low: { label: '低', className: 'bg-blue-100 text-blue-700' },
}

export function LifestyleOverviewPage() {
  const [data, setData] = useState<OverviewData | null>(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    api
      .query<OverviewData>('/lifestyle/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [])

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
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">生活总览</h1>
        <p className="text-sm text-muted-foreground">
          汇总物品、卡片、待办与扣账情况，快速掌握生活资产与待办。点击板块可跳转到对应页面。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
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
          value={`${data.phone_total} 张`}
          hint={`正常 ${data.phone_active} 张 · 月租 ${fmt(data.phone_monthly_fee)}`}
          to="/lifestyle/cards"
        />
        <StatCard
          icon={CreditCard}
          label="银行卡"
          value={`${data.bank_total} 张`}
          hint={`正常 ${data.bank_active} 张 · 本月扣账 ${fmt(data.month_deduct)}`}
          to="/lifestyle/cards"
        />
        <StatCard
          icon={ListTodo}
          label="待办清单"
          value={`${data.todo_pending} 项待办`}
          hint={`共 ${data.todo_total} 项 · 逾期 ${data.todo_overdue} 项`}
          to="/lifestyle/todos"
        />
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="即将过期物品" to="/lifestyle/items">
          {data.expiring_items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              暂无临期物品{data.item_expired > 0 ? `，但已有 ${data.item_expired} 件过期` : ''}
            </p>
          ) : (
            <div className="space-y-2">
              {data.expiring_items.map((item) => (
                <div key={item.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{item.item_name}</div>
                    <div className="text-xs text-muted-foreground">
                      {item.category} · {item.expire_date ?? '—'}
                    </div>
                  </div>
                  <Badge
                    className={item.days_left <= 7 ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}
                  >
                    剩 {item.days_left} 天
                  </Badge>
                </div>
              ))}
              {data.item_expired > 0 && (
                <p className="text-xs text-destructive">另有 {data.item_expired} 件已过期</p>
              )}
            </div>
          )}
        </SectionCard>

        <SectionCard title="待处理待办" to="/lifestyle/todos">
          {data.pending_todos.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">暂无待办</p>
          ) : (
            <div className="space-y-2">
              {data.pending_todos.map((t) => (
                <div key={t.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{t.title}</div>
                    <div className="text-xs text-muted-foreground">
                      {t.category ?? '未分类'} · 截止 {t.due_date ?? '—'}
                    </div>
                  </div>
                  <Badge className={priortyMeta[t.priority]?.className}>
                    {priortyMeta[t.priority]?.label ?? t.priority}
                  </Badge>
                </div>
              ))}
              {data.todo_overdue > 0 && (
                <p className="text-xs text-destructive">{data.todo_overdue} 项已逾期，请尽快处理</p>
              )}
            </div>
          )}
        </SectionCard>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <AlertTriangle className="size-4 text-amber-500" />
              卡片待办
            </CardTitle>
            <CardDescription>本月尚未扣账的手机卡与临期提醒</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <span className="text-muted-foreground">本月未扣账手机卡</span>
              <span className="font-medium">{data.phone_unpaid} 张</span>
            </div>
            <div className="flex items-center justify-between rounded-lg border px-3 py-2">
              <span className="text-muted-foreground">本月累计扣账</span>
              <span className="font-medium text-red-600">{fmt(data.month_deduct)}</span>
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
              <FileText className="size-4 text-emerald-500" />
              最新生活报告
            </CardTitle>
          </CardHeader>
          <CardContent>
            {data.latest_report ? (
              <div className="space-y-1">
                <div className="text-sm font-medium">{data.latest_report.title}</div>
                <div className="text-xs text-muted-foreground">{data.latest_report.period_label ?? ''}</div>
                {data.latest_report.summary && (
                  <p className="text-sm text-muted-foreground">{data.latest_report.summary}</p>
                )}
                <Link
                  to="/lifestyle/reports"
                  className="mt-2 inline-flex items-center gap-1 text-xs text-emerald-600 hover:underline"
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