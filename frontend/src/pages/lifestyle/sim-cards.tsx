import { Badge } from '@/components/ui/badge'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type SimCardRecord = {
  id: number
  card_name: string
  card_type: string
  card_number?: string
  balance?: number
  expire_date?: string
  status: 'active' | 'frozen' | 'expired'
  note?: string
}

type SimCardStats = {
  total: number
  balance_total: number
  by_type: { card_type: string; count: number }[]
  by_status: { status: string; count: number }[]
}

const cardTypes = ['手机卡', '银行卡', '会员卡', '门禁卡', '公交卡', '其他']

const fields: FieldDef[] = [
  { key: 'card_name', label: '卡片名称', type: 'text', required: true },
  {
    key: 'card_type',
    label: '类型',
    type: 'select',
    required: true,
    options: cardTypes.map((c) => ({ value: c, label: c })),
  },
  { key: 'card_number', label: '卡号', type: 'text', placeholder: '可填写部分号码' },
  { key: 'balance', label: '余额', type: 'number', step: '0.01', min: 0 },
  { key: 'expire_date', label: '到期日', type: 'date' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'active', label: '正常' },
      { value: 'frozen', label: '冻结' },
      { value: 'expired', label: '已过期' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const statusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '正常', className: 'bg-green-100 text-green-700' },
  frozen: { label: '冻结', className: 'bg-amber-100 text-amber-700' },
  expired: { label: '已过期', className: 'bg-red-100 text-red-700' },
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const columns: ColumnDef<SimCardRecord>[] = [
  { key: 'card_name', label: '名称' },
  { key: 'card_type', label: '类型' },
  { key: 'card_number', label: '卡号', render: (r) => r.card_number ?? '—' },
  {
    key: 'balance',
    label: '余额',
    render: (r) => (r.balance != null ? fmt(r.balance) : '—'),
  },
  { key: 'expire_date', label: '到期日', render: (r) => r.expire_date ?? '—' },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={statusMeta[r.status]?.className}>{statusMeta[r.status]?.label ?? r.status}</Badge>
    ),
  },
]

export function SimCardsPage() {
  const stats = useStats<SimCardStats>('/lifestyle/sim-cards')
  const byType = stats?.by_type ?? []
  const byStatus = stats?.by_status ?? []

  return (
    <RecordManager<SimCardRecord>
      title="卡片管理"
      description="集中管理手机卡、银行卡等各类卡片信息。"
      apiPath="/lifestyle/sim-cards"
      fields={fields}
      columns={columns}
      extra={
        byType.length > 0 || byStatus.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <BarChartCard
              title={`卡片类型统计（${stats?.total ?? 0} 张 · 余额合计 ${stats ? fmt(stats.balance_total) : ''}）`}
              data={byType}
              xKey="card_type"
              series={[{ key: 'count', name: '数量', color: '#0ea5e9' }]}
            />
            <BarChartCard
              title="卡片状态分布"
              data={byStatus}
              xKey="status"
              series={[{ key: 'count', name: '数量', color: '#14b8a6' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
