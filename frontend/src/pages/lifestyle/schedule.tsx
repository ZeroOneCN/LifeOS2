import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type ScheduleRecord = {
  id: number
  schedule_date: string
  start_time?: string
  end_time?: string
  title: string
  location?: string
  category?: string
  note?: string
}

type ScheduleStats = {
  trend: { schedule_date: string; count: number }[]
  by_category: { category: string; count: number }[]
  total: number
}

const categories = ['工作', '运动', '家庭', '学习', '社交', '其他']

const fields: FieldDef[] = [
  { key: 'schedule_date', label: '日期', type: 'date', required: true },
  { key: 'start_time', label: '开始时间', type: 'text', placeholder: '如 09:30' },
  { key: 'end_time', label: '结束时间', type: 'text', placeholder: '如 10:30' },
  { key: 'title', label: '日程标题', type: 'text', required: true },
  { key: 'location', label: '地点', type: 'text' },
  {
    key: 'category',
    label: '分类',
    type: 'select',
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<ScheduleRecord>[] = [
  { key: 'schedule_date', label: '日期' },
  {
    key: 'time',
    label: '时间',
    render: (r) =>
      r.start_time || r.end_time ? `${r.start_time ?? '—'} ~ ${r.end_time ?? '—'}` : '—',
  },
  { key: 'title', label: '日程' },
  { key: 'location', label: '地点', render: (r) => r.location ?? '—' },
  { key: 'category', label: '分类', render: (r) => r.category ?? '—' },
]

export function SchedulePage() {
  const stats = useStats<ScheduleStats>('/lifestyle/schedule')
  const trend = stats?.trend ?? []
  const byCategory = stats?.by_category ?? []

  return (
    <RecordManager<ScheduleRecord>
      title="日程管理"
      description="安排每日行程，合理规划时间。"
      apiPath="/lifestyle/schedule"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 || byCategory.length > 0 ? (
          <div className="grid gap-4 lg:grid-cols-2">
            <LineChartCard
              title={`近30天日程数量趋势（共 ${stats?.total ?? 0} 项）`}
              data={trend}
              xKey="schedule_date"
              series={[{ key: 'count', name: '日程数', color: '#8b5cf6' }]}
            />
            <BarChartCard
              title="日程分类分布"
              data={byCategory}
              xKey="category"
              series={[{ key: 'count', name: '数量', color: '#10b981' }]}
            />
          </div>
        ) : null
      }
    />
  )
}
