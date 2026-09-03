import { useEffect, useState } from 'react'
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { CalendarClock, Download, FileText, Gift, Percent, TrendingUp } from 'lucide-react'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { api } from '@/lib/api'

type OverviewData = {
  summary: {
    account_value: number
    net_profit: number
    gross_pnl: number
    total_commission: number
    total_overnight: number
    trade_count: number
    open_count: number
    win_rate?: number
    profit_loss_ratio?: number
    total_deposit: number
    total_withdraw: number
    total_experience: number
    symbol_count: number
  }
  analysis: {
    avg_win?: number
    avg_loss?: number
    max_drawdown: number
    max_drawdown_pct: number
    profit_factor?: number
    longest_win_streak: number
    longest_loss_streak: number
    avg_holding_minutes?: number
  }
  equity_trend: { date: string; pnl: number; pos: number; neg: number }[]
  daily_pnl: { date: string; amount: number }[]
  by_symbol: { symbol: string; count: number; win_rate: number; pnl: number }[]
  symbols: string[]
  report_count: number
  total_records: number
  fund_count: number
}

const fmtVal = (n: number) =>
  `${n < 0 ? '-' : ''}${Math.abs(n).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
const fmtPnl = (n: number) =>
  `${n >= 0 ? '+' : ''}${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
  accent = false,
}: {
  icon: typeof TrendingUp
  label: string
  value: string
  hint?: string
  accent?: boolean
}) {
  const numeric = Number(value.replace(/[^0-9.-]/g, ''))
  const earn = ['盈亏', '收益', '净值'].some((k) => label.includes(k))
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${accent ? 'text-emerald-600' : ''} ${earn ? (numeric >= 0 ? 'text-emerald-600' : 'text-red-600') : ''}`}>
          {value}
        </div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

function EquityChart({ data }: { data: OverviewData['equity_trend'] }) {
  if (!data || data.length === 0)
    return <p className="py-10 text-center text-sm text-muted-foreground">暂无足够数据</p>
  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
        <defs>
          <linearGradient id="gPosO" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#16a34a" stopOpacity={0.35} />
            <stop offset="100%" stopColor="#16a34a" stopOpacity={0.03} />
          </linearGradient>
          <linearGradient id="gNegO" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#dc2626" stopOpacity={0.03} />
            <stop offset="100%" stopColor="#dc2626" stopOpacity={0.35} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="date" tick={{ fontSize: 11 }} />
        <YAxis tick={{ fontSize: 11 }} />
        <Tooltip formatter={(value) => fmtPnl(Number(value))} />
        <ReferenceLine y={0} stroke="#6b7280" strokeDasharray="4 4" />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <Area type="monotone" dataKey="pos" name="盈利区" stackId="e" stroke="#16a34a" fill="url(#gPosO)" />
        <Area type="monotone" dataKey="neg" name="亏损区" stackId="e" stroke="#dc2626" fill="url(#gNegO)" />
        <Line type="monotone" dataKey="pnl" name="累计净收益" stroke="#111827" strokeWidth={1.5} dot={false} />
      </AreaChart>
    </ResponsiveContainer>
  )
}

export function InvestmentOverviewPage() {
  const [data, setData] = useState<OverviewData | null>(null)
  const [error, setError] = useState(false)
  useEffect(() => {
    api
      .query<OverviewData>('/investment/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [])

  if (error)
    return (
      <Card>
        <CardContent className="py-16 text-center text-sm text-muted-foreground">
          投资数据加载失败，请确认后端服务已启动。
        </CardContent>
      </Card>
    )
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

  const s = data.summary
  const a = data.analysis
  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">投资总览</h1>
        <p className="text-sm text-muted-foreground">
          汇总外汇交易、资金动态与投资报告，快速掌握整体账户表现。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={TrendingUp} label="账户净值" value={fmtVal(s.account_value)} hint={`入金 ${fmtVal(s.total_deposit)} / 出金 ${fmtVal(s.total_withdraw)}`} />
        <StatCard icon={Percent} label="净收益" value={fmtPnl(s.net_profit)} hint={`毛盈亏 ${fmtPnl(s.gross_pnl)}`} accent />
        <StatCard icon={Download} label="交易数" value={`${s.trade_count} 笔`} hint={`持仓 ${s.open_count} · 品种 ${s.symbol_count}`} />
        <StatCard icon={Percent} label="胜率" value={`${s.win_rate ?? 0}%`} hint={`盈亏比 ${s.profit_loss_ratio ?? 0}`} />
        <StatCard icon={TrendingUp} label="手续费" value={fmtVal(s.total_commission)} hint={`隔夜费 ${fmtVal(s.total_overnight)}`} />
        <StatCard icon={Gift} label="体验金" value={fmtVal(s.total_experience)} hint={`交易记录 ${data.total_records} 条`} />
        <StatCard icon={FileText} label="投资报告" value={`${data.report_count} 份`} hint="历史报告" />
        <StatCard icon={CalendarClock} label="资金动态" value={`${data.fund_count} 条`} hint="出入金/体验金记录" />
      </section>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">收益曲线（累计净收益）</CardTitle>
          <CardDescription>绿色盈利区、红色亏损区，0 为基线</CardDescription>
        </CardHeader>
        <CardContent>
          <EquityChart data={data.equity_trend} />
        </CardContent>
      </Card>

      {data.by_symbol.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-medium">交易品种盈亏（Top）</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={data.by_symbol.slice(0, 12)} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="symbol" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="pnl" name="净盈亏" radius={[4, 4, 0, 0]}>
                  {data.by_symbol.slice(0, 12).map((d, i) => (
                    <Cell key={i} fill={d.pnl >= 0 ? '#16a34a' : '#dc2626'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">近 12 个月净盈亏</CardTitle>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={data.daily_pnl} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip />
              <Bar dataKey="amount" name="净盈亏" radius={[2, 2, 0, 0]}>
                {data.daily_pnl.map((d, i) => (
                  <Cell key={i} fill={d.amount >= 0 ? '#16a34a' : '#dc2626'} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={Percent} label="平均盈利" value={a.avg_win != null ? fmtVal(a.avg_win) : '—'} />
        <StatCard icon={Percent} label="平均亏损" value={a.avg_loss != null ? fmtVal(a.avg_loss) : '—'} />
        <StatCard icon={TrendingUp} label="最大回撤" value={fmtVal(a.max_drawdown)} hint={`幅度 ${a.max_drawdown_pct}%`} />
        <StatCard icon={TrendingUp} label="盈利因子" value={a.profit_factor != null ? fmtVal(a.profit_factor) : '—'} hint={`连胜 ${a.longest_win_streak} · 连亏 ${a.longest_loss_streak}`} />
      </section>
    </div>
  )
}