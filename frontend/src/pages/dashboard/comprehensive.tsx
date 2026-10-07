import { useEffect, useState } from 'react'
import { Heart, Wallet, ShoppingBag, TrendingUp } from 'lucide-react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { api } from '@/lib/api'

type ComprehensiveReport = {
  period: { start: string; end: string; days: number }
  health: {
    steps_total: number
    sleep_avg_min: number | null
    fitness_count: number
    checkup_count: number
    medication_records: number
  }
  finance: {
    debt_remaining: number
    pending_reminders: number
    unpaid_utilities: number
  }
  lifestyle: {
    todos_done: number
    todos_pending: number
    items_expiring_30d: number
  }
  investment: {
    forex_records: number
    fund_records: number
  }
}

type MetricItem = { label: string; value: string | number }

/** 指标卡片：以图标 + 标题 + 指标列表展示某领域汇总。 */
function DomainCard({
  icon,
  title,
  items,
}: {
  icon: React.ReactNode
  title: string
  items: MetricItem[]
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center gap-2 pb-2">
        {icon}
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {items.map((it) => (
          <div key={it.label} className="rounded-lg bg-muted/40 p-3">
            <div className="text-xs text-muted-foreground">{it.label}</div>
            <div className="mt-1 text-xl font-semibold">{it.value}</div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

/** 跨模块综合报告页面：展示健康/财务/生活/投资各领域关键指标。 */
export function ComprehensiveReportPage() {
  const [data, setData] = useState<ComprehensiveReport | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api
      .query<ComprehensiveReport>('/reports/comprehensive?days=30')
      .then((d) => setData(d))
      .catch(() => setData(null))
      .finally(() => setLoading(false))
  }, [])

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-48" />
        <div className="grid gap-4 lg:grid-cols-2">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-40" />
          ))}
        </div>
      </div>
    )
  }

  if (!data) {
    return <div className="text-muted-foreground">加载综合报告失败，请稍后重试。</div>
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">跨模块综合报告</h1>
        <span className="text-sm text-muted-foreground">
          周期：{data.period.start} ~ {data.period.end}
        </span>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <DomainCard
          icon={<Heart className="size-5 text-rose-500" />}
          title="健康"
          items={[
            { label: '步数累计', value: data.health.steps_total.toLocaleString() },
            { label: '平均睡眠(分)', value: data.health.sleep_avg_min ?? '-' },
            { label: '运动次数', value: data.health.fitness_count },
            { label: '体检记录', value: data.health.checkup_count },
            { label: '用药记录', value: data.health.medication_records },
          ]}
        />
        <DomainCard
          icon={<Wallet className="size-5 text-amber-500" />}
          title="财务"
          items={[
            { label: '待还债务', value: `¥${data.finance.debt_remaining.toLocaleString()}` },
            { label: '待办提醒', value: data.finance.pending_reminders },
            { label: '未缴账单', value: data.finance.unpaid_utilities },
          ]}
        />
        <DomainCard
          icon={<ShoppingBag className="size-5 text-emerald-500" />}
          title="生活"
          items={[
            { label: '已完成待办', value: data.lifestyle.todos_done },
            { label: '待办总数', value: data.lifestyle.todos_pending },
            { label: '30天内到期物品', value: data.lifestyle.items_expiring_30d },
          ]}
        />
        <DomainCard
          icon={<TrendingUp className="size-5 text-blue-500" />}
          title="投资"
          items={[
            { label: '外汇记录', value: data.investment.forex_records },
            { label: '基金记录', value: data.investment.fund_records },
          ]}
        />
      </div>
    </div>
  )
}
