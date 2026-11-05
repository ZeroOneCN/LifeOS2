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

import { PageHeader } from '@/components/page-header'
import { Card, CardContent, CardDescription, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import {
  DASH,
  formatDecimal,
  formatInt,
  formatPercent,
  formatUsd,
  formatUsdAxis,
  formatUsdSigned,
} from '@/lib/format'
import { useChartColors } from '@/lib/chart-theme'

/** Recharts Tooltip 深色适配：内联样式优先于 CSS，用主题变量保证深色下悬浮文字可读 */
const tooltipStyle = {
  backgroundColor: 'var(--popover)',
  border: '1px solid var(--border)',
  borderRadius: '0.5rem',
  color: 'var(--popover-foreground)',
  fontSize: '12px',
  boxShadow: '0 4px 14px rgba(0,0,0,0.18)',
}

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

/** 投资域金额统一为美元：负号在货币符号前，如 -$1,234.00 */
const fmtVal = formatUsd
/** 盈亏带符号，0 不加正号 */
const fmtPnl = formatUsdSigned
/** 图表坐标轴：整数美元，避免坐标轴被小数挤满 */
const fmtAxis = formatUsdAxis
/** 非金额比率（如盈利因子），不带货币符号 */
const fmtNum = (n: number) => formatDecimal(n, 2)

function StatCard({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: typeof TrendingUp
  label: string
  value: string
  hint?: string
}) {
  const numeric = Number(value.replace(/[^0-9.-]/g, '')) || 0
  const isMoneySign = ['盈亏', '收益', '净值'].some((k) => label.includes(k))
  // 颜色只由数值符号决定，不再额外叠加装饰性颜色（0 为中性）
  const tone = isMoneySign
    ? numeric > 0
      ? 'text-success'
      : numeric < 0
        ? 'text-danger'
        : 'text-muted-foreground'
    : ''
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground min-w-0 max-w-[55%] truncate">{label}</CardTitle>
        <CardHeaderActions>
          <Icon className="size-4 text-muted-foreground" />
        </CardHeaderActions>
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${tone}`}>
          {value}
        </div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

function EquityChart({ data }: { data: OverviewData['equity_trend'] }) {
  const palette = useChartColors()
  if (!data || data.length === 0)
    return <p className="py-10 text-center text-sm text-muted-foreground">暂无足够数据</p>
  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
        <defs>
          <linearGradient id="gPosO" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={palette.success} stopOpacity={0.35} />
            <stop offset="100%" stopColor={palette.success} stopOpacity={0.03} />
          </linearGradient>
          <linearGradient id="gNegO" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={palette.danger} stopOpacity={0.03} />
            <stop offset="100%" stopColor={palette.danger} stopOpacity={0.35} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette['chart-grid']} />
        <XAxis dataKey="date" tick={{ fontSize: 11, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} />
        <YAxis tick={{ fontSize: 11, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} tickFormatter={fmtAxis} />
        <Tooltip formatter={(value) => fmtPnl(Number(value))} contentStyle={tooltipStyle} />
        <ReferenceLine y={0} stroke={palette['chart-axis']} strokeDasharray="4 4" />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <Area type="monotone" dataKey="pos" name="盈利区" stackId="e" stroke={palette.success} fill="url(#gPosO)" />
        <Area type="monotone" dataKey="neg" name="亏损区" stackId="e" stroke={palette.danger} fill="url(#gNegO)" />
        <Line type="monotone" dataKey="pnl" name="累计净收益" stroke={palette['chart-axis']} strokeWidth={1.5} dot={false} />
      </AreaChart>
    </ResponsiveContainer>
  )
}

export function InvestmentOverviewPage() {
  const realtimeTick = useRealtime(30_000)
  const palette = useChartColors()
  const [data, setData] = useState<OverviewData | null>(null)
  const [error, setError] = useState(false)
  useEffect(() => {
    api
      .query<OverviewData>('/investment/overview')
      .then(setData)
      .catch(() => setError(true))
  }, [realtimeTick])

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
      <PageHeader
        title="投资总览"
        description="汇总外汇交易、资金动态与投资报告，快速掌握整体账户表现。"
      />

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={TrendingUp} label="账户净值" value={fmtVal(s.account_value)} hint={`入金 ${fmtVal(s.total_deposit)} / 出金 ${fmtVal(s.total_withdraw)}`} />
        <StatCard icon={Percent} label="净收益" value={fmtPnl(s.net_profit)} hint={`毛盈亏 ${fmtPnl(s.gross_pnl)}`} />
        <StatCard icon={Download} label="交易数" value={`${formatInt(s.trade_count)} 笔`} hint={`持仓 ${formatInt(s.open_count)} · 品种 ${formatInt(s.symbol_count)}`} />
        <StatCard icon={Percent} label="胜率" value={formatPercent(s.win_rate ?? 0)} hint={`盈亏比 ${formatDecimal(s.profit_loss_ratio ?? 0, 2)}`} />
        <StatCard icon={TrendingUp} label="手续费" value={fmtVal(s.total_commission)} hint={`隔夜费 ${fmtVal(s.total_overnight)}`} />
        <StatCard icon={Gift} label="体验金" value={fmtVal(s.total_experience)} hint={`交易记录 ${formatInt(data.total_records)} 条`} />
        <StatCard icon={FileText} label="投资报告" value={`${formatInt(data.report_count)} 份`} hint="历史报告" />
        <StatCard icon={CalendarClock} label="资金动态" value={`${formatInt(data.fund_count)} 条`} hint="出入金/体验金记录" />
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
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette['chart-grid']} />
                <XAxis dataKey="symbol" tick={{ fontSize: 11, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} />
                <YAxis tick={{ fontSize: 11, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} tickFormatter={fmtAxis} />
                <Tooltip formatter={(value) => fmtPnl(Number(value))} contentStyle={tooltipStyle} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="pnl" name="净盈亏" radius={[4, 4, 0, 0]}>
                  {data.by_symbol.slice(0, 12).map((d, i) => (
                    <Cell key={i} fill={d.pnl >= 0 ? palette.success : palette.danger} />
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
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke={palette['chart-grid']} />
              <XAxis dataKey="date" tick={{ fontSize: 10, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} />
              <YAxis tick={{ fontSize: 11, fill: palette['chart-axis'] }} stroke={palette['chart-axis']} tickFormatter={fmtAxis} />
              <Tooltip formatter={(value) => fmtPnl(Number(value))} contentStyle={tooltipStyle} />
              <Bar dataKey="amount" name="净盈亏" radius={[2, 2, 0, 0]}>
                {data.daily_pnl.map((d, i) => (
                  <Cell key={i} fill={d.amount >= 0 ? palette.success : palette.danger} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard icon={Percent} label="平均盈利" value={a.avg_win != null ? fmtVal(a.avg_win) : DASH} />
        <StatCard icon={Percent} label="平均亏损" value={a.avg_loss != null ? fmtVal(a.avg_loss) : DASH} />
        <StatCard icon={TrendingUp} label="最大回撤" value={fmtVal(a.max_drawdown)} hint={`幅度 ${formatPercent(a.max_drawdown_pct)}`} />
        <StatCard icon={TrendingUp} label="盈利因子" value={a.profit_factor != null ? fmtNum(a.profit_factor) : DASH} hint={`连胜 ${formatInt(a.longest_win_streak)} · 连亏 ${formatInt(a.longest_loss_streak)}`} />
      </section>
    </div>
  )
}