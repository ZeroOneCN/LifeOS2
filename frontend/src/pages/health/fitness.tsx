import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type FitnessRecord = {
  id: number
  record_date: string
  exercise_type: string
  duration_min: number
  calories?: number
  distance_km?: number
  note?: string
}

type FitnessStats = {
  by_type: { exercise_type: string; count: number; minutes: number; calories: number }[]
  trend: { record_date: string; count: number; minutes: number; calories: number }[]
}

const exerciseTypeLabel: Record<string, string> = {
  running: '跑步',
  walking: '步行',
  cycling: '骑行',
  swimming: '游泳',
  strength: '力量训练',
  yoga: '瑜伽',
  other: '其他',
}

const fields: FieldDef[] = [
  { key: 'record_date', label: '日期', type: 'date', required: true },
  {
    key: 'exercise_type',
    label: '运动类型',
    type: 'select',
    required: true,
    options: Object.entries(exerciseTypeLabel).map(([value, label]) => ({ value, label })),
  },
  { key: 'duration_min', label: '时长', type: 'number', required: true, placeholder: '分钟' },
  { key: 'calories', label: '消耗', type: 'number', step: '0.1', placeholder: '千卡' },
  { key: 'distance_km', label: '距离', type: 'number', step: '0.1', placeholder: '公里' },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<FitnessRecord>[] = [
  { key: 'record_date', label: '日期' },
  {
    key: 'exercise_type',
    label: '类型',
    render: (r) => exerciseTypeLabel[r.exercise_type] ?? r.exercise_type,
  },
  { key: 'duration_min', label: '时长', render: (r) => `${r.duration_min} 分钟` },
  { key: 'calories', label: '消耗', render: (r) => (r.calories ? `${r.calories} kcal` : '—') },
  { key: 'distance_km', label: '距离', render: (r) => (r.distance_km != null ? `${r.distance_km} km` : '—') },
]

export function FitnessPage() {
  const stats = useStats<FitnessStats>('/health/fitness')
  const byType = stats?.by_type ?? []
  const trend = stats?.trend ?? []

  return (
    <RecordManager<FitnessRecord>
      title="健身运动"
      description="记录每次运动的类型、时长与消耗，跟踪运动习惯。"
      apiPath="/health/fitness"
      fields={fields}
      columns={columns}
      extra={
        (byType.length > 0 || trend.length > 0) && (
          <div className="grid gap-4 lg:grid-cols-2">
            <BarChartCard
              title="运动类型分布（近 30 天）"
              data={byType.map((t) => ({ name: exerciseTypeLabel[t.exercise_type] ?? t.exercise_type, minutes: t.minutes }))}
              xKey="name"
              series={[{ key: 'minutes', name: '时长(分钟)', color: '#4f46e5' }]}
            />
            <BarChartCard
              title="每日运动消耗"
              data={trend}
              xKey="record_date"
              series={[{ key: 'calories', name: '消耗(kcal)', color: '#f59e0b' }]}
            />
          </div>
        )
      }
    />
  )
}
