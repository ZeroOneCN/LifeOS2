import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { BarChartCard, StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type PlanRecord = {
  id: number
  plan_date: string
  plan_type: string
  title: string
  target_amount?: number
  saved_amount?: number
  status: 'active' | 'done' | 'abandoned'
  note?: string
}

type PlanStats = {
  total: number
  active: number
  done: number
  target_total: number
  saved_total: number
  by_type: { plan_type: string; count: number; amount: number }[]
}

const planTypes = ['储蓄', '预算', '投资', '目标']

const fields: FieldDef[] = [
  { key: 'plan_date', label: '规划日期', type: 'date', required: true },
  {
    key: 'plan_type',
    label: '类型',
    type: 'select',
    required: true,
    options: planTypes.map((c) => ({ value: c, label: c })),
  },
  { key: 'title', label: '目标名称', type: 'text', required: true, placeholder: '如 年度储蓄计划' },
  { key: 'target_amount', label: '目标金额', type: 'number', step: '0.01', min: 0 },
  { key: 'saved_amount', label: '已存金额', type: 'number', step: '0.01', min: 0 },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'active', label: '进行中' },
      { value: 'done', label: '已完成' },
      { value: 'abandoned', label: '已放弃' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const statusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '进行中', className: 'bg-blue-100 text-blue-700' },
  done: { label: '已完成', className: 'bg-green-100 text-green-700' },
  abandoned: { label: '已放弃', className: 'bg-gray-100 text-gray-500' },
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const columns: ColumnDef<PlanRecord>[] = [
  { key: 'plan_date', label: '日期' },
  { key: 'plan_type', label: '类型' },
  { key: 'title', label: '目标' },
  {
    key: 'target_amount',
    label: '目标金额',
    render: (r) => (r.target_amount != null ? fmt(r.target_amount) : '—'),
  },
  {
    key: 'progress',
    label: '进度',
    render: (r) => {
      if (r.target_amount == null || r.saved_amount == null || r.target_amount === 0) return '—'
      const pct = Math.min(100, Math.round((r.saved_amount / r.target_amount) * 100))
      return (
        <div className="flex items-center gap-2">
          <div className="h-1.5 w-20 overflow-hidden rounded-full bg-muted">
            <div className="h-full rounded-full bg-indigo-500" style={{ width: `${pct}%` }} />
          </div>
          <span className="text-xs text-muted-foreground">{pct}%</span>
        </div>
      )
    },
  },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={statusMeta[r.status]?.className}>{statusMeta[r.status]?.label ?? r.status}</Badge>
    ),
  },
]

export function PlanningPage() {
  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const stats = useStats<PlanStats>('/finance/planning', days)
  const byType = stats?.by_type ?? []

  return (
    <RecordManager<PlanRecord>
      title="财务规划"
      description="制定储蓄、预算与投资目标，追踪达成进度。"
      apiPath="/finance/planning"
      fields={fields}
      columns={columns}
      extra={
        <>
          <div className="flex justify-end">
            <StatsPeriodPicker
              value={days}
              onChange={(d) => {
                setDays(d)
                setGlobalStatsDays(d)
              }}
            />
          </div>
          <BarChartCard
            title={`各类型已存金额（已存合计 ${stats ? fmt(stats.saved_total) : ''}）`}
            data={byType}
            xKey="plan_type"
            series={[{ key: 'amount', name: '已存金额', color: '#10b981' }]}
          />
        </>
      }
    />
  )
}
