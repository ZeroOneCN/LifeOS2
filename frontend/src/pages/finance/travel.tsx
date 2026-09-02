import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type TravelRecord = {
  id: number
  expense_date: string
  trip_name: string
  category: string
  amount: number
  note?: string
}

type TravelStats = {
  trend: { expense_date: string; amount: number }[]
  by_category: { category: string; amount: number }[]
  total: number
  count: number
}

const categories = ['交通', '住宿', '餐饮', '门票', '购物', '其他']

const fields: FieldDef[] = [
  { key: 'expense_date', label: '日期', type: 'date', required: true },
  { key: 'trip_name', label: '行程名称', type: 'text', required: true, placeholder: '如 五一上海游' },
  {
    key: 'category',
    label: '分类',
    type: 'select',
    required: true,
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'amount', label: '金额', type: 'number', required: true, step: '0.01', min: 0 },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<TravelRecord>[] = [
  { key: 'expense_date', label: '日期' },
  { key: 'trip_name', label: '行程' },
  { key: 'category', label: '分类' },
  {
    key: 'amount',
    label: '金额',
    render: (r) => `¥${r.amount.toLocaleString(undefined, { minimumFractionDigits: 2 })}`,
  },
]

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

export function TravelPage() {
  const stats = useStats<TravelStats>('/finance/travel')
  const trend = stats?.trend ?? []
  const byCategory = stats?.by_category ?? []

  return (
    <RecordManager<TravelRecord>
      title="旅行开支"
      description="记录旅行中的各项费用，合理规划出行预算。"
      apiPath="/finance/travel"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 || byCategory.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <LineChartCard
              title={`旅行支出趋势（近30天 · 合计 ${stats ? fmt(stats.total) : ''}）`}
              data={trend}
              xKey="expense_date"
              series={[{ key: 'amount', name: '金额', color: '#0ea5e9' }]}
            />
            <BarChartCard
              title="开支分类分布"
              data={byCategory}
              xKey="category"
              series={[{ key: 'amount', name: '金额', color: '#14b8a6' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
