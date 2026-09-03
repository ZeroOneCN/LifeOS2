import { useEffect, useState } from 'react'
import {
  Activity,
  History,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
  type LucideIcon,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api, type PageResult } from '@/lib/api'

type ActivityRecord = {
  id: number
  action: string
  module: string
  resource_type: string
  resource_id: number | null
  summary: string | null
  detail: string | null
  ip: string | null
  created_at: string
}

type ActivityStats = {
  total: number
  today: number
  by_action: { action: string; count: number }[]
  by_module: { module: string; count: number }[]
  trend: { log_date: string; count: number }[]
}

const MODULE_NAMES: Record<string, string> = {
  'health/vitals-sleep': '睡眠体征',
  'health/fitness': '健身运动',
  'health/steps': '步数统计',
  'health/checkup': '体检指标',
  'health/reports': '健康报告',
  'health/medication': '用药跟踪',
  'finance/purchases': '购买记录',
  'finance/travel': '旅行开支',
  'finance/bills': '账单管理',
  'finance/reminders': '账单提醒',
  'finance/planning': '财务规划',
  'lifestyle/items': '物品追踪',
  'lifestyle/sim-cards': '卡片管理',
  'lifestyle/todos': '待办清单',
  'lifestyle/schedule': '日程管理',
  'investment/forex': '外汇交易',
  notifications: '通知中心',
}

const ACTION_META: Record<string, { name: string; className: string; icon: LucideIcon }> = {
  create: { name: '新增', className: 'bg-green-100 text-green-700', icon: Plus },
  update: { name: '更新', className: 'bg-blue-100 text-blue-700', icon: Pencil },
  delete: { name: '删除', className: 'bg-red-100 text-red-700', icon: Trash2 },
}

function formatTime(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(
    d.getMinutes(),
  )}`
}

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  className,
}: {
  icon: LucideIcon
  label: string
  value: string
  hint?: string
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
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function ActivityLogsPage() {
  const [items, setItems] = useState<ActivityRecord[]>([])
  const [stats, setStats] = useState<ActivityStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [action, setAction] = useState('all')
  const [module, setModule] = useState('all')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const totalPages = Math.max(1, Math.ceil(total / 10))

  const loadList = async () => {
    setLoading(true)
    try {
      const qs = new URLSearchParams()
      qs.set('page', String(page))
      qs.set('page_size', '10')
      if (action !== 'all') qs.set('action', action)
      if (module !== 'all') qs.set('module', module)
      if (start) qs.set('start', start)
      if (end) qs.set('end', end)
      const res = await api.query<PageResult<ActivityRecord>>(`/activity-logs?${qs}`)
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    api.query<ActivityStats>('/activity-logs/stats?days=30').then(setStats).catch(() => setStats(null))
  }, [])

  useEffect(() => {
    loadList()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, action, module, start, end])

  const byAction = stats?.by_action ?? []
  const byModule = stats?.by_module ?? []
  const trend = stats?.trend ?? []

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">活动日志</h1>
          <p className="text-sm text-muted-foreground">
            自动记录各模块的新增、编辑与删除操作。
          </p>
        </div>
        <Button variant="outline" onClick={loadList}>
          <RefreshCw /> 刷新
        </Button>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        <StatCard
          icon={Activity}
          label="今日操作"
          value={String(stats?.today ?? '—')}
          className="text-amber-500"
        />
        <StatCard
          icon={History}
          label="近30天操作"
          value={String(stats?.total ?? '—')}
          className="text-blue-500"
        />
        <StatCard
          icon={History}
          label="操作模块数"
          value={String(byModule.length ?? '—')}
          className="text-green-500"
        />
      </section>

      {byAction.length > 0 || trend.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="操作类型分布"
            data={byAction.map((a) => ({ action: ACTION_META[a.action]?.name ?? a.action, count: a.count }))}
            xKey="action"
            series={[{ key: 'count', name: '次数', color: '#6366f1' }]}
          />
          <LineChartCard
            title="近30天操作趋势"
            data={trend}
            xKey="log_date"
            series={[{ key: 'count', name: '操作数', color: '#0ea5e9' }]}
          />
        </div>
      ) : null}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">筛选条件</CardTitle>
          <CardDescription>按操作类型、模块与日期范围过滤日志</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-2">
            <Label>操作类型</Label>
            <Select value={action} onValueChange={(v) => { setAction(v); setPage(1) }}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部</SelectItem>
                <SelectItem value="create">新增</SelectItem>
                <SelectItem value="update">更新</SelectItem>
                <SelectItem value="delete">删除</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>模块</Label>
            <Select value={module} onValueChange={(v) => { setModule(v); setPage(1) }}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部</SelectItem>
                {byModule.map((m) => (
                  <SelectItem key={m.module} value={m.module}>
                    {MODULE_NAMES[m.module] ?? m.module}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>开始日期</Label>
            <Input type="date" value={start} onChange={(e) => { setStart(e.target.value); setPage(1) }} />
          </div>
          <div className="space-y-2">
            <Label>结束日期</Label>
            <Input type="date" value={end} onChange={(e) => { setEnd(e.target.value); setPage(1) }} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">操作记录</CardTitle>
          <CardDescription>共 {items.length} 条，按时间倒序排列</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="flex justify-center py-12 text-muted-foreground">
              <Loader2 className="size-5 animate-spin" />
            </div>
          ) : items.length === 0 ? (
            <p className="py-12 text-center text-sm text-muted-foreground">
              暂无活动日志，在各模块执行新增/编辑/删除操作后将自动记录。
            </p>
          ) : (
            <ol className="space-y-3">
              {items.map((row) => {
                const meta = ACTION_META[row.action] ?? {
                  name: row.action,
                  className: 'bg-gray-100 text-gray-600',
                  icon: Activity,
                }
                const Icon = meta.icon
                return (
                  <li key={row.id} className="rounded-lg border px-4 py-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <span
                        className={`flex size-6 shrink-0 items-center justify-center rounded-full ${meta.className}`}
                      >
                        <Icon className="size-3.5" />
                      </span>
                      <span className="text-sm font-medium">{row.summary ?? '未知操作'}</span>
                      <Badge variant="outline">{MODULE_NAMES[row.module] ?? row.module}</Badge>
                      {row.resource_id != null && (
                        <span className="text-xs text-muted-foreground">
                          ID: {row.resource_id}
                        </span>
                      )}
                      <span className="ml-auto text-xs text-muted-foreground">
                        {formatTime(row.created_at)}
                      </span>
                    </div>
                    {row.detail && (
                      <pre className="mt-2 max-h-24 overflow-y-auto whitespace-pre-wrap break-all rounded-md bg-muted/50 px-3 py-2 text-xs text-muted-foreground">
                        {row.detail}
                      </pre>
                    )}
                  </li>
                )
              })}
            </ol>
          )}
        </CardContent>
        {totalPages > 1 && (
          <CardFooter className="flex items-center justify-end gap-2">
            <Button
              variant="outline"
              size="sm"
              disabled={page <= 1}
              onClick={() => setPage(page - 1)}
            >
              上一页
            </Button>
            <span className="text-sm text-muted-foreground">
              {page} / {totalPages}
            </span>
            <Button
              variant="outline"
              size="sm"
              disabled={page >= totalPages}
              onClick={() => setPage(page + 1)}
            >
              下一页
            </Button>
          </CardFooter>
        )}
      </Card>
    </div>
  )
}
