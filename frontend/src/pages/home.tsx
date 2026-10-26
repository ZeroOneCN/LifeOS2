import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AlertTriangle,
  CaseSensitive,
  CircleDollarSign,
  Coins,
  CreditCard,
  Flame,
  Footprints,
  HandCoins,
  HeartPulse,
  Package,
  Receipt,
  Scale,
  Timer,
  TrendingUp,
  Utensils,
  Wallet,
  type LucideIcon,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Tip } from '@/components/ui/tip'
import { navigation } from '@/config/navigation'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'

const centers = navigation.filter((s) => !s.system)

/** 金额格式化：保留两位小数并加货币符号 */
const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
/** 带正负号的数值格式化，用于收益类指标 */
const signFmt = (n: number) =>
  `${n >= 0 ? '+' : ''}${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
/** 大数字格式化：最多保留一位小数 */
const num = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 1 })

/* ------------------------------ 数据接口类型 ------------------------------ */

type FinOverview = {
  month_expense: number
  outstanding_loans: number
  outstanding_debt: number
  invest_pnl: number
  lend_total: number
  borrow_total: number
  categories: { label: string; amount: number }[]
  week_trend: { date: string; amount: number }[]
  pending_bills: { id: number; bill_type: string; amount: number; remaining?: number; due_date?: string }[]
  pending_utils: { id: number; bill_type: string; amount: number; due_date?: string }[]
  upcoming_subs: { id: number; title: string; category: string; amount?: number; due_date?: string }[]
}

type HealthDash = {
  series: { record_date: string; intake: number; expenditure: number; balance: number }[]
  step_total: number
  exercise_count: number
  intake_total: number
  expenditure_total: number
  latest_body: { height_cm?: number; weight_kg?: number; bmi?: number; body_fat_percent?: number } | null
}

type LifeOverview = {
  todo_pending: number
  todo_overdue: number
  item_expiring: number
  item_expired: number
  item_value: number
  month_deduct: number
  phone_total: number
  bank_total: number
  pending_todos: { id: number; title: string; category: string; due_date?: string; priority?: string }[]
  expiring_items: { id: number; item_name: string; category: string; expire_date?: string; days_left: number }[]
  latest_report: { id: number; title: string; period_label?: string; summary?: string } | null
}

type InvOverview = {
  summary: {
    account_value: number
    net_profit: number
    win_rate?: number
    trade_count: number
    open_count: number
  }
}

type Profile = { nickname?: string; username?: string; account?: string }

type Compliment = { content: string; sequence_no?: number; hour?: number; updated_at?: string }

const RAINBOW_REFRESH_MS = 60 * 60 * 1000 // 每小时刷新一句彩虹屁

/* ------------------------------ 紧急度分级 ------------------------------ */

/** 信息流条目的紧急度分级：逾期/临近/普通，驱动配色与排序 */
type Tone = 'danger' | 'warning' | 'neutral'

/** 分级权重：数值越小越靠前，用于按紧急度排序 */
const TONE_TIER: Record<Tone, number> = { danger: 0, warning: 1, neutral: 2 }

/** 统一信息流条目：由各中心「待处理」数据汇聚而成 */
type FlowItem = {
  key: string
  title: string
  meta: string
  to: string
  tone: Tone
  /** 排序键 = 分级权重 × 100000 + 剩余天数，升序排列即紧急度降序 */
  rank: number
  amount?: number
  badge?: string
}

/**
 * 计算目标日期距今天的天数。
 * @param dateStr 目标日期字符串（YYYY-MM-DD），缺省或非法时返回 Infinity
 * @returns 距今天的天数（负数为已过期，当天为 0，无期限为 Infinity）
 */
function daysUntil(dateStr?: string): number {
  if (!dateStr) return Number.POSITIVE_INFINITY
  const target = new Date(`${dateStr}T00:00:00`).getTime()
  if (Number.isNaN(target)) return Number.POSITIVE_INFINITY
  const now = new Date()
  const base = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  return Math.round((target - base) / 86_400_000)
}

/**
 * 将剩余天数映射为紧急度分级。
 * @param days 距到期天数
 * @param warnWithin 进入「临近」警示的天数阈值（默认 3 天）
 * @returns 紧急度分级
 */
function toneOf(days: number, warnWithin = 3): Tone {
  if (!Number.isFinite(days)) return 'neutral'
  if (days < 0) return 'danger'
  return days <= warnWithin ? 'warning' : 'neutral'
}

/** 将无期限（Infinity）归一为一个足够大的排序值，避免参与排序时破坏数值计算 */
const safeDays = (days: number) => (Number.isFinite(days) ? days : 99_999)

/**
 * 将各中心首页返回的「待处理」数据汇聚为一条统一信息流。
 * 覆盖：待缴账单、水电账单、账单提醒、订阅到期、待办事项、临期物品。
 * 每条记录按紧急度（逾期 → 临近 → 普通）排序，紧急度相同时按到期日升序。
 * @param fin 财务总览数据
 * @param life 生活总览数据
 * @returns 已按紧急度排序的信息流条目数组
 */
function buildFlowItems(fin: FinOverview | null, life: LifeOverview | null): FlowItem[] {
  const items: FlowItem[] = []

  /**
   * 向信息流追加一条记录。
   * @param key 唯一键
   * @param title 主标题
   * @param meta 副标题（来源分类与到期信息）
   * @param to 点击跳转路径
   * @param days 距到期天数
   * @param extra 可选：金额、角标文案、紧急度覆盖
   */
  const push = (
    key: string,
    title: string,
    meta: string,
    to: string,
    days: number,
    extra?: { amount?: number; badge?: string; tone?: Tone },
  ) => {
    const tone = extra?.tone ?? toneOf(days)
    items.push({
      key,
      title,
      meta,
      to,
      tone,
      rank: TONE_TIER[tone] * 100_000 + safeDays(days),
      amount: extra?.amount,
      badge: extra?.badge,
    })
  }

  fin?.pending_bills.forEach((b) =>
    push(`bill-${b.id}`, b.bill_type, `待缴账单 · 到期 ${b.due_date ?? '—'}`, '/finance/overview', daysUntil(b.due_date), {
      amount: b.remaining ?? b.amount,
    }),
  )
  fin?.pending_utils.forEach((u) =>
    push(`util-${u.id}`, u.bill_type, `水电账单 · 到期 ${u.due_date ?? '—'}`, '/finance/overview', daysUntil(u.due_date), {
      amount: u.amount,
    }),
  )
  fin?.upcoming_subs.forEach((s) =>
    push(`sub-${s.id}`, s.title, `${s.category} · 到期 ${s.due_date ?? '—'}`, '/finance/overview', daysUntil(s.due_date), {
      amount: s.amount,
    }),
  )
  life?.pending_todos.forEach((t) => {
    const days = daysUntil(t.due_date)
    const overdue = Number.isFinite(days) && days < 0
    push(`todo-${t.id}`, t.title, `${t.category} · ${t.due_date ?? '无期限'}`, '/lifestyle/todos', days, {
      badge: t.priority === 'high' ? '高' : t.priority === 'medium' ? '中' : t.priority === 'low' ? '低' : undefined,
      // 高优先级待办即使无期限也按「临近」呈现，逾期则升级为「紧急」
      tone: overdue ? 'danger' : !Number.isFinite(days) && t.priority === 'high' ? 'warning' : toneOf(days),
    })
  })
  life?.expiring_items.forEach((i) =>
    push(`item-${i.id}`, i.item_name, `${i.category} · 距到期 ${i.days_left} 天`, '/lifestyle/items', i.days_left, {
      badge: i.days_left <= 0 ? '已过期' : `剩 ${i.days_left} 天`,
      tone: i.days_left <= 0 ? 'danger' : i.days_left <= 7 ? 'warning' : 'neutral',
    }),
  )

  return items.sort((a, b) => a.rank - b.rank)
}

/** 紧急度 → 角标配色（含深色模式变体） */
function toneBadgeClass(tone: Tone): string {
  return tone === 'danger'
    ? 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300'
    : tone === 'warning'
      ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300'
      : 'bg-muted text-muted-foreground'
}

/** 紧急度 → 金额文字配色（含深色模式变体） */
function toneTextClass(tone: Tone): string {
  return tone === 'danger'
    ? 'text-red-600 dark:text-red-400'
    : tone === 'warning'
      ? 'text-amber-600 dark:text-amber-400'
      : 'text-foreground'
}

/* ------------------------------ 小组件 ------------------------------ */

/**
 * 单个关键指标卡片。
 * @param icon 图标组件
 * @param label 指标名称
 * @param value 指标值（已格式化字符串）
 * @param hint 指标说明
 * @param money 是否按「金额」着色（绿色）
 * @param pnl 是否按「盈亏」着色（正绿负红）
 */
function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  money = false,
  pnl = false,
}: {
  icon: LucideIcon
  label: string
  value: string
  hint?: string
  money?: boolean
  pnl?: boolean
}) {
  const numeric = Number(value.replace(/[.-]/g, '').replace(/,/g, ''))
  const color = pnl ? (numeric >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400') : money ? 'text-emerald-600 dark:text-emerald-400' : ''
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent className="pb-4">
        <div className={`text-2xl font-semibold ${color}`}>{value}</div>
        {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

/**
 * 指标分组：小标题 + 单行卡片网格。按业务中心分组，避免不同域指标混排成孤行。
 * @param icon 分组图标
 * @param title 分组标题
 * @param cols 网格列数类名
 * @param children 组内指标卡片
 */
function StatGroup({
  icon: Icon,
  title,
  cols,
  children,
}: {
  icon: LucideIcon
  title: string
  cols: string
  children: React.ReactNode
}) {
  return (
    <section>
      <div className="mb-3 flex items-center gap-2">
        <Icon className="size-4 text-muted-foreground" />
        <h2 className="text-sm font-semibold text-muted-foreground">{title}</h2>
      </div>
      <div className={cols}>{children}</div>
    </section>
  )
}

/**
 * 统一待处理信息流卡片：把各中心「待处理」条目按紧急度自上而下排列，
 * 超过高度上限时在卡片内部滚动，保持信息流长度可控。
 * @param items 已按紧急度排序的信息流条目
 */
function PendingFlowCard({ items }: { items: FlowItem[] }) {
  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-sm">
          <span className="flex items-center gap-2">
            <AlertTriangle className="size-4 text-amber-500" />
            待处理
          </span>
          <Badge className={items.length ? toneBadgeClass(items[0].tone) : 'bg-muted text-muted-foreground'}>
            {items.length} 项
          </Badge>
        </CardTitle>
      </CardHeader>
      <CardContent className="max-h-96 space-y-2 overflow-y-auto">
        {items.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">暂无待处理事项</p>
        ) : (
          items.map((it) => (
            <Link
              key={it.key}
              to={it.to}
              className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2 transition-colors hover:bg-muted/60"
            >
              <div className="min-w-0">
                <Tip label={it.title}>
                  <div className="truncate text-sm font-medium">{it.title}</div>
                </Tip>
                <Tip label={it.meta}>
                  <div className="truncate text-xs text-muted-foreground">{it.meta}</div>
                </Tip>
              </div>
              {it.badge ? (
                <Badge className={`shrink-0 ${toneBadgeClass(it.tone)}`}>{it.badge}</Badge>
              ) : it.amount != null ? (
                <span className={`shrink-0 text-sm font-medium ${toneTextClass(it.tone)}`}>{fmt(it.amount)}</span>
              ) : null}
            </Link>
          ))
        )}
      </CardContent>
    </Card>
  )
}

/** 侧栏快捷入口：竖向列出全部业务中心，点击进入该中心首个页面 */
function QuickEntryRail() {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-sm">
          <HeartPulse className="size-4 text-muted-foreground" />
          功能中心快捷入口
        </CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {centers.map((center) => (
          <Link
            key={center.title}
            to={center.children[0].url}
            className="flex items-center gap-3 rounded-lg border px-3 py-2.5 transition-colors hover:bg-muted/60"
          >
            <center.icon className="size-4 shrink-0 text-primary" />
            <div className="min-w-0">
              <div className="text-sm font-medium">{center.title}</div>
              <Tip label={center.children.map((item) => item.title).join(' · ')}>
                <div className="truncate text-xs text-muted-foreground">
                  {center.children.map((item) => item.title).join(' · ')}
                </div>
              </Tip>
            </div>
          </Link>
        ))}
      </CardContent>
    </Card>
  )
}

/* ------------------------------ 页面主体 ------------------------------ */

export function HomePage() {
  const [fin, setFin] = useState<FinOverview | null>(null)
  const [health, setHealth] = useState<HealthDash | null>(null)
  const [life, setLife] = useState<LifeOverview | null>(null)
  const [inv, setInv] = useState<InvOverview | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [compliment, setCompliment] = useState<string>('')
  const [backend, setBackend] = useState(false)
  const [loading, setLoading] = useState(true)
  const realtimeTick = useRealtime(30_000)

  /** 拉取首页「彩虹屁」鼓励语（每小时刷新一次） */
  const fetchCompliment = () => {
    api
      .query<Compliment>('/motivation/rainbow')
      .then((d) => setCompliment(d.content))
      .catch(() => setCompliment(''))
  }
  useEffect(() => {
    fetchCompliment()
    const timer = setInterval(fetchCompliment, RAINBOW_REFRESH_MS)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    Promise.allSettled([
      api.query<FinOverview>('/finance/overview').then(setFin),
      api.query<HealthDash>('/health/dashboard').then(setHealth),
      api.query<LifeOverview>('/lifestyle/overview').then(setLife),
      api.query<InvOverview>('/investment/overview').then(setInv),
      api.query<Profile>('/auth/me')
        .then(setProfile)
        .catch(() => setProfile(null)),
      fetch('/api/v1/health')
        .then((r) => r.json())
        .then((d) => setBackend(d.status === 'ok'))
        .catch(() => setBackend(false)),
    ]).finally(() => setLoading(false))
  }, [realtimeTick])

  // 待处理信息流：数据变化时重新计算紧急度排序
  const flowItems = useMemo(() => buildFlowItems(fin, life), [fin, life])

  // 问候语
  const hour = new Date().getHours()
  const greeting = hour < 6 ? '夜深了' : hour < 9 ? '早上好' : hour < 12 ? '上午好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好'
  const todayStr = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(new Date())
  const displayName = profile?.nickname || profile?.username || profile?.account || '主人'

  const outstanding = (fin?.outstanding_loans ?? 0) + (fin?.outstanding_debt ?? 0)

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_19rem]">
      {/* 主信息流：问候 → 待处理流（上移）→ 关键指标（下沉） */}
      <div className="flex min-w-0 flex-col gap-6">
        {/* 问候区 */}
        <section className="rounded-xl border bg-gradient-to-r from-primary/10 via-background to-background p-6">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <h1 className="font-heading text-2xl font-semibold tracking-tight">
                {greeting}，{displayName}
              </h1>
              <p className="mt-1 text-sm text-muted-foreground">
                {todayStr}
              </p>
              {compliment && (
                <p className="mt-3 max-w-2xl italic text-foreground/70 transition-opacity duration-700">
                  「{compliment}」
                </p>
              )}
            </div>
            {!loading && !backend && (
              <Badge className="bg-destructive/10 text-destructive">后端未连接</Badge>
            )}
          </div>
        </section>

        {/* 待处理信息流：按紧急度（逾期 → 临近 → 普通）自上而下 */}
        <PendingFlowCard items={flowItems} />

        {/* 关键指标：按中心分组，每组单行排布，避免卡片混排产生孤行 */}
        <section className="flex flex-col gap-6">
          <StatGroup icon={Wallet} title="财务与投资" cols="grid gap-4 grid-cols-2 sm:grid-cols-3 min-[1680px]:grid-cols-5">
            <StatCard icon={Wallet} label="本月支出" value={fmt(fin?.month_expense ?? 0)} hint="含购/旅/水电/订阅/租/贷" money />
            <StatCard icon={HandCoins} label="累计待还" value={fmt(outstanding)} hint={`网贷 ${fmt(fin?.outstanding_loans ?? 0)} + 民间 ${fmt(fin?.outstanding_debt ?? 0)}`} />
            <StatCard icon={TrendingUp} label="投资净收益" value={signFmt(inv?.summary.net_profit ?? 0)} hint={`账户净值 ${fmt(inv?.summary.account_value ?? 0)}`} pnl />
            <StatCard icon={CircleDollarSign} label="投资胜率" value={`${inv?.summary.win_rate ?? 0}%`} hint={`共 ${inv?.summary.trade_count ?? 0} 笔交易`} />
            <StatCard icon={CreditCard} label="本月扣款" value={fmt(life?.month_deduct ?? 0)} hint="生活卡片类月度支出" />
          </StatGroup>

          <StatGroup icon={HeartPulse} title="健康" cols="grid gap-4 grid-cols-2 sm:grid-cols-3 min-[1680px]:grid-cols-5">
            <StatCard icon={Footprints} label="近期步数" value={`${num(health?.step_total ?? 0)} 步`} hint="近 30 天累计" />
            <StatCard icon={Timer} label="近期运动" value={`${health?.exercise_count ?? 0} 次`} hint="近 30 天记录" />
            <StatCard icon={Utensils} label="膳食摄入" value={`${num(health?.intake_total ?? 0)} kcal`} hint="近 30 天饮食总摄入" />
            <StatCard icon={Flame} label="运动消耗" value={`${num(health?.expenditure_total ?? 0)} kcal`} hint="近 30 天运动总消耗" />
            <StatCard icon={Scale} label="当前体重" value={health?.latest_body?.weight_kg ? `${health.latest_body.weight_kg} kg` : '—'} hint={health?.latest_body?.bmi ? `BMI ${health.latest_body.bmi}` : '暂无记录'} />
          </StatGroup>

          <StatGroup icon={Package} title="生活" cols="grid gap-4 grid-cols-2 sm:grid-cols-3">
            <StatCard icon={CaseSensitive} label="待办事项" value={`${life?.todo_pending ?? 0} 项`} hint={life?.todo_overdue ? `其中 ${life.todo_overdue} 项已逾期` : '暂无逾期'} />
            <StatCard icon={Package} label="临期物品" value={`${life?.item_expiring ?? 0} 项`} hint={life?.item_expired ? `另有 ${life.item_expired} 项已过期` : '30 天内到期'} />
            <StatCard icon={Coins} label="物品总价值" value={fmt(life?.item_value ?? 0)} hint={`卡片 ${life?.phone_total ?? 0} 张 · 银行卡 ${life?.bank_total ?? 0} 张`} />
          </StatGroup>
        </section>
      </div>

      {/* 侧栏：快捷入口与最新报告常驻可见 */}
      <aside className="flex flex-col gap-6">
        <QuickEntryRail />

        {life?.latest_report && (
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-sm">
                <Receipt className="size-4 text-emerald-500" />
                最新生活报告
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <Tip label={life.latest_report.title}>
                    <div className="truncate text-sm font-medium">{life.latest_report.title}</div>
                  </Tip>
                  {life.latest_report.period_label && (
                    <div className="text-xs text-muted-foreground">{life.latest_report.period_label}</div>
                  )}
                </div>
                <Link to="/lifestyle/reports" className="shrink-0 text-xs text-muted-foreground hover:text-foreground">
                  查看 →
                </Link>
              </div>
              {life.latest_report.summary && (
                <p className="mt-2 text-sm text-muted-foreground">{life.latest_report.summary}</p>
              )}
            </CardContent>
          </Card>
        )}
      </aside>
    </div>
  )
}
