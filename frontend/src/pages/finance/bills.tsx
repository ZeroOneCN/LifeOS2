import { Badge } from '@/components/ui/badge'
import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type BillRecord = {
  id: number
  bill_date: string
  bill_type: string
  amount: number
  due_date?: string
  paid: boolean
  note?: string
}

type BillStats = {
  trend: { bill_date: string; amount: number }[]
  by_type: { bill_type: string; amount: number }[]
  total: number
  unpaid: number
  unpaid_count: number
}

const billTypes = ['水费', '电费', '燃气费', '话费', '网络', '物业费', '其他']

const fields: FieldDef[] = [
  { key: 'bill_date', label: '出账日期', type: 'date', required: true },
  {
    key: 'bill_type',
    label: '账单类型',
    type: 'select',
    required: true,
    options: billTypes.map((c) => ({ value: c, label: c })),
  },
  { key: 'amount', label: '金额', type: 'number', required: true, step: '0.01', min: 0 },
  { key: 'due_date', label: '到期日', type: 'date' },
  { key: 'paid', label: '是否已支付', type: 'boolean', options: [{ value: 'true', label: '已支付' }, { value: 'false', label: '未支付' }] },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<BillRecord>[] = [
  { key: 'bill_date', label: '出账日期' },
  { key: 'bill_type', label: '类型' },
  {
    key: 'amount',
    label: '金额',
    render: (r) => `¥${r.amount.toLocaleString(undefined, { minimumFractionDigits: 2 })}`,
  },
  { key: 'due_date', label: '到期日', render: (r) => r.due_date ?? '—' },
  {
    key: 'paid',
    label: '状态',
    render: (r) =>
      r.paid ? (
        <Badge className="bg-green-100 text-green-700">已支付</Badge>
      ) : (
        <Badge className="bg-amber-100 text-amber-700">待支付</Badge>
      ),
  },
]

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

export function BillsPage() {
  const stats = useStats<BillStats>('/finance/bills')
  const trend = stats?.trend ?? []
  const byType = stats?.by_type ?? []

  return (
    <RecordManager<BillRecord>
      title="账单管理"
      description="管理水、电、燃气等生活账单，掌握缴费情况。"
      apiPath="/finance/bills"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 || byType.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <LineChartCard
              title={`账单金额趋势（近30天 · 合计 ${stats ? fmt(stats.total) : ''}）`}
              data={trend}
              xKey="bill_date"
              series={[{ key: 'amount', name: '金额', color: '#8b5cf6' }]}
            />
            <BarChartCard
              title="账单类型分布"
              data={byType}
              xKey="bill_type"
              series={[{ key: 'amount', name: '金额', color: '#ec4899' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
