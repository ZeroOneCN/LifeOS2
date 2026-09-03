import { useEffect, useMemo, useState } from 'react'
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
import { toast } from 'sonner'
import {
  ArrowDownToLine,
  ArrowUpFromLine,
  CalendarDays,
  Download,
  Gift,
  HardHat,
  Loader2,
  Percent,
  Plus,
  RefreshCw,
  Trash2,
  TrendingUp,
  Upload,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { RecordManager, type ColumnDef, type FieldDef } from '@/components/health/record-manager'
import { api } from '@/lib/api'

// ---------------------------------------------------------------------------
// 类型
// ---------------------------------------------------------------------------
type ForexRecord = {
  id: number
  trade_date: string
  symbol: string
  order_type: 'buy' | 'sell'
  open_price: number
  lot_size: number
  commission: number
  close_price?: number
  pnl?: number
  overnight_fee: number
  open_time?: string
  close_time?: string
  holding?: number
  status: 'open' | 'closed'
  note?: string
}

type ForexStats = {
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
    profit_factor?: number
    total_deposit: number
    total_withdraw: number
    total_experience: number
    symbol_count: number
  }
  equity_trend: { date: string; pnl: number; pos: number; neg: number }[]
  daily_pnl: { date: string; amount: number }[]
  by_symbol: { symbol: string; count: number; win_rate: number; pnl: number }[]
  symbols: string[]
  analysis: {
    avg_win?: number
    avg_loss?: number
    max_drawdown: number
    max_drawdown_pct: number
    profit_factor?: number
    longest_win_streak: number
    longest_loss_streak: number
    avg_holding_minutes?: number
    hour_dist: { hour: number; count: number }[]
  }
}

type FundRecord = {
  id: number
  record_type: 'deposit' | 'withdraw' | 'experience'
  amount: number
  record_date: string
  note?: string
}

type FundStats = {
  deposit: number
  withdraw: number
  experience: number
  net: number
  by_date: { date: string; deposit: number; withdraw: number; experience: number }[]
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
const fmtVal = (n: number) =>
  `${n < 0 ? '-' : ''}${Math.abs(n).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
const fmtPnl = (n: number) =>
  `${n >= 0 ? '+' : ''}${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
const pnlCls = (n: number) =>
  n >= 0 ? 'font-semibold text-emerald-600' : 'font-semibold text-red-600'
const fmtHolding = (min?: number) => {
  if (min == null) return '—'
  if (min < 60) return `${min}分`
  const h = Math.floor(min / 60)
  const m = min % 60
  return `${h}时${m}分`
}

// ---------------------------------------------------------------------------
// 交易表单字段（MT5 格式）
// ---------------------------------------------------------------------------
const tradeFields: FieldDef[] = [
  { key: 'trade_date', label: '交易日期', type: 'date', required: true },
  { key: 'symbol', label: '交易品种', type: 'text', required: true, placeholder: 'EUR/USD' },
  {
    key: 'order_type',
    label: '订单类型',
    type: 'select',
    required: true,
    options: [
      { value: 'buy', label: '做多 Buy' },
      { value: 'sell', label: '做空 Sell' },
    ],
  },
  { key: 'open_price', label: '开仓价格', type: 'number', required: true, step: '0.0001', min: 0 },
  { key: 'lot_size', label: '手数', type: 'number', required: true, step: '0.01', min: 0 },
  { key: 'open_time', label: '开仓时间', type: 'datetime' },
  { key: 'close_price', label: '平仓价格', type: 'number', step: '0.0001', min: 0 },
  { key: 'close_time', label: '平仓时间', type: 'datetime' },
  { key: 'commission', label: '手续费', type: 'number', step: '0.01' },
  { key: 'overnight_fee', label: '隔夜费', type: 'number', step: '0.01' },
  { key: 'pnl', label: '盈亏金额', type: 'number', step: '0.01' },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const tradeColumns: ColumnDef<ForexRecord>[] = [
  { key: 'trade_date', label: '日期时间' },
  { key: 'symbol', label: '交易品种' },
  {
    key: 'order_type',
    label: '订单类型',
    render: (r) =>
      r.order_type === 'buy' ? (
        <Badge className="bg-green-100 text-green-700">做多 Buy</Badge>
      ) : (
        <Badge className="bg-red-100 text-red-700">做空 Sell</Badge>
      ),
  },
  { key: 'open_price', label: '开仓价格' },
  { key: 'lot_size', label: '手数' },
  { key: 'commission', label: '手续费' },
  { key: 'close_price', label: '平仓价格', render: (r) => (r.close_price ?? '—') },
  {
    key: 'pnl',
    label: '盈亏金额',
    render: (r) => (r.pnl != null ? <span className={pnlCls(r.pnl)}>{fmtPnl(r.pnl)}</span> : '—'),
  },
  { key: 'overnight_fee', label: '隔夜费' },
  { key: 'open_time', label: '开仓时间', render: (r) => fmtDT(r.open_time) },
  { key: 'close_time', label: '平仓时间', render: (r) => fmtDT(r.close_time) },
  {
    key: 'holding',
    label: '持仓时间',
    render: (r) => <span className="text-muted-foreground">{fmtHolding(r.holding)}</span>,
  },
  { key: 'note', label: '备注' },
]

const fmtDT = (v?: string) => {
  if (!v) return '—'
  return v.replace('T', ' ').slice(0, 19)
}

// ---------------------------------------------------------------------------
// 收益曲线（红绿基线：绿涨红跌，0 为基线）
// ---------------------------------------------------------------------------
function EquityChart({ data }: { data: ForexStats['equity_trend'] }) {
  if (!data || data.length === 0)
    return <p className="py-10 text-center text-sm text-muted-foreground">暂无足够数据绘制收益曲线</p>
  return (
    <ResponsiveContainer width="100%" height={280}>
      <AreaChart data={data} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
        <defs>
          <linearGradient id="gEquityPos" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#16a34a" stopOpacity={0.35} />
            <stop offset="100%" stopColor="#16a34a" stopOpacity={0.03} />
          </linearGradient>
          <linearGradient id="gEquityNeg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#dc2626" stopOpacity={0.03} />
            <stop offset="100%" stopColor="#dc2626" stopOpacity={0.35} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="date" tick={{ fontSize: 11 }} />
        <YAxis tick={{ fontSize: 11 }} />
        <Tooltip formatter={(value) => fmtPnl(Number(value))} />
        <ReferenceLine y={0} stroke="#6b7280" strokeDasharray="4 4" label={{ value: '0', position: 'insideTopLeft', fontSize: 11, fill: '#6b7280' }} />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <Area type="monotone" dataKey="pos" name="盈利区" stackId="e" stroke="#16a34a" fill="url(#gEquityPos)" />
        <Area type="monotone" dataKey="neg" name="亏损区" stackId="e" stroke="#dc2626" fill="url(#gEquityNeg)" />
        <Line type="monotone" dataKey="pnl" name="累计净收益" stroke="#111827" strokeWidth={1.5} dot={false} />
      </AreaChart>
    </ResponsiveContainer>
  )
}

// ---------------------------------------------------------------------------
// 交易日历
// ---------------------------------------------------------------------------
type CalendarData = { year: number; month: number; days: { day: number; pnl: number; count: number; win: number; position: boolean }[] }

function TradingCalendar() {
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7))
  const [data, setData] = useState<CalendarData | null>(null)

  useEffect(() => {
    api
      .query<CalendarData>(`/investment/forex/calendar?month=${encodeURIComponent(month)}`)
      .then(setData)
      .catch(() => setData(null))
  }, [month])

  const firstDow = useMemo(() => (data ? new Date(data.year, data.month - 1, 1).getDay() : 0), [data])
  const cells: (CalendarData['days'][number] | null)[] = useMemo(
    () => [
      ...(data ? Array.from({ length: firstDow }, () => null) : []),
      ...(data?.days ?? []),
    ],
    [data, firstDow],
  )

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="flex items-center gap-2 text-sm">
          <CalendarDays className="size-4 text-indigo-500" /> 交易日历
        </CardTitle>
        <Input type="month" value={month} onChange={(e) => setMonth(e.target.value)} className="w-36" />
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-7 gap-1 text-center text-xs">
          {['日', '一', '二', '三', '四', '五', '六'].map((w) => (
            <div key={w} className="py-1 font-medium text-muted-foreground">{w}</div>
          ))}
          {cells.map((d, i) =>
            d ? (
              <div
                key={i}
                className={`flex min-h-14 flex-col justify-between rounded-lg border p-1 ${
                  d.count === 0
                    ? 'bg-muted/40 text-muted-foreground'
                    : d.pnl >= 0
                      ? 'bg-emerald-50 border-emerald-200'
                      : 'bg-red-50 border-red-200'
                }`}
              >
                <span className="self-start text-xs font-medium">{d.day}</span>
                {d.count > 0 && (
                  <div className="space-y-0.5 text-right">
                    <div className={`text-xs font-semibold ${pnlCls(d.pnl)}`}>{fmtPnl(d.pnl)}</div>
                    <div className="text-[10px] text-muted-foreground">{d.count}笔 {d.win > 0 ? `· 胜${d.win}` : ''}{d.position ? '· 持仓' : ''}</div>
                  </div>
                )}
              </div>
            ) : (
              <div key={i} />
            ),
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// 仓位计算（多仓位杠杆并行：共同计算保证金，按保证金比例算爆仓价格）
// ---------------------------------------------------------------------------
type PositionRow = {
  id: number
  symbol: string
  direction: 'buy' | 'sell'
  open_price: string
  lots: string
  leverage: string
}

const NEW_ROW = (): PositionRow => ({
  id: Date.now() + Math.floor(Math.random() * 100000),
  symbol: '',
  direction: 'buy',
  open_price: '',
  lots: '',
  leverage: '100',
})

function PositionCalculator({ equity }: { equity?: number }) {
  // 净值：默认注入实时净值，可手动变更；点「重置」恢复为实时净值
  const [equityVal, setEquityVal] = useState(() => (equity != null ? String(equity) : ''))
  const [contractSize, setContractSize] = useState('100000') // 每手合约规格（标准手=100000）
  const [stopOutPct, setStopOutPct] = useState('100') // 爆仓保证金比例 %
  const [warnPct, setWarnPct] = useState('150') // 预警保证金比例 %
  const [rows, setRows] = useState<PositionRow[]>([NEW_ROW()])

  useEffect(() => {
    if (equity != null) setEquityVal(String(equity))
  }, [equity])

  const addRow = () => setRows((prev) => [...prev, NEW_ROW()])
  const removeRow = (id: number) => setRows((prev) => prev.filter((r) => r.id !== id))
  const updateRow = (id: number, patch: Partial<PositionRow>) =>
    setRows((prev) => prev.map((r) => (r.id === id ? { ...r, ...patch } : r)))

  const result = useMemo(() => {
    const eq = parseFloat(equityVal)
    const cs = parseFloat(contractSize) || 100000
    const stopLevel = parseFloat(stopOutPct) > 0 ? parseFloat(stopOutPct) : 100
    const warnLevel = parseFloat(warnPct) > 0 ? parseFloat(warnPct) : stopLevel
    const positions = rows
      .map((r) => ({
        id: r.id,
        symbol: r.symbol.trim(),
        direction: r.direction,
        open: parseFloat(r.open_price),
        lots: parseFloat(r.lots),
        lev: parseFloat(r.leverage) > 0 ? parseFloat(r.leverage) : 1,
      }))
      .filter((p) => p.symbol && p.open > 0 && p.lots > 0)
    const hasEquity = !Number.isNaN(eq) && Number.isFinite(eq)
    if (!hasEquity || positions.length === 0) return null

    let totalNotional = 0
    let totalMargin = 0
    const list = positions.map((p) => {
      const notional = p.open * p.lots * cs // 名义价值
      const margin = notional / p.lev // 该仓位保证金 = 名义价值 / 杠杆
      totalNotional += notional
      totalMargin += margin
      return { ...p, notional, margin }
    })
    const freeMargin = eq - totalMargin // 可用保证金
    const marginLevel = totalMargin > 0 ? (eq / totalMargin) * 100 : null // 保证金比例 %

    // 每一仓位的爆仓价格：假定其它仓位不变，仅此仓价格变动，使保证金比例跌至爆仓阈值
    const liqList = list.map((p) => {
      const neededPnl = (stopLevel / 100) * totalMargin - eq // 触发强平还需再亏损的金额
      const perLot = p.lots * cs
      let liqPrice: number | null = null
      if (perLot > 0) {
        liqPrice =
          p.direction === 'buy' ? p.open + neededPnl / perLot : p.open - neededPnl / perLot
      }
      return { ...p, liqPrice }
    })

    let status: 'ok' | 'warn' | 'danger' | 'idle' = 'idle'
    if (marginLevel != null && totalMargin > 0) {
      if (marginLevel <= stopLevel) status = 'danger'
      else if (marginLevel <= warnLevel) status = 'warn'
      else status = 'ok'
    }
    return {
      eq,
      totalNotional: totalNotional || 0,
      totalMargin,
      freeMargin,
      marginLevel: totalMargin > 0 ? marginLevel! : null,
      stopLevel,
      warnLevel,
      list: liqList,
      status,
    }
  }, [equityVal, contractSize, stopOutPct, warnPct, rows])

  const statusBadge =
    result == null
      ? { text: '待输入', cls: 'bg-gray-100 text-gray-600' }
      : result.status === 'danger'
        ? { text: '已爆仓/强平', cls: 'bg-red-100 text-red-700' }
        : result.status === 'warn'
          ? { text: '预警', cls: 'bg-amber-100 text-amber-700' }
          : { text: '正常', cls: 'bg-emerald-100 text-emerald-700' }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm">
            <HardHat className="size-4 text-amber-500" /> 账户与爆仓参数
          </CardTitle>
          <CardDescription>基于实时净值（可手动变更）计算保证金比例与爆仓价格</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="space-y-1">
              <Label>账户净值（可改）</Label>
              <div className="flex gap-1">
                <Input type="number" value={equityVal} onChange={(e) => setEquityVal(e.target.value)} placeholder="0" />
                <Button variant="outline" size="icon" title="重置为实时净值" onClick={() => equity != null && setEquityVal(String(equity))}>
                  <RefreshCw className="size-4" />
                </Button>
              </div>
            </div>
            <div className="space-y-1">
              <Label>每手合约规格</Label>
              <Input type="number" value={contractSize} onChange={(e) => setContractSize(e.target.value)} placeholder="100000" />
            </div>
            <div className="space-y-1">
              <Label>爆仓保证金比例 %</Label>
              <Input type="number" value={stopOutPct} onChange={(e) => setStopOutPct(e.target.value)} placeholder="100" />
            </div>
            <div className="space-y-1">
              <Label>预警保证金比例 %</Label>
              <Input type="number" value={warnPct} onChange={(e) => setWarnPct(e.target.value)} placeholder="150" />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <div>
            <CardTitle className="flex items-center gap-2 text-sm">
              <Plus className="size-4 text-indigo-500" /> 持仓清单（多仓位并行）
            </CardTitle>
            <CardDescription>每个仓位独立杠杆，共同占用保证金，联动计算爆仓价格</CardDescription>
          </div>
          <Button size="sm" variant="outline" onClick={addRow}>
            <Plus /> 添加仓位
          </Button>
        </CardHeader>
        <CardContent className="space-y-2">
          {rows.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">暂无仓位，点击「添加仓位」开始计算。</p>
          ) : (
            rows.map((row) => (
              <div key={row.id} className="grid grid-cols-2 items-end gap-2 rounded-lg border p-2 sm:grid-cols-6">
                <div className="space-y-1">
                  <Label className="text-xs">交易品种</Label>
                  <Input value={row.symbol} onChange={(e) => updateRow(row.id, { symbol: e.target.value })} placeholder="EUR/USD" />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">方向</Label>
                  <Select value={row.direction} onValueChange={(v) => updateRow(row.id, { direction: v as PositionRow['direction'] })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="buy">做多 Buy</SelectItem>
                      <SelectItem value="sell">做空 Sell</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">开仓价</Label>
                  <Input type="number" value={row.open_price} onChange={(e) => updateRow(row.id, { open_price: e.target.value })} placeholder="1.1000" />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">手数</Label>
                  <Input type="number" value={row.lots} onChange={(e) => updateRow(row.id, { lots: e.target.value })} placeholder="1.00" />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">杠杆</Label>
                  <Input type="number" value={row.leverage} onChange={(e) => updateRow(row.id, { leverage: e.target.value })} placeholder="100" />
                </div>
                <div className="flex justify-end">
                  <Button size="icon" variant="ghost" className="text-destructive" onClick={() => removeRow(row.id)}>
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm">
            <TrendingUp className="size-4 text-emerald-500" /> 计算结果
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {!result ? (
            <p className="py-4 text-center text-sm text-muted-foreground">
              请至少填写净值并添加一个有效仓位（品种 + 开仓价 + 手数）。
            </p>
          ) : (
            <>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
                <div className="rounded-lg border p-3">
                  <div className="text-xs text-muted-foreground">账户净值</div>
                  <div className="text-lg font-semibold">{fmtVal(result.eq)}</div>
                </div>
                <div className="rounded-lg border p-3">
                  <div className="text-xs text-muted-foreground">总名义价值</div>
                  <div className="text-lg font-semibold">{fmtVal(result.totalNotional)}</div>
                </div>
                <div className="rounded-lg border p-3">
                  <div className="text-xs text-muted-foreground">总保证金</div>
                  <div className="text-lg font-semibold text-indigo-600">{fmtVal(result.totalMargin)}</div>
                </div>
                <div className="rounded-lg border p-3">
                  <div className="text-xs text-muted-foreground">可用保证金</div>
                  <div className="text-lg font-semibold">{fmtVal(result.freeMargin)}</div>
                </div>
                <div className="rounded-lg border p-3">
                  <div className="text-xs text-muted-foreground">保证金比例</div>
                  <div className="flex items-center gap-2">
                    <span className="text-lg font-semibold">{result.marginLevel != null ? `${result.marginLevel.toFixed(1)}%` : '—'}</span>
                    <Badge className={statusBadge.cls}>{statusBadge.text}</Badge>
                  </div>
                </div>
              </div>

              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>品种</TableHead>
                    <TableHead>方向</TableHead>
                    <TableHead>开仓价</TableHead>
                    <TableHead>手数</TableHead>
                    <TableHead>杠杆</TableHead>
                    <TableHead className="text-right">名义价值</TableHead>
                    <TableHead className="text-right">该仓保证金</TableHead>
                    <TableHead className="text-right">爆仓价格</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {result.list.map((p) => (
                    <TableRow key={p.id}>
                      <TableCell className="font-medium">{p.symbol}</TableCell>
                      <TableCell>
                        {p.direction === 'buy' ? (
                          <Badge className="bg-green-100 text-green-700">多</Badge>
                        ) : (
                          <Badge className="bg-red-100 text-red-700">空</Badge>
                        )}
                      </TableCell>
                      <TableCell>{p.open}</TableCell>
                      <TableCell>{p.lots}</TableCell>
                      <TableCell>1:{p.lev}</TableCell>
                      <TableCell className="text-right">{fmtVal(p.notional)}</TableCell>
                      <TableCell className="text-right text-indigo-600">{fmtVal(p.margin)}</TableCell>
                      <TableCell className="text-right font-medium">
                        {p.liqPrice != null && Number.isFinite(p.liqPrice) ? p.liqPrice.toFixed(p.open < 10 ? 4 : 2) : '—'}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <p className="text-xs text-muted-foreground">
                爆仓价格：假定其余仓位不变，仅该仓位价格变动，使整体保证金比例跌至 {result.stopLevel}% 时对应的价格
                （{result.warnLevel}% 为预警阈值）。
              </p>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// 资金动态（入金/出金/体验金）
// ---------------------------------------------------------------------------
const fundTypes = [
  { value: 'deposit', label: '入金' },
  { value: 'withdraw', label: '出金' },
  { value: 'experience', label: '体验金' },
] as const

function FundsSection() {
  const [stats, setStats] = useState<FundStats | null>(null)
  const [items, setItems] = useState<FundRecord[]>([])
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<FundRecord | null>(null)
  const [form, setForm] = useState({ record_type: 'deposit', amount: '', record_date: new Date().toISOString().slice(0, 10), note: '' })
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条资金记录吗？' })

  const load = async () => {
    try {
      const s = await api.query<FundStats>('/investment/funds/stats')
      setStats(s)
      const list = await api.list<FundRecord>('/investment/funds', { page: 1, page_size: 50 })
      setItems(list.items)
    } catch {
      setStats(null)
    }
  }
  useEffect(() => {
    load()
  }, [])

  const openCreate = () => {
    setEditing(null)
    setForm({ record_type: 'deposit', amount: '', record_date: new Date().toISOString().slice(0, 10), note: '' })
    setOpen(true)
  }
  const openEdit = (r: FundRecord) => {
    setEditing(r)
    setForm({ record_type: r.record_type, amount: String(r.amount), record_date: r.record_date, note: r.note ?? '' })
    setOpen(true)
  }
  const submit = async () => {
    const payload = { record_type: form.record_type, amount: Number(form.amount), record_date: form.record_date, note: form.note || null }
    try {
      if (editing) await api.update('/investment/funds', editing.id, payload)
      else await api.create('/investment/funds', payload)
      setOpen(false)
      await load()
    } catch (e) {
      toast.error('保存失败', { description: (e as Error).message })
    }
  }
  const remove = async (r: FundRecord) => {
    if (!(await confirm())) return
    await api.remove('/investment/funds', r.id)
    await load()
  }

  const itemsSorted = [...items].sort((a, b) => (a.record_date < b.record_date ? 1 : -1))

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between pb-2">
        <div>
          <CardTitle className="flex items-center gap-2 text-sm">
            <TrendingUp className="size-4 text-indigo-500" /> 资金动态
          </CardTitle>
          <CardDescription>记录出入金与体验金，构成账户净值</CardDescription>
        </div>
        <Button size="sm" onClick={openCreate}>记录资金</Button>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Card className="border-green-200">
            <CardContent className="flex items-center justify-between py-3">
              <span className="text-sm text-muted-foreground">累计入金</span>
              <Badge className="bg-green-100 text-green-700">{stats ? fmtVal(stats.deposit) : '—'}</Badge>
            </CardContent>
          </Card>
          <Card className="border-red-200">
            <CardContent className="flex items-center justify-between py-3">
              <span className="text-sm text-muted-foreground">累计出金</span>
              <Badge className="bg-red-100 text-red-700">{stats ? fmtVal(stats.withdraw) : '—'}</Badge>
            </CardContent>
          </Card>
          <Card className="border-amber-200">
            <CardContent className="flex items-center justify-between py-3">
              <span className="text-sm text-muted-foreground">体验金</span>
              <Badge className="bg-amber-100 text-amber-700">{stats ? fmtVal(stats.experience) : '—'}</Badge>
            </CardContent>
          </Card>
          <Card className="border-indigo-200">
            <CardContent className="flex items-center justify-between py-3">
              <span className="text-sm text-muted-foreground">净投入</span>
              <Badge className="bg-indigo-100 text-indigo-700">{stats ? fmtVal(stats.net) : '—'}</Badge>
            </CardContent>
          </Card>
        </div>

        {itemsSorted.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">暂无资金记录，点击「记录资金」添加入金/出金/体验金。</p>
        ) : (
          <div className="max-h-72 space-y-2 overflow-y-auto pr-1">
            {itemsSorted.map((r) => (
              <div key={r.id} className="flex items-center justify-between rounded-lg border px-3 py-2">
                <div className="flex items-center gap-3">
                  {r.record_type === 'deposit' ? (
                    <ArrowDownToLine className="size-4 text-green-600" />
                  ) : r.record_type === 'withdraw' ? (
                    <ArrowUpFromLine className="size-4 text-red-600" />
                  ) : (
                    <Gift className="size-4 text-amber-500" />
                  )}
                  <div>
                    <div className="text-sm font-medium">
                      {fundTypes.find((t) => t.value === r.record_type)?.label}
                      <span className="ml-2 font-semibold text-emerald-600">+{fmtVal(r.amount)}</span>
                    </div>
                    <div className="text-xs text-muted-foreground">{r.record_date}{r.note ? ` · ${r.note}` : ''}</div>
                  </div>
                </div>
                <div className="flex gap-1">
                  <Button size="icon" variant="ghost" onClick={() => openEdit(r)}>编辑</Button>
                  <Button size="icon" variant="ghost" className="text-destructive" onClick={() => remove(r)}>删除</Button>
                </div>
              </div>
            ))}
          </div>
        )}

        {itemsSorted.length > 0 && stats && stats.by_date.length > 0 && (
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={stats.by_date}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Bar dataKey="deposit" name="入金" fill="#16a34a" radius={[3, 3, 0, 0]} />
              <Bar dataKey="withdraw" name="出金" fill="#dc2626" radius={[3, 3, 0, 0]} />
              <Bar dataKey="experience" name="体验金" fill="#f59e0b" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </CardContent>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing ? '编辑资金记录' : '记录资金'}</DialogTitle>
            <DialogDescription>登记入金 / 出金 / 体验金，金额为正数。</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>类型</Label>
              <Select value={form.record_type} onValueChange={(v) => setForm((f) => ({ ...f, record_type: v as typeof form.record_type }))}>
                <SelectTrigger>
                  <SelectValue placeholder="选择类型" />
                </SelectTrigger>
                <SelectContent>
                  {fundTypes.map((t) => (
                    <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>发生日期</Label>
              <Input type="date" value={form.record_date} onChange={(e) => setForm((f) => ({ ...f, record_date: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label>金额</Label>
              <Input type="number" step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} placeholder="1000" />
            </div>
            <div className="space-y-2">
              <Label>备注</Label>
              <Input value={form.note} onChange={(e) => setForm((f) => ({ ...f, note: e.target.value }))} placeholder="如：首次入金、出金提现等" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>取消</Button>
            <Button onClick={submit}>保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {confirmDialog}
    </Card>
  )
}

// ---------------------------------------------------------------------------
// xlsx 导入
// ---------------------------------------------------------------------------
function ImportButton({ onDone }: { onDone: () => void }) {
  const [importing, setImporting] = useState(false)
  const [mode, setMode] = useState<'append' | 'replace'>('append')
  const handle = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setImporting(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const res = await api.upload<{ imported: number; skipped: number }>(`/investment/forex/import?mode=${mode}`, fd)
      toast.success('导入完成', { description: `成功导入 ${res.imported} 条，跳过 ${res.skipped} 条` })
      onDone()
    } catch (err) {
      toast.error('导入失败', { description: (err as Error).message })
    } finally {
      setImporting(false)
      e.target.value = ''
    }
  }
  return (
    <div className="flex items-center gap-2">
      <Select value={mode} onValueChange={(v) => setMode(v as typeof mode)}>
        <SelectTrigger className="w-28">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="append">增量导入</SelectItem>
          <SelectItem value="replace">覆盖导入</SelectItem>
        </SelectContent>
      </Select>
      <Button disabled={importing} onClick={() => document.getElementById('forex-import-input')?.click()}>
        {importing ? <Loader2 className="size-4 animate-spin" /> : <Upload className="size-4" />}
        导入 xlsx
      </Button>
      <input id="forex-import-input" type="file" accept=".xlsx,.xlsm" className="hidden" onChange={handle} />
    </div>
  )
}

// ---------------------------------------------------------------------------
// 页面
// ---------------------------------------------------------------------------
function StatCard({ icon: Icon, label, value, hint, accent = false }: { icon: typeof TrendingUp; label: string; value: string; hint?: string; accent?: boolean }) {
  const numeric = Number(value.replace(/[^0-9.-]/g, ''))
  const earningsStyle = label.includes('盈亏') || label.includes('收益') || label.includes('净值') ? (numeric >= 0 ? 'text-emerald-600' : 'text-red-600') : ''
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${accent ? 'text-emerald-600' : ''} ${earningsStyle}`}>{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function ForexPage() {
  const [stats, setStats] = useState<ForexStats | null>(null)
  const [refresh, setRefresh] = useState(0)

  useEffect(() => {
    api
      .stats<ForexStats>('/investment/forex', 3650)
      .then(setStats)
      .catch(() => setStats(null))
  }, [refresh])

  const onImported = () => setRefresh((r) => r + 1)
  const s = stats?.summary
  const a = stats?.analysis

  return (
    <div className="flex flex-col gap-4">
      <Tabs defaultValue="trades">
        <TabsList>
          <TabsTrigger value="trades">交易列表</TabsTrigger>
          <TabsTrigger value="funds">资金动态</TabsTrigger>
          <TabsTrigger value="position">仓位计算</TabsTrigger>
        </TabsList>

        <TabsContent value="trades">
          <RecordManager<ForexRecord>
            title="外汇交易"
            description="MT5 导出并清洗后导入交易明细，自动计算持仓时间，追踪盈亏与交易表现。"
            apiPath="/investment/forex"
            fields={tradeFields}
            columns={tradeColumns}
            refreshKey={refresh}
            headerExtra={<ImportButton onDone={onImported} />}
            extra={
              <>
                {s && (
                  <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <StatCard icon={TrendingUp} label="账户净值" value={fmtVal(s.account_value)} hint={`入金 ${fmtVal(s.total_deposit)} - 出金 ${fmtVal(s.total_withdraw)}`} />
                    <StatCard icon={Percent} label="净收益" value={fmtPnl(s.net_profit)} hint={`毛盈亏 ${fmtPnl(s.gross_pnl)}`} accent />
                    <StatCard icon={Download} label="交易数" value={`${s.trade_count} 笔`} hint={`持仓 ${s.open_count} · 品种 ${s.symbol_count}`} />
                    <StatCard icon={Percent} label="胜率" value={`${s.win_rate ?? 0}%`} hint={`盈亏比 ${s.profit_loss_ratio ?? 0}`} />
                    <StatCard icon={Download} label="手续费" value={fmtVal(s.total_commission)} hint="累计手续费" />
                    <StatCard icon={CalendarDays} label="隔夜费" value={fmtVal(s.total_overnight)} hint="库存/隔夜费合计" />
                    <StatCard icon={ArrowUpFromLine} label="入金" value={fmtVal(s.total_deposit)} hint={`出金 ${fmtVal(s.total_withdraw)}`} />
                    <StatCard icon={Gift} label="体验金" value={fmtVal(s.total_experience)} hint="账户体验金" />
                  </section>
                )}

                <section className="grid gap-4 lg:grid-cols-2">
                  <Card>
                    <CardHeader className="pb-2">
                      <CardTitle className="text-sm font-medium">收益曲线（累计净收益）</CardTitle>
                      <CardDescription>绿色为盈利区、红色为亏损区，0 为基线</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <EquityChart data={stats?.equity_trend ?? []} />
                    </CardContent>
                  </Card>
                  <TradingCalendar />
                </section>

                {stats && stats.by_symbol.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2">
                      <CardTitle className="text-sm font-medium">交易品种盈亏</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <ResponsiveContainer width="100%" height={260}>
                        <BarChart data={stats.by_symbol} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
                          <CartesianGrid strokeDasharray="3 3" vertical={false} />
                          <XAxis dataKey="symbol" tick={{ fontSize: 11 }} />
                          <YAxis tick={{ fontSize: 11 }} />
                          <Tooltip />
                          <Legend wrapperStyle={{ fontSize: 12 }} />
                          <Bar dataKey="pnl" name="净盈亏" radius={[4, 4, 0, 0]}>
                            {stats.by_symbol.map((d, i) => (
                              <Cell key={i} fill={d.pnl >= 0 ? '#16a34a' : '#dc2626'} />
                            ))}
                          </Bar>
                        </BarChart>
                      </ResponsiveContainer>
                    </CardContent>
                  </Card>
                )}

                {a && (
                  <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <StatCard icon={Percent} label="平均盈利" value={a.avg_win != null ? fmtVal(a.avg_win) : '—'} />
                    <StatCard icon={Percent} label="平均亏损" value={a.avg_loss != null ? fmtVal(a.avg_loss) : '—'} />
                    <StatCard icon={TrendingUp} label="最大回撤" value={`${fmtVal(a.max_drawdown)}`} hint={`回撤幅度 ${a.max_drawdown_pct}%`} />
                    <StatCard icon={TrendingUp} label="平均持仓" value={fmtHolding(a.avg_holding_minutes)} hint={`连胜 ${a.longest_win_streak} · 连亏 ${a.longest_loss_streak}`} />
                  </section>
                )}

                {a && a.hour_dist.length > 0 && (
                  <Card>
                    <CardHeader className="pb-2">
                      <CardTitle className="text-sm font-medium">开仓时段分布（数据分析·按小时）</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <ResponsiveContainer width="100%" height={220}>
                        <BarChart data={a.hour_dist} margin={{ top: 4, right: 8, bottom: 0, left: -8 }}>
                          <CartesianGrid strokeDasharray="3 3" vertical={false} />
                          <XAxis dataKey="hour" tickFormatter={(h) => `${h}:00`} tick={{ fontSize: 11 }} />
                          <YAxis tick={{ fontSize: 11 }} />
                          <Tooltip />
                          <Bar dataKey="count" name="开仓笔数" fill="#6366f1" radius={[4, 4, 0, 0]} />
                        </BarChart>
                      </ResponsiveContainer>
                    </CardContent>
                  </Card>
                )}
              </>
            }
          />
        </TabsContent>

        <TabsContent value="funds">
          <div className="flex flex-col gap-4">
            <div className="space-y-1">
              <h1 className="font-heading text-2xl font-semibold tracking-tight">资金动态</h1>
              <p className="text-sm text-muted-foreground">记录入金 / 出金 / 体验金，构成账户净值。</p>
            </div>
            <FundsSection />
          </div>
        </TabsContent>

        <TabsContent value="position">
          <div className="flex flex-col gap-4">
            <div className="space-y-1">
              <h1 className="font-heading text-2xl font-semibold tracking-tight">仓位计算</h1>
              <p className="text-sm text-muted-foreground">多仓位杠杆并行计算：共同占用保证金，按保证金比例推演爆仓价格。</p>
            </div>
            <PositionCalculator equity={s?.account_value} />
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}