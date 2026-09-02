import {
  LineChartCard,
  useStats,
} from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type VitalsRecord = {
  id: number
  record_date: string
  blood_pressure_high?: number
  blood_pressure_low?: number
  heart_rate?: number
  blood_oxygen?: number
  blood_glucose?: number
  body_temp?: number
  bedtime?: string
  wake_time?: string
  sleep_duration_min?: number
  deep_sleep_min?: number
  light_sleep_min?: number
  wake_count?: number
  sleep_quality?: number
  note?: string
}

type VitalsStats = {
  trend: {
    record_date: string
    blood_pressure_high?: number
    blood_pressure_low?: number
    heart_rate?: number
    blood_glucose?: number
    body_temp?: number
    sleep_duration_min?: number
    deep_sleep_min?: number
    sleep_quality?: number
  }[]
}

const fields: FieldDef[] = [
  { key: 'record_date', label: '日期', type: 'date', required: true },
  { key: 'bedtime', label: '睡觉时间', type: 'time', placeholder: '如 23:00' },
  { key: 'wake_time', label: '起床时间', type: 'time', placeholder: '如 07:30' },
  { key: 'blood_pressure_high', label: '血压-高压', type: 'number', placeholder: 'mmHg' },
  { key: 'blood_pressure_low', label: '血压-低压', type: 'number', placeholder: 'mmHg' },
  { key: 'heart_rate', label: '心率', type: 'number', placeholder: 'bpm' },
  { key: 'blood_oxygen', label: '血氧', type: 'number', step: '0.1', placeholder: '%' },
  { key: 'blood_glucose', label: '血糖', type: 'number', step: '0.1', placeholder: 'mmol/L' },
  { key: 'body_temp', label: '体温', type: 'number', step: '0.1', placeholder: '℃' },
  { key: 'deep_sleep_min', label: '深睡时长', type: 'number', placeholder: '分钟' },
  { key: 'light_sleep_min', label: '浅睡时长', type: 'number', placeholder: '分钟' },
  { key: 'wake_count', label: '醒来次数', type: 'number' },
  {
    key: 'sleep_quality',
    label: '睡眠质量',
    type: 'select',
    options: Array.from({ length: 10 }, (_, i) => ({
      value: String(i + 1),
      label: `${i + 1} 分`,
    })),
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<VitalsRecord>[] = [
  { key: 'record_date', label: '日期' },
  {
    key: 'sleep',
    label: '睡眠时段',
    render: (r) =>
      r.bedtime && r.wake_time ? `${r.bedtime.slice(0, 5)} - ${r.wake_time.slice(0, 5)}` : '—',
  },
  {
    key: 'sleep_duration_min',
    label: '睡眠',
    render: (r) =>
      r.sleep_duration_min != null
        ? `${Math.floor(r.sleep_duration_min / 60)}h${r.sleep_duration_min % 60}m`
        : '—',
  },
  {
    key: 'bp',
    label: '血压',
    render: (r) =>
      r.blood_pressure_high && r.blood_pressure_low
        ? `${r.blood_pressure_high}/${r.blood_pressure_low}`
        : '—',
  },
  { key: 'heart_rate', label: '心率', render: (r) => (r.heart_rate ? `${r.heart_rate} bpm` : '—') },
  { key: 'blood_oxygen', label: '血氧', render: (r) => (r.blood_oxygen ? `${r.blood_oxygen}%` : '—') },
  { key: 'blood_glucose', label: '血糖', render: (r) => (r.blood_glucose ? `${r.blood_glucose}` : '—') },
  { key: 'body_temp', label: '体温', render: (r) => (r.body_temp ? `${r.body_temp}℃` : '—') },
  { key: 'sleep_quality', label: '质量', render: (r) => (r.sleep_quality ? `${r.sleep_quality}/10` : '—') },
]

export function VitalsSleepPage() {
  const stats = useStats<VitalsStats>('/health/vitals-sleep')
  const trend = stats?.trend ?? []

  return (
    <RecordManager<VitalsRecord>
      title="睡眠体征"
      description="记录每日生命体征（血压、心率、血氧等）与睡眠质量。"
      apiPath="/health/vitals-sleep"
      fields={fields}
      columns={columns}
      extra={
        trend.length > 0 && (
          <div className="grid gap-4 lg:grid-cols-2">
            <LineChartCard
              title="血压趋势"
              data={trend}
              xKey="record_date"
              series={[
                { key: 'blood_pressure_high', name: '高压', color: '#ef4444' },
                { key: 'blood_pressure_low', name: '低压', color: '#3b82f6' },
              ]}
            />
            <LineChartCard
              title="睡眠时长与质量"
              data={trend}
              xKey="record_date"
              series={[
                { key: 'sleep_duration_min', name: '时长(分钟)', color: '#8b5cf6' },
                { key: 'sleep_quality', name: '质量(分)', color: '#10b981' },
              ]}
            />
          </div>
        )
      }
    />
  )
}
