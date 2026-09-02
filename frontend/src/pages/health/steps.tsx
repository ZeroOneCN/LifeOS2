import { LineChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type StepsRecord = {
  id: number
  record_date: string
  steps: number
  distance_km?: number
  calories?: number
}

type StepsStats = {
  trend: { record_date: string; steps: number; distance_km?: number; calories?: number }[]
  avg_steps?: number
  total_steps: number
  max_steps?: number
}

const fields: FieldDef[] = [
  { key: 'record_date', label: '日期', type: 'date', required: true },
  { key: 'steps', label: '步数', type: 'number', required: true, placeholder: '步' },
  { key: 'distance_km', label: '距离', type: 'number', step: '0.1', placeholder: '公里' },
  { key: 'calories', label: '消耗', type: 'number', step: '0.1', placeholder: '千卡' },
]

const columns: ColumnDef<StepsRecord>[] = [
  { key: 'record_date', label: '日期' },
  { key: 'steps', label: '步数', render: (r) => r.steps.toLocaleString() },
  { key: 'distance_km', label: '距离', render: (r) => (r.distance_km != null ? `${r.distance_km} km` : '—') },
  { key: 'calories', label: '消耗', render: (r) => (r.calories ? `${r.calories} kcal` : '—') },
]

export function StepsPage() {
  const stats = useStats<StepsStats>('/health/steps')
  const trend = stats?.trend ?? []

  return (
    <RecordManager<StepsRecord>
      title="步数统计"
      description="记录每日步数与运动消耗，观察日常活动趋势。"
      apiPath="/health/steps"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 && (
          <LineChartCard
            title="每日步数趋势"
            data={trend}
            xKey="record_date"
            series={[{ key: 'steps', name: '步数', color: '#10b981' }]}
            height={280}
          />
        )
      }
    />
  )
}
