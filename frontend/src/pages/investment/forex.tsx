import { Badge } from '@/components/ui/badge'
import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type ForexRecord = {
  id: number
  trade_date: string
  pair: string
  direction: 'buy' | 'sell'
  open_price: number
  close_price?: number
  lot_size: number
  pnl?: number
  status: 'open' | 'closed'
  note?: string
}

type ForexStats = {
  total: number
  closed: number
  open: number
  total_pnl: number
  win_rate?: number
  trend: { trade_date: string; pnl: number }[]
  by_pair: { pair: string; pnl: number }[]
}

const pairs = ['EUR/USD', 'USD/JPY', 'GBP/USD', 'USD/CHF', 'AUD/USD', 'USD/CAD', 'NZD/USD']

const fields: FieldDef[] = [
  { key: 'trade_date', label: '交易日期', type: 'date', required: true },
  {
    key: 'pair',
    label: '货币对',
    type: 'select',
    required: true,
    options: pairs.map((p) => ({ value: p, label: p })),
  },
  {
    key: 'direction',
    label: '方向',
    type: 'select',
    required: true,
    options: [
      { value: 'buy', label: '做多 Buy' },
      { value: 'sell', label: '做空 Sell' },
    ],
  },
  { key: 'open_price', label: '开仓价', type: 'number', required: true, step: '0.0001', min: 0 },
  { key: 'close_price', label: '平仓价', type: 'number', step: '0.0001', min: 0 },
  { key: 'lot_size', label: '手数', type: 'number', required: true, step: '0.01', min: 0 },
  { key: 'pnl', label: '盈亏', type: 'number', step: '0.01' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'closed', label: '已平仓' },
      { value: 'open', label: '持仓中' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const fmtPnl = (n: number) =>
  `${n >= 0 ? '+' : ''}${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const columns: ColumnDef<ForexRecord>[] = [
  { key: 'trade_date', label: '日期' },
  { key: 'pair', label: '货币对' },
  {
    key: 'direction',
    label: '方向',
    render: (r) =>
      r.direction === 'buy' ? (
        <Badge className="bg-green-100 text-green-700">多</Badge>
      ) : (
        <Badge className="bg-red-100 text-red-700">空</Badge>
      ),
  },
  {
    key: 'price',
    label: '开/平仓价',
    render: (r) => `${r.open_price} → ${r.close_price ?? '—'}`,
  },
  { key: 'lot_size', label: '手数' },
  {
    key: 'pnl',
    label: '盈亏',
    render: (r) =>
      r.pnl != null ? (
        <span className={r.pnl >= 0 ? 'font-medium text-green-600' : 'font-medium text-red-600'}>
          {fmtPnl(r.pnl)}
        </span>
      ) : (
        '—'
      ),
  },
  {
    key: 'status',
    label: '状态',
    render: (r) =>
      r.status === 'closed' ? (
        <Badge className="bg-gray-100 text-gray-600">已平仓</Badge>
      ) : (
        <Badge className="bg-blue-100 text-blue-700">持仓中</Badge>
      ),
  },
]

export function ForexPage() {
  const stats = useStats<ForexStats>('/investment/forex')
  const trend = stats?.trend ?? []
  const byPair = stats?.by_pair ?? []

  return (
    <RecordManager<ForexRecord>
      title="外汇交易"
      description="记录外汇交易明细，追踪盈亏与交易表现。"
      apiPath="/investment/forex"
      fields={fields}
      columns={columns}
      extra={
        stats ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="grid gap-4 sm:grid-cols-2">
              <LineChartCard
                title={`累计盈亏 ${fmtPnl(stats.total_pnl)}（近30天）`}
                data={trend}
                xKey="trade_date"
                series={[{ key: 'pnl', name: '盈亏', color: '#4f46e5' }]}
              />
              <BarChartCard
                title={`胜率 ${stats.win_rate ?? 0}% · 交易 ${stats.total} 笔（持仓 ${stats.open}）`}
                data={byPair}
                xKey="pair"
                series={[{ key: 'pnl', name: '盈亏', color: '#0ea5e9' }]}
              />
            </div>
          </div>
        ) : null
      }
    />
  )
}
