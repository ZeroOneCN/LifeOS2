import { Badge } from '@/components/ui/badge'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type ItemRecord = {
  id: number
  item_name: string
  category: string
  location?: string
  status: 'in_use' | 'lost' | 'loaned' | 'recycled'
  purchase_date?: string
  price?: number
  note?: string
}

type ItemStats = {
  total: number
  by_category: { category: string; count: number }[]
  by_status: { status: string; count: number }[]
}

const categories = ['电子', '服饰', '书籍', '家居', '数码配件', '其他']

const fields: FieldDef[] = [
  { key: 'item_name', label: '物品名称', type: 'text', required: true },
  {
    key: 'category',
    label: '分类',
    type: 'select',
    required: true,
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'location', label: '存放位置', type: 'text', placeholder: '如 书房 / 卧室' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'in_use', label: '使用中' },
      { value: 'loaned', label: '借出' },
      { value: 'lost', label: '丢失' },
      { value: 'recycled', label: '已淘汰' },
    ],
  },
  { key: 'purchase_date', label: '购买日期', type: 'date' },
  { key: 'price', label: '价格', type: 'number', step: '0.01', min: 0 },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const statusMeta: Record<string, { label: string; className: string }> = {
  in_use: { label: '使用中', className: 'bg-green-100 text-green-700' },
  loaned: { label: '借出', className: 'bg-blue-100 text-blue-700' },
  lost: { label: '丢失', className: 'bg-red-100 text-red-700' },
  recycled: { label: '已淘汰', className: 'bg-gray-100 text-gray-500' },
}

const columns: ColumnDef<ItemRecord>[] = [
  { key: 'item_name', label: '物品' },
  { key: 'category', label: '分类' },
  { key: 'location', label: '位置', render: (r) => r.location ?? '—' },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={statusMeta[r.status]?.className}>{statusMeta[r.status]?.label ?? r.status}</Badge>
    ),
  },
  { key: 'purchase_date', label: '购买日期', render: (r) => r.purchase_date ?? '—' },
  {
    key: 'price',
    label: '价格',
    render: (r) =>
      r.price != null ? `¥${r.price.toLocaleString(undefined, { minimumFractionDigits: 2 })}` : '—',
  },
]

export function ItemsPage() {
  const stats = useStats<ItemStats>('/lifestyle/items')
  const byCategory = stats?.by_category ?? []
  const byStatus = stats?.by_status ?? []

  return (
    <RecordManager<ItemRecord>
      title="物品追踪"
      description="登记个人物品，记录存放位置与状态。"
      apiPath="/lifestyle/items"
      fields={fields}
      columns={columns}
      extra={
        byCategory.length > 0 || byStatus.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <BarChartCard
              title={`物品分类统计（共 ${stats?.total ?? 0} 件）`}
              data={byCategory}
              xKey="category"
              series={[{ key: 'count', name: '数量', color: '#6366f1' }]}
            />
            <BarChartCard
              title="物品状态分布"
              data={byStatus}
              xKey="status"
              series={[{ key: 'count', name: '数量', color: '#f59e0b' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
