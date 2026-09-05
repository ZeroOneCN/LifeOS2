import { useEffect, useState } from 'react'
import { Bell, CheckCircle2, Loader2, Mail } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'

type NotificationRecord = {
  id: number
  title: string
  content?: string
  category: string
  source?: string
  read: boolean
  notify_date: string
  note?: string
}

type NotificationStats = {
  total: number
  unread: number
  today: number
  by_category: { category: string; count: number }[]
  trend: { notify_date: string; count: number }[]
}

const categoryStyle: Record<string, string> = {
  系统: 'bg-blue-100 text-blue-700',
  健康: 'bg-green-100 text-green-700',
  财务: 'bg-amber-100 text-amber-700',
  生活: 'bg-purple-100 text-purple-700',
  投资: 'bg-cyan-100 text-cyan-700',
  其他: 'bg-gray-100 text-gray-600',
}

function StatCard({
  icon: Icon,
  label,
  value,
  className,
}: {
  icon: typeof Bell
  label: string
  value: string
  className?: string
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
      </CardContent>
    </Card>
  )
}

export function NotificationList() {
  const [items, setItems] = useState<NotificationRecord[]>([])
  const [stats, setStats] = useState<NotificationStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const totalPages = Math.max(1, Math.ceil(total / 10))

  const load = async () => {
    setLoading(true)
    try {
      const [listRes, statsRes] = await Promise.all([
        api.list<NotificationRecord>('/notifications', { page, page_size: 10 }),
        api.query<NotificationStats>('/notifications/stats?days=30'),
      ])
      setItems(listRes.items)
      setTotal(listRes.total)
      setStats(statsRes)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [page]) // eslint-disable-line react-hooks/exhaustive-deps

  const byCategory = stats?.by_category ?? []
  const trend = stats?.trend ?? []

  return (
    <div className="flex flex-col gap-4">
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard icon={Mail} label="未读提醒" value={String(stats?.unread ?? '—')} className="text-blue-500" />
        <StatCard icon={Bell} label="今日提醒" value={String(stats?.today ?? '—')} className="text-amber-500" />
        <StatCard icon={CheckCircle2} label="提醒总数" value={String(stats?.total ?? '—')} className="text-green-500" />
      </section>

      {byCategory.length > 0 || trend.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="提醒类型分布"
            data={byCategory}
            xKey="category"
            series={[{ key: 'count', name: '数量', color: '#6366f1' }]}
          />
          <LineChartCard
            title="近30天提醒趋势"
            data={trend}
            xKey="notify_date"
            series={[{ key: 'count', name: '提醒数', color: '#0ea5e9' }]}
          />
        </div>
      ) : null}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">提醒台账</CardTitle>
          <CardDescription>系统按提醒开关自动生成的下发记录，各渠道发送结果见「发送记录」</CardDescription>
        </CardHeader>
        <CardContent className={`space-y-2 transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
          {items.length === 0 ? (
            loading ? (
              <div className="flex justify-center py-12 text-muted-foreground">
                <Loader2 className="size-5 animate-spin" />
              </div>
            ) : (
              <p className="py-12 text-center text-sm text-muted-foreground">
                暂无提醒记录，提醒会自动生成于此
              </p>
            )
          ) : (
            items.map((row) => (
              <div key={row.id} className="flex items-start gap-4 rounded-lg border px-4 py-3">
                <div className="flex min-w-0 flex-1 gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-sm font-medium">{row.title}</span>
                      <Badge className={categoryStyle[row.category] ?? categoryStyle.其他}>
                        {row.category}
                      </Badge>
                    </div>
                    {row.content && (
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                        {row.content}
                      </p>
                    )}
                    <div className="mt-1 flex gap-3 text-xs text-muted-foreground">
                      <span>{row.source ?? '—'}</span>
                      <span>{row.notify_date}</span>
                    </div>
                  </div>
                </div>
              </div>
            ))
          )}
        </CardContent>
        {totalPages > 1 && (
          <CardFooter>
            <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />
          </CardFooter>
        )}
      </Card>
    </div>
  )
}