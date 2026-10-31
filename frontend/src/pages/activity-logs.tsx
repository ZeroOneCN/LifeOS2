import { useEffect, useState } from 'react'
import {
  Activity,
  Eraser,
  History,
  Loader2,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
  type LucideIcon,
} from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardHeaderActions,
  CardTitle,
} from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { DatePicker } from '@/components/ui/date-picker'
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
import { Tip } from '@/components/ui/tip'
import { useRealtime } from '@/hooks/use-realtime'
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
  user_agent: string | null
  created_at: string
}

type ActivityStats = {
  total: number
  today: number
  by_action: { action: string; count: number }[]
  by_module: { module: string; name?: string; count: number }[]
  trend: { log_date: string; count: number }[]
}

const MODULE_NAMES: Record<string, string> = {
  'health/vitals-sleep': '睡眠体征',
  'health/fitness': '健身运动',
  'health/diet': '饮食记录',
  'health/body': '体重记录',
  'health/steps': '步数统计',
  'health/checkup': '体检指标',
  'health/checkup/templates': '体检模板',
  'health/checkup/panels': '体检组合',
  'health/reports': '健康报告',
  'health/overview': '健康概览',
  'health/dashboard': '健康看板',
  'health/medication': '用药跟踪',
  'health/medication/purchases': '购药记录',
  'health/medication/stocks': '药品库存',
  'finance/shopping/records': '购物记录',
  'finance/shopping/categories': '购物分类',
  'finance/shopping/ledgers': '购物账本',
  'finance/shopping/platforms': '购物平台',
  'finance/shopping/import': '购物导入',
  'finance/travel/details': '行程明细',
  'finance/travel/ledgers': '行程账本',
  'finance/travel/payment-channels': '行程支付渠道',
  'finance/travel/reports': '旅行报告',
  'finance/travel/report': '旅行报告',
  'finance/travel/report/generate': '旅行报告',
  'finance/rent-channels': '租赁渠道',
  'finance/rent-terms': '租约条款',
  'finance/housing': '住房记录',
  'finance/utilities': '水电账单',
  'finance/subscriptions': '服务订阅',
  'finance/subscription-categories': '订阅分类',
  'finance/loan-platforms': '借款平台',
  'finance/loan-bills': '网贷账单',
  'finance/repayments': '还款记录',
  'finance/investments': '投资记账',
  'finance/memos': '备忘录',
  'finance/currencies': '汇率设置',
  'finance/planning': '财务规划',
  'finance/debts': '债务管理',
  'finance/reports': '财务报告',
  'finance/reports/generate': '财务报告',
  'finance/overview': '财务概览',
  'lifestyle/items': '物品追踪',
  'lifestyle/phone-cards': '手机卡管理',
  'lifestyle/bank-cards': '银行卡管理',
  'lifestyle/carriers': '运营商管理',
  'lifestyle/card-bills': '卡片账单',
  'lifestyle/sim-cards': '卡片管理',
  'lifestyle/todos': '待办清单',
  'lifestyle/schedule': '日程管理',
  'lifestyle/reports': '生活报告',
  'lifestyle/overview': '生活概览',
  'investment/forex': '外汇交易',
  'investment/funds': '基金投资',
  'investment/overview': '投资概览',
  'investment/reports': '投资报告',
  notifications: '通知中心',
  motivation: '激励语录',
  'user/profile': '个人资料',
  'user/settings': '账号设置',
  'auth/login': '登录系统',
  'auth/register': '注册账号',
  'auth/logout': '退出登录',
  'auth/refresh': '刷新令牌',
  'auth/sessions': '会话管理',
  'auth/login-audits': '登录审计',
  'backup/export': '数据导出',
  'backup/import': '数据导入',
  'backup/exports': '备份文件',
  'backup/schedules': '定时备份',
  'backup/schedules/toggle': '定时备份',
  'notifications/scan': '提醒扫描',
  'notifications/read-all': '全部已读',
  'notifications/channels': '通知渠道',
  'notifications/settings': '提醒设置',
  'notifications/templates': '通知模板',
  'notifications/send-logs': '发送记录',
  'notifications/test': '测试通知',
  'site-config': '系统设置',
  'site-config/reset': '系统设置',
}

/** 顶级路径兜底中文名：用于未显式登记的深层子路径 */
const MODULE_PREFIX_NAMES: Record<string, string> = {
  health: '健康管理',
  finance: '财务管理',
  lifestyle: '生活管理',
  investment: '投资管理',
  notifications: '通知中心',
  auth: '账号安全',
  backup: '数据备份',
  user: '用户中心',
  'site-config': '系统设置',
  motivation: '激励语录',
}

/**
 * 将模块路径转换为中文名：优先精确匹配，其次最长前缀，最后按顶级路径兜底。
 * 与后端 module_display_name 保持一致，确保筛选与列表展示的中文口径统一。
 */
function moduleLabel(module: string): string {
  if (!module) return '未知模块'
  if (MODULE_NAMES[module]) return MODULE_NAMES[module]
  const parts = module.split('/')
  for (let i = parts.length - 1; i > 0; i -= 1) {
    const key = parts.slice(0, i).join('/')
    if (MODULE_NAMES[key]) return MODULE_NAMES[key]
  }
  return MODULE_PREFIX_NAMES[parts[0]] ?? module
}

const ACTION_META: Record<string, { name: string; className: string; icon: LucideIcon }> = {
  create: { name: '新增', className: 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300', icon: Plus },
  update: { name: '更新', className: 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300', icon: Pencil },
  patch: { name: '部分更新', className: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-500/15 dark:text-yellow-300', icon: Pencil },
  delete: { name: '删除', className: 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300', icon: Trash2 },
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
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground min-w-0 max-w-[55%] truncate">{label}</CardTitle>
        <CardHeaderActions>
          <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
        </CardHeaderActions>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function ActivityLogsPage() {
  const realtimeTick = useRealtime(30_000)
  const { confirm, dialog: confirmDialog } = useConfirm()
  const [items, setItems] = useState<ActivityRecord[]>([])
  const [stats, setStats] = useState<ActivityStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [statsLoading, setStatsLoading] = useState(true)
  const [clearing, setClearing] = useState(false)
  const [refreshKey, setRefreshKey] = useState(0)
  const [action, setAction] = useState('all')
  const [module, setModule] = useState('all')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const totalPages = Math.max(1, Math.ceil(total / 10))
  const refreshing = loading || statsLoading

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

  // days=0 表示统计全部历史，趋势图覆盖所有已记录操作
  useEffect(() => {
    setStatsLoading(true)
    api
      .query<ActivityStats>('/activity-logs/stats?days=0')
      .then(setStats)
      .catch(() => setStats(null))
      .finally(() => setStatsLoading(false))
  }, [realtimeTick, refreshKey])

  useEffect(() => {
    loadList()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, action, module, start, end, realtimeTick, refreshKey])

  const handleRefresh = () => setRefreshKey((k) => k + 1)

  const handleClear = async () => {
    const ok = await confirm({
      title: '清空活动日志',
      description: '将删除全部活动日志记录，删除后无法恢复。确定继续吗？',
      confirmText: '清空',
      danger: true,
    })
    if (!ok) return
    setClearing(true)
    try {
      const res = await api.del<{ deleted: number }>('/activity-logs')
      toast.success(`已清空 ${res.deleted} 条活动日志`)
      setPage(1)
      handleRefresh()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '清空失败')
    } finally {
      setClearing(false)
    }
  }

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
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" onClick={handleRefresh} disabled={refreshing}>
            <RefreshCw className={refreshing ? 'animate-spin' : ''} />
            {refreshing ? '刷新中' : '刷新'}
          </Button>
          <Button
            variant="outline"
            onClick={handleClear}
            disabled={clearing || loading}
            className="text-destructive hover:text-destructive"
          >
            {clearing ? <Loader2 className="animate-spin" /> : <Eraser />}
            {clearing ? '清空中' : '清空日志'}
          </Button>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          icon={Activity}
          label="今日操作"
          value={String(stats?.today ?? '—')}
          className="text-amber-500"
        />
        <StatCard
          icon={History}
          label="历史总操作"
          value={String(stats?.total ?? '—')}
          className="text-blue-500"
        />
        <StatCard
          icon={History}
          label="操作模块数"
          value={String(byModule.length)}
          className="text-green-500"
        />
        <Card>
          <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
            <CardTitle className="min-w-0 max-w-[55%] truncate text-sm font-medium text-muted-foreground">
              操作类型分布
            </CardTitle>
            <CardHeaderActions>
              <Pencil className="size-4 text-violet-500" />
            </CardHeaderActions>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-x-4 gap-y-1">
            {(byAction.length > 0 ? byAction : []).map((a) => {
              const meta = ACTION_META[a.action]
              return (
                <span key={a.action} className="flex items-baseline gap-1">
                  <span className="text-lg font-semibold leading-none">{a.count}</span>
                  <span className="text-xs text-muted-foreground">{meta?.name ?? a.action}</span>
                </span>
              )
            })}
            {byAction.length === 0 && (
              <span className="text-2xl font-semibold">—</span>
            )}
          </CardContent>
        </Card>
      </section>

      {trend.length > 0 && (
        <LineChartCard
          title="历史操作趋势"
          data={trend}
          xKey="log_date"
          series={[{ key: 'count', name: '操作数', color: '#0ea5e9' }]}
        />
      )}

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
              <SelectContent position="popper" sideOffset={4} className="z-[60]">
                <SelectItem value="all">全部</SelectItem>
                <SelectItem value="create">新增</SelectItem>
                <SelectItem value="update">更新</SelectItem>
                <SelectItem value="patch">部分更新</SelectItem>
                <SelectItem value="delete">删除</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>模块</Label>
            <Select value={module} onValueChange={(v) => { setModule(v); setPage(1) }}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent position="popper" sideOffset={4} className="z-[60] max-h-80">
                <SelectItem value="all">全部模块</SelectItem>
                {byModule.map((m) => (
                  <SelectItem key={m.module} value={m.module}>
                    {m.name ?? moduleLabel(m.module)}（{m.count}）
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
          <CardTitle className="text-sm font-medium">操作记录</CardTitle>
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
                暂无活动日志，在各模块执行新增/编辑/删除操作后将自动记录。
              </p>
            )
          ) : (
            <ol className="space-y-3">
              {items.map((row) => {
                const meta = ACTION_META[row.action] ?? {
                  name: row.action,
                  className: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400',
                  icon: Activity,
                }
                const Icon = meta.icon
                return (
                  <li key={row.id} className="rounded-lg border px-4 py-3">
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <span
                        className={`flex size-6 shrink-0 items-center justify-center rounded-full ${meta.className}`}
                      >
                        <Icon className="size-3.5" />
                      </span>
                      <span className="text-sm font-medium">{row.summary ?? '未知操作'}</span>
                      <Badge variant="outline">{moduleLabel(row.module)}</Badge>
                      {row.resource_id != null && (
                        <span className="text-xs text-muted-foreground">
                          ID: {row.resource_id}
                        </span>
                      )}
                      <span className="ml-auto text-xs text-muted-foreground whitespace-nowrap">
                        {formatTime(row.created_at)}
                      </span>
                      {row.ip && (
                        <Badge variant="outline" className="text-xs font-normal">
                          IP: {row.ip}
                        </Badge>
                      )}
                      {row.user_agent && (
                        <Tip label={row.user_agent}>
                          <span className="text-xs text-muted-foreground">
                            UA: {row.user_agent}
                          </span>
                        </Tip>
                      )}
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
          <CardFooter>
            <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />
          </CardFooter>
        )}
      </Card>
      {confirmDialog}
    </div>
  )
}
