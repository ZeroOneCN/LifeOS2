import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  AlertTriangle,
  CalendarClock,
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
  ShoppingCart,
  Timer,
  TrendingUp,
  Wallet,
  type LucideIcon,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { navigation } from '@/config/navigation'
import { api } from '@/lib/api'

const centers = navigation.filter((s) => !s.system)

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
const signFmt = (n: number) =>
  `${n >= 0 ? '+' : ''}${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
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
  pending_reminders: { id: number; title: string; category: string; amount?: number; due_date?: string }[]
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

type Profile = { nickname?: string; username?: string }

/* ------------------------------ 小组件 ------------------------------ */

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
  const color = pnl ? (numeric >= 0 ? 'text-emerald-600' : 'text-red-600') : money ? 'text-emerald-600' : ''
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

function ReminderCard({
  icon: Icon,
  title,
  to,
  iconClass,
  children,
}: {
  icon: LucideIcon
  title: string
  to: string
  iconClass: string
  children: React.ReactNode
}) {
  return (
    <Card className="h-full">
      <CardHeader>
        <CardTitle className="flex items-center justify-between text-sm">
          <span className="flex items-center gap-2">
            <Icon className={`size-4 ${iconClass}`} />
            {title}
          </span>
          <Link
            to={to}
            className="text-xs text-muted-foreground hover:text-foreground"
          >
            查看 →
          </Link>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">{children}</CardContent>
    </Card>
  )
}

function Empty({ text }: { text: string }) {
  return <p className="py-6 text-center text-sm text-muted-foreground">{text}</p>
}

/* ------------------------------ 页面主体 ------------------------------ */

export function HomePage() {
  const [fin, setFin] = useState<FinOverview | null>(null)
  const [health, setHealth] = useState<HealthDash | null>(null)
  const [life, setLife] = useState<LifeOverview | null>(null)
  const [inv, setInv] = useState<InvOverview | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [backend, setBackend] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.allSettled([
      api.query<FinOverview>('/finance/overview').then(setFin),
      api.query<HealthDash>('/health/dashboard').then(setHealth),
      api.query<LifeOverview>('/lifestyle/overview').then(setLife),
      api.query<InvOverview>('/investment/overview').then(setInv),
      api.query<Profile>('/user/profile')
        .then(setProfile)
        .catch(() => setProfile(null)),
      fetch('/api/v1/health')
        .then((r) => r.json())
        .then((d) => setBackend(d.status === 'ok'))
        .catch(() => setBackend(false)),
    ]).finally(() => setLoading(false))
  }, [])

  // 问候语
  const hour = new Date().getHours()
  const greeting = hour < 6 ? '夜深了' : hour < 9 ? '早上好' : hour < 12 ? '上午好' : hour < 14 ? '中午好' : hour < 18 ? '下午好' : '晚上好'
  const todayStr = new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  }).format(new Date())
  const displayName = profile?.nickname || profile?.username || '主人'

  const outstanding = (fin?.outstanding_loans ?? 0) + (fin?.outstanding_debt ?? 0)

  const pendingCount =
    (fin?.pending_bills.length ?? 0) + (fin?.pending_utils.length ?? 0) + (fin?.pending_reminders.length ?? 0)

  return (
    <div className="flex flex-col gap-6">
      {/* 问候区 */}
      <section className="rounded-xl border bg-gradient-to-r from-primary/10 via-background to-background p-6">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <h1 className="font-heading text-2xl font-semibold tracking-tight">
              {greeting}，{displayName}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {todayStr} · 今天是管理各项生活的美好一天
            </p>
          </div>
          {!loading && !backend && (
            <Badge className="bg-destructive/10 text-destructive">后端未连接</Badge>
          )}
        </div>
      </section>

      {/* 关键指标 */}
      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={Wallet} label="本月支出" value={fmt(fin?.month_expense ?? 0)} hint="含购/旅/水电/订阅/租/贷" money />
        <StatCard icon={HandCoins} label="累计待还" value={fmt(outstanding)} hint={`网贷 ${fmt(fin?.outstanding_loans ?? 0)} + 民间 ${fmt(fin?.outstanding_debt ?? 0)}`} />
        <StatCard icon={TrendingUp} label="投资净收益" value={signFmt(inv?.summary.net_profit ?? 0)} hint={`账户净值 ${fmt(inv?.summary.account_value ?? 0)}`} pnl />
        <StatCard icon={CircleDollarSign} label="投资胜率" value={`${inv?.summary.win_rate ?? 0}%`} hint={`共 ${inv?.summary.trade_count ?? 0} 笔交易`} />
        <StatCard icon={Footprints} label="近期步数" value={`${num(health?.step_total ?? 0)} 步`} hint="近 30 天累计" />
        <StatCard icon={Timer} label="近期运动" value={`${health?.exercise_count ?? 0} 次`} hint="近 30 天记录" />
        <StatCard icon={Flame} label="膳食摄入" value={`${num(health?.intake_total ?? 0)} kcal`} hint="近 30 天饮食总摄入" />
        <StatCard icon={Flame} label="运动消耗" value={`${num(health?.expenditure_total ?? 0)} kcal`} hint="近 30 天运动总消耗" />
        <StatCard icon={Scale} label="当前体重" value={health?.latest_body?.weight_kg ? `${health.latest_body.weight_kg} kg` : '—'} hint={health?.latest_body?.bmi ? `BMI ${health.latest_body.bmi}` : '暂无记录'} />
        <StatCard icon={CaseSensitive} label="待办事项" value={`${life?.todo_pending ?? 0} 项`} hint={life?.todo_overdue ? `其中 ${life.todo_overdue} 项已逾期` : '暂无逾期'} />
        <StatCard icon={Package} label="临期物品" value={`${life?.item_expiring ?? 0} 项`} hint={life?.item_expired ? `另有 ${life.item_expired} 项已过期` : '30 天内到期'} />
        <StatCard icon={Coins} label="物品总价值" value={fmt(life?.item_value ?? 0)} hint={`卡片 ${life?.phone_total ?? 0} 张 · 银行卡 ${life?.bank_total ?? 0} 张`} />
        <StatCard icon={CreditCard} label="本月扣款" value={fmt(life?.month_deduct ?? 0)} hint="生活卡片类月度支出" />
      </section>

      {/* 待办与提醒 */}
      <section className="grid gap-4 lg:grid-cols-3">
        <ReminderCard icon={AlertTriangle} title="待缴账单" iconClass="text-amber-500" to="/finance/overview">
          {!fin || pendingCount === 0 ? (
            <Empty text="暂无待缴账单或提醒" />
          ) : (
            <>
              {fin.pending_bills.map((b) => (
                <div key={b.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{b.bill_type}</div>
                    <div className="text-xs text-muted-foreground">到期 {b.due_date ?? '—'}</div>
                  </div>
                  <span className="text-sm font-medium text-red-600">{fmt(b.remaining ?? b.amount)}</span>
                </div>
              ))}
              {fin.pending_utils.map((u) => (
                <div key={u.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{u.bill_type}</div>
                    <div className="text-xs text-muted-foreground">到期 {u.due_date ?? '—'}</div>
                  </div>
                  <span className="text-sm font-medium text-red-600">{fmt(u.amount)}</span>
                </div>
              ))}
              {fin.pending_reminders.map((r) => (
                <div key={r.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{r.title}</div>
                    <div className="text-xs text-muted-foreground">{r.category} · 截止 {r.due_date ?? '—'}</div>
                  </div>
                  {r.amount != null && <span className="text-sm font-medium">{fmt(r.amount)}</span>}
                </div>
              ))}
            </>
          )}
        </ReminderCard>

        <ReminderCard icon={CalendarClock} title="待办清单" iconClass="text-sky-500" to="/lifestyle/todos">
          {!life || life.pending_todos.length === 0 ? (
            <Empty text="暂无待办事项" />
          ) : (
            life.pending_todos.map((t) => (
              <div key={t.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                <div>
                  <div className="text-sm font-medium">{t.title}</div>
                  <div className="text-xs text-muted-foreground">
                    {t.category} · {t.due_date ?? '无期限'}
                  </div>
                </div>
                {t.priority && (
                  <Badge className={t.priority === 'high' ? 'bg-red-100 text-red-700' : t.priority === 'medium' ? 'bg-amber-100 text-amber-700' : 'bg-muted text-muted-foreground'}>
                    {t.priority === 'high' ? '高' : t.priority === 'medium' ? '中' : '低'}
                  </Badge>
                )}
              </div>
            ))
          )}
        </ReminderCard>

        <ReminderCard icon={ShoppingCart} title="临期提醒" iconClass="text-violet-500" to="/finance/overview">
          {(!fin || fin.upcoming_subs.length === 0) && (!life || life.expiring_items.length === 0) ? (
            <Empty text="暂无明显临期事项" />
          ) : (
            <>
              {fin?.upcoming_subs.map((s) => (
                <div key={s.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{s.title}</div>
                    <div className="text-xs text-muted-foreground">{s.category} · 到期 {s.due_date ?? '—'}</div>
                  </div>
                  {s.amount != null && <span className="text-sm font-medium">{fmt(s.amount)}</span>}
                </div>
              ))}
              {life?.expiring_items.map((i) => (
                <div key={i.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                  <div>
                    <div className="text-sm font-medium">{i.item_name}</div>
                    <div className="text-xs text-muted-foreground">{i.category} · 距到期 {i.days_left} 天</div>
                  </div>
                  <Badge className={
                    (i.expire_date && new Date(`${i.expire_date}T00:00:00`) < new Date())
                      ? 'bg-red-100 text-red-700'
                      : i.days_left <= 7
                        ? 'bg-amber-100 text-amber-700'
                        : 'bg-muted text-muted-foreground'
                  }>
                    {i.days_left <= 0 ? '已过期' : `剩 ${i.days_left} 天`}
                  </Badge>
                </div>
              ))}
            </>
          )}
        </ReminderCard>
      </section>

      {/* 快捷入口 */}
      <section>
        <div className="mb-3 flex items-center gap-2">
          <HeartPulse className="size-4 text-muted-foreground" />
          <h2 className="text-sm font-semibold text-muted-foreground">功能中心快捷入口</h2>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
          {centers.map((center) => (
            <Link key={center.title} to={center.children[0].url} className="h-full">
              <Card className="h-full transition-colors hover:bg-muted/60">
                <CardHeader>
                  <center.icon className="size-5 text-primary" />
                  <CardTitle className="mt-2">{center.title}</CardTitle>
                  <CardDescription className="line-clamp-2">
                    {center.children.map((item) => item.title).join(' · ')}
                  </CardDescription>
                </CardHeader>
              </Card>
            </Link>
          ))}
        </div>
      </section>

      {/* 生活速览小卡（最新报告） */}
      {life?.latest_report && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm">
              <Receipt className="size-4 text-emerald-500" />
              最新生活报告
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex items-center justify-between">
              <div>
                <div className="text-sm font-medium">{life.latest_report.title}</div>
                {life.latest_report.period_label && (
                  <div className="text-xs text-muted-foreground">{life.latest_report.period_label}</div>
                )}
              </div>
              <Link to="/lifestyle/reports" className="text-xs text-muted-foreground hover:text-foreground">
                查看 →
              </Link>
            </div>
            {life.latest_report.summary && (
              <p className="mt-2 text-sm text-muted-foreground">{life.latest_report.summary}</p>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}