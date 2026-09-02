import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type PurchaseRecord = {
  id: number
  purchase_date: string
  item_name: string
  category: string
  amount: number
  quantity?: number
  store?: string
  note?: string
}

type PurchaseStats = {
  trend: { purchase_date: string; amount: number }[]
  by_category: { category: string; amount: number }[]
  total: number
  count: number
}

const categories = ['餐饮', '日用', '交通', '服饰', '数码', '娱乐', '家居', '其他']

const fields: FieldDef[] = [
  { key: 'purchase_date', label: '购买日期', type: 'date', required: true },
  { key: 'item_name', label: '商品名称', type: 'text', required: true },
  {
    key: 'category',
    label: '分类',
    type: 'select',
    required: true,
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'amount', label: '金额', type: 'number', required: true, step: '0.01', min: 0 },
  { key: 'quantity', label: '数量', type: 'number', min: 1 },
  { key: 'store', label: '购买渠道', type: 'text', placeholder: '如 淘宝 / 超市' },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<PurchaseRecord>[] = [
  { key: 'purchase_date', label: '日期' },
  { key: 'item_name', label: '商品' },
  { key: 'category', label: '分类' },
  {
    key: 'amount',
    label: '金额',
    render: (r) => `¥${r.amount.toLocaleString(undefined, { minimumFractionDigits: 2 })}`,
  },
  { key: 'quantity', label: '数量', render: (r) => (r.quantity ? `×${r.quantity}` : '—') },
  { key: 'store', label: '渠道', render: (r) => r.store ?? '—' },
]

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

export function PurchasesPage() {
  const stats = useStats<PurchaseStats>('/finance/purchases')
  const trend = stats?.trend ?? []
  const byCategory = stats?.by_category ?? []

  return (
    <RecordManager<PurchaseRecord>
      title="购买记录"
      description="记录日常消费支出，掌握每笔花费去向。"
      apiPath="/finance/purchases"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 || byCategory.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <LineChartCard
              title={`支出趋势（近30天 · 合计 ${stats ? fmt(stats.total) : ''}）`}
              data={trend}
              xKey="purchase_date"
              series={[{ key: 'amount', name: '金额', color: '#4f46e5' }]}
            />
            <BarChartCard
              title="分类支出占比"
              data={byCategory}
              xKey="category"
              series={[{ key: 'amount', name: '金额', color: '#f59e0b' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
