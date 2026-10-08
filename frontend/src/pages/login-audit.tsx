import { useEffect, useState } from 'react'
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  Loader2,
  RefreshCw,
  Shield,
  ShieldAlert,
  ShieldCheck,
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
import { DatePicker } from '@/components/ui/date-picker'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { LineChartCard } from '@/components/health/charts'
import { useRealtime } from '@/hooks/use-realtime'
import { api, type PageResult } from '@/lib/api'

type LoginAudit = {
  id: number
  account: string
  user_id: number | null
  result: 'success' | 'fail' | 'locked'
  failure_reason: string | null
  ip_address: string | null
  user_agent: string | null
  lock_triggered: boolean
  created_at: string
}

type LoginAuditStats = {
  total: number
  today: number
  by_result: { result: string; count: number }[]
  by_ip: { ip: string; count: number }[]
  trend: { log_date: string; count: number }[]
  brute_force_ips: {
    ip: string
    fail_count: number
    account_count: number
    last_attempt: string | null
  }[]
  brute_force_window_minutes: number
  brute_force_threshold: number
}

const RESULT_META: Record<string, { name: string; className: string; icon: LucideIcon }> = {
  success: { name: '登录成功', className: 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300', icon: CheckCircle2 },
  fail: { name: '登录失败', className: 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300', icon: ShieldAlert },
  locked: { name: '触发锁定', className: 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300', icon: Ban },
}

const FAILURE_REASONS: Record<string, string> = {
  account_not_found: '账号不存在',
  password_wrong: '密码错误',
  account_locked: '账号锁定',
}

function formatTime(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
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

export function LoginAuditPage() {
  const realtimeTick = useRealtime(30_000)
  const [items, setItems] = useState<LoginAudit[]>([])
  const [stats, setStats] = useState<LoginAuditStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [result, setResult] = useState('all')
  const [account, setAccount] = useState('')
  const [ip, setIp] = useState('')
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
      if (result !== 'all') qs.set('result', result)
      if (account.trim()) qs.set('account', account.trim())
      if (ip.trim()) qs.set('ip', ip.trim())
      if (start) qs.set('start', start)
      if (end) qs.set('end', end)
      const res = await api.query<PageResult<LoginAudit>>(`/login-audits?${qs}`)
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    api.query<LoginAuditStats>('/login-audits/stats?days=30').then(setStats).catch(() => setStats(null))
  }, [realtimeTick])

  useEffect(() => {
    loadList()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, result, start, end, realtimeTick])

  const byResult = stats?.by_result ?? []
  const byIp = stats?.by_ip ?? []
  const trend = stats?.trend ?? []
  const bruteIps = stats?.brute_force_ips ?? []
  const todayCount = stats?.today ?? 0
  const failToday = byResult.find((r) => r.result === 'fail')?.count ?? 0
  const lockedToday = byResult.find((r) => r.result === 'locked')?.count ?? 0

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">安全审计</h1>
          <p className="text-sm text-muted-foreground">
            记录所有登录尝试的账号、IP、时间与结果，自动检测暴力破解行为。
          </p>
        </div>
        <Button variant="outline" onClick={loadList}>
          <RefreshCw /> 刷新
        </Button>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={ShieldCheck} label="今日登录" value={String(todayCount)} className="text-blue-500" />
        <StatCard icon={ShieldAlert} label="今日失败" value={String(failToday)} className="text-amber-500" />
        <StatCard icon={Ban} label="今日锁定" value={String(lockedToday)} className="text-red-500" />
        <StatCard
          icon={AlertTriangle}
          label="暴力破解嫌疑 IP"
          value={String(bruteIps.length)}
          hint={stats ? `窗口 ${stats.brute_force_window_minutes} 分钟 / 阈值 ${stats.brute_force_threshold} 次` : undefined}
          className="text-red-500"
        />
      </section>

      {bruteIps.length > 0 && (
        <Card className="border-red-200 dark:border-red-500/30">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
              <AlertTriangle className="size-4" /> 暴力破解告警
            </CardTitle>

            <CardDescription>以下 IP 在近 {stats?.brute_force_window_minutes} 分钟内登录失败次数超过阈值，请及时核查</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {bruteIps.map((b) => (
              <div key={b.ip} className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-md border px-3 py-2 text-sm">
                <Badge variant="outline" className="font-mono">IP: {b.ip}</Badge>
                <span className="text-red-600 dark:text-red-400">失败 {b.fail_count} 次</span>
                <span className="text-muted-foreground">尝试账号 {b.account_count} 个</span>
                {b.last_attempt && (
                  <span className="ml-auto text-xs text-muted-foreground">最近: {formatTime(b.last_attempt)}</span>
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {byResult.length > 0 && (
        <section className="grid gap-4 sm:grid-cols-3">
          {byResult.map((r) => {
            const meta = RESULT_META[r.result] ?? { name: r.result, className: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400', icon: Shield }
            const Icon = meta.icon
            return (
              <Card key={r.result}>
                <CardContent className="flex items-center gap-3 p-6">
                  <span className={`flex size-9 shrink-0 items-center justify-center rounded-full ${meta.className}`}>
                    <Icon className="size-4" />
                  </span>
                  <div className="min-w-0">
                    <div className="text-xl font-semibold leading-tight">{r.count}</div>
                    <div className="truncate text-xs text-muted-foreground">{meta.name}</div>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </section>
      )}

      {byIp.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">来源 IP 分布（Top10）</CardTitle>
            <CardDescription>近 30 天登录尝试最频繁的来源 IP</CardDescription>
          </CardHeader>
          <CardContent className="grid gap-2 sm:grid-cols-2">
            {byIp.map((b) => (
              <div key={b.ip} className="flex items-center gap-2 text-sm">
                <Badge variant="outline" className="font-mono">{b.ip}</Badge>
                <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
                  <div
                    className="h-full rounded-full bg-blue-500"
                    style={{ width: `${Math.min(100, (b.count / (byIp[0]?.count || 1)) * 100)}%` }}
                  />
                </div>
                <span className="w-12 text-right text-xs text-muted-foreground">{b.count}</span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {trend.length > 0 && (
        <LineChartCard
          title="近30天登录尝试趋势"
          data={trend}
          xKey="log_date"
          series={[{ key: 'count', name: '尝试数', color: '#0ea5e9' }]}
        />
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">筛选条件</CardTitle>
          <CardDescription>按结果、账号、IP 与日期范围过滤审计记录</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          <div className="space-y-2">
            <Label>结果</Label>
            <Select value={result} onValueChange={(v) => { setResult(v); setPage(1) }}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部</SelectItem>
                <SelectItem value="success">登录成功</SelectItem>
                <SelectItem value="fail">登录失败</SelectItem>
                <SelectItem value="locked">触发锁定</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>账号</Label>
            <Input
              value={account}
              onChange={(e) => setAccount(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { setPage(1); loadList() } }}
              placeholder="账号关键词"
            />
          </div>
          <div className="space-y-2">
            <Label>IP</Label>
            <Input
              value={ip}
              onChange={(e) => setIp(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { setPage(1); loadList() } }}
              placeholder="精确 IP"
            />
          </div>
          <div className="space-y-2">
            <Label>开始日期</Label>
            <DatePicker value={start} onChange={(v) => { setStart(v); setPage(1) }} />
          </div>
          <div className="space-y-2">
            <Label>结束日期</Label>
            <DatePicker value={end} onChange={(v) => { setEnd(v); setPage(1) }} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">登录记录</CardTitle>
          <CardDescription>共 {items.length} 条，按时间倒序排列</CardDescription>
        </CardHeader>
        <CardContent className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
          {items.length === 0 ? (
            loading ? (
              <div className="flex justify-center py-12 text-muted-foreground">
                <Loader2 className="size-5 animate-spin" />
              </div>
            ) : (
              <p className="py-12 text-center text-sm text-muted-foreground">
                暂无登录审计记录，登录尝试发生后将自动记录于此。
              </p>
            )
          ) : (
            <ol className="space-y-3">
              {items.map((row) => {
                const meta = RESULT_META[row.result] ?? { name: row.result, className: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400', icon: Shield }
                const Icon = meta.icon
                return (
                  <li key={row.id} className="rounded-lg border px-4 py-3">
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span className={`flex size-6 shrink-0 items-center justify-center rounded-full ${meta.className}`}>
                        <Icon className="size-3.5" />
                      </span>
                      <span className="text-sm font-medium">{meta.name}</span>
                      <Badge variant="outline" className="font-mono">{row.account}</Badge>
                      {row.failure_reason && (
                        <span className="text-xs text-muted-foreground">
                          {FAILURE_REASONS[row.failure_reason] ?? row.failure_reason}
                        </span>
                      )}
                      {row.lock_triggered && (
                        <Badge variant="outline" className="text-xs font-normal text-red-600 dark:text-red-400">
                          触发锁定
                        </Badge>
                      )}
                      <span className="ml-auto text-xs text-muted-foreground whitespace-nowrap">
                        {formatTime(row.created_at)}
                      </span>
                      {row.ip_address && (
                        <Badge variant="outline" className="text-xs font-normal font-mono">
                          IP: {row.ip_address}
                        </Badge>
                      )}
                      {row.user_agent && (
                        <span className="text-xs text-muted-foreground" title={row.user_agent}>
                          UA: {row.user_agent}
                        </span>
                      )}
                    </div>
                  </li>
                )
              })}
            </ol>
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
