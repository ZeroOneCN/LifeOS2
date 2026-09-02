import {
  AlertTriangle,
  ArrowDownCircle,
  ArrowUpCircle,
  HandCoins,
  Wallet,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type DebtRecord = {
  id: number
  debt_date: string
  name: string
  direction: 'lend' | 'borrow'
  counterparty?: string
  amount: number
  remaining?: number
  interest_rate?: number
  due_date?: string
  status: 'active' | 'settled'
  note?: string
}

type DebtStats = {
  total: number
  active: number
  settled: number
  borrow_total: number
  lend_total: number
  outstanding: number
  overdue: number
  by_direction: { direction: string; label: string; amount: number }[]
  by_status: { status: string; label: string; count: number }[]
  overdue_list: {
    name: string
    counterparty?: string
    direction: string
    remaining: number
    due_date?: string
  }[]
}

const directionMeta: Record<string, { label: string; className: string }> = {
  lend: { label: '借出', className: 'bg-blue-100 text-blue-700' },
  borrow: { label: '借入', className: 'bg-amber-100 text-amber-700' },
}

const statusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '进行中', className: 'bg-blue-100 text-blue-700' },
  settled: { label: '已结清', className: 'bg-green-100 text-green-700' },
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const fields: FieldDef[] = [
  { key: 'debt_date', label: '日期', type: 'date', required: true },
  { key: 'name', label: '债务名称', type: 'text', required: true, placeholder: '如 朋友借款 / 房贷' },
  {
    key: 'direction',
    label: '方向',
    type: 'select',
    required: true,
    options: [
      { value: 'lend', label: '借出（应收）' },
      { value: 'borrow', label: '借入（应付）' },
    ],
  },
  { key: 'counterparty', label: '对方', type: 'text', placeholder: '借款人 / 债权人' },
  { key: 'amount', label: '总金额', type: 'number', step: '0.01', min: 0, required: true },
  { key: 'remaining', label: '剩余金额', type: 'number', step: '0.01', min: 0 },
  { key: 'interest_rate', label: '年利率(%)', type: 'number', step: '0.01', min: 0 },
  { key: 'due_date', label: '到期日', type: 'date' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'active', label: '进行中' },
      { value: 'settled', label: '已结清' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<DebtRecord>[] = [
  { key: 'debt_date', label: '日期' },
  { key: 'name', label: '名称' },
  {
    key: 'direction',
    label: '方向',
    render: (r) => (
      <Badge className={directionMeta[r.direction]?.className}>
        {directionMeta[r.direction]?.label ?? r.direction}
      </Badge>
    ),
  },
  { key: 'counterparty', label: '对方', render: (r) => r.counterparty ?? '—' },
  { key: 'amount', label: '总金额', render: (r) => fmt(r.amount) },
  {
    key: 'remaining',
    label: '剩余',
    render: (r) => (r.remaining != null ? fmt(r.remaining) : '—'),
  },
  {
    key: 'interest_rate',
    label: '利率',
    render: (r) => (r.interest_rate != null ? `${r.interest_rate}%` : '—'),
  },
  { key: 'due_date', label: '到期', render: (r) => r.due_date ?? '—' },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={statusMeta[r.status]?.className}>
        {statusMeta[r.status]?.label ?? r.status}
      </Badge>
    ),
  },
]

function StatChip({
  icon: Icon,
  label,
  value,
  className,
}: {
  icon: typeof Wallet
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

export function DebtsPage() {
  const stats = useStats<DebtStats>('/finance/debts')

  return (
    <RecordManager<DebtRecord>
      title="债务管理"
      description="追踪借出与借入款项，掌握应收应付与逾期情况。"
      apiPath="/finance/debts"
      fields={fields}
      columns={columns}
      extra={
        stats ? (
          <div className="flex flex-col gap-4">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <StatChip icon={Wallet} label="债务总数" value={String(stats.total)} />
              <StatChip
                icon={ArrowDownCircle}
                label="借出应收"
                value={fmt(stats.lend_total)}
                className="text-blue-500"
              />
              <StatChip
                icon={ArrowUpCircle}
                label="借入应付"
                value={fmt(stats.borrow_total)}
                className="text-amber-500"
              />
              <StatChip
                icon={HandCoins}
                label="未结清余额"
                value={fmt(stats.outstanding)}
                className="text-indigo-500"
              />
            </div>

            {stats.overdue > 0 && (
              <Card className="border-red-200 bg-red-50">
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-sm font-medium text-red-700">
                    <AlertTriangle className="size-4" />
                    已逾期 {stats.overdue} 笔待处理
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-1.5 text-sm">
                  {stats.overdue_list.map((o, i) => (
                    <div
                      key={i}
                      className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-white/70 px-3 py-1.5"
                    >
                      <span>
                        {o.name}
                        {o.counterparty ? `（${o.counterparty}）` : ''}
                        <Badge className={`ml-2 ${directionMeta[o.direction]?.className}`}>
                          {directionMeta[o.direction]?.label ?? o.direction}
                        </Badge>
                      </span>
                      <span className="text-muted-foreground">
                        到期 {o.due_date ?? '—'} · 剩余{' '}
                        <span className="font-medium text-red-700">{fmt(o.remaining)}</span>
                      </span>
                    </div>
                  ))}
                </CardContent>
              </Card>
            )}

            <div className="grid gap-4 lg:grid-cols-2">
              <BarChartCard
                title="借出 / 借入金额对比"
                data={stats.by_direction}
                xKey="label"
                series={[{ key: 'amount', name: '金额', color: '#4f46e5' }]}
              />
              <BarChartCard
                title="债务状态分布"
                data={stats.by_status}
                xKey="label"
                series={[{ key: 'count', name: '笔数', color: '#10b981' }]}
              />
            </div>
          </div>
        ) : null
      }
    />
  )
}
