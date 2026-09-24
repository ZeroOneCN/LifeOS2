import { useEffect, useState } from 'react'
import { Bell, CheckCircle2, Loader2 } from 'lucide-react'

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
import { useRealtime } from '@/hooks/use-realtime'
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
  today: number
  by_category: { category: string; count: number }[]
  trend: { notify_date: string; count: number }[]
}

const categoryStyle: Record<string, string> = {
  系统: 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300',
  健康: 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300',
  财务: 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300',
  生活: 'bg-purple-100 text-purple-700 dark:bg-purple-500/15 dark:text-purple-300',
  投资: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-500/15 dark:text-cyan-300',
  其他: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400',
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
  const realtimeTick = useRealtime(30_000)
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
  }, [page, realtimeTick]) // eslint-disable-line react-hooks/exhaustive-deps

  const byCategory = stats?.by_category ?? []
  const trend = stats?.trend ?? []
  const categoryTotal = byCategory.reduce((sum, c) => sum + c.count, 0)

  // 近7日提醒（按自然日补齐，趋势数据为近30天按日的计数）
  const trendMap = new Map(trend.map((t) => [t.notify_date, t.count]))
  const today = new Date()
  const recentDays = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - (6 - i))
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    return { key, label: key.slice(5), count: trendMap.get(key) ?? 0, isToday: i === 6 }
  })

  return (
    <div className="flex flex-col gap-4">
      <section className="grid gap-4 sm:grid-cols-2">
        <StatCard icon={Bell} label="今日提醒" value={String(stats?.today ?? '—')} className="text-amber-500" />
        <StatCard icon={CheckCircle2} label="提醒总数" value={String(stats?.total ?? '—')} className="text-green-500" />
      </section>

      {byCategory.length > 0 || trend.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">提醒类型分布</CardTitle>
              <CardDescription>近30天各类型提醒数量与占比</CardDescription>
            </CardHeader>
            <CardContent>
              {byCategory.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">暂无数据</p>
              ) : (
                <ul className="space-y-2">
                  {byCategory.map((c) => {
                    const pct = categoryTotal > 0 ? Math.round((c.count / categoryTotal) * 100) : 0
                    return (
                      <li key={c.category}>
                        <div className="flex items-center justify-between text-sm">
                          <span className="text-muted-foreground">{c.category}</span>
                          <span className="font-medium">{c.count} 条 · {pct}%</span>
                        </div>
                        <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-muted">
                          <div className="h-full rounded-full bg-indigo-500" style={{ width: `${pct}%` }} />
                        </div>
                      </li>
                    )
                  })}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">近7日提醒</CardTitle>
              <CardDescription>最近一周每日提醒数量</CardDescription>
            </CardHeader>
            <CardContent>
              <ul className="grid grid-cols-2 gap-2">
                {recentDays.map((d) => (
                  <li
                    key={d.key}
                    className="flex items-center justify-between rounded-lg border px-3 py-2"
                  >
                    <span className="truncate text-sm text-muted-foreground">
                      {d.label}{d.isToday ? '（今天）' : ''}
                    </span>
                    <span className="shrink-0 text-sm font-medium">{d.count} 条</span>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
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