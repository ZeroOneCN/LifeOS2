import { useState } from 'react'
import {
  BarChartCard,
  LineChartCard,
  StatsPeriodPicker,
  setGlobalStatsDays,
  useStats,
  type StatsDays,
} from '@/components/health/charts'
import { Card, CardContent } from '@/components/ui/card'
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
    blood_oxygen?: number
    blood_glucose?: number
    body_temp?: number
    sleep_duration_min?: number
    deep_sleep_min?: number
    light_sleep_min?: number
    wake_count?: number
    sleep_quality?: number
  }[]
  avg?: {
    blood_pressure_high?: number
    blood_pressure_low?: number
    heart_rate?: number
    blood_oxygen?: number
    blood_glucose?: number
    body_temp?: number
    sleep_duration_min?: number
    deep_sleep_min?: number
    sleep_quality?: number
  }
  record_count?: number
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
    render: (r) => {
      if (r.sleep_duration_min == null) return '—'
      const total = Math.round(r.sleep_duration_min)
      return `${Math.floor(total / 60)}h${total % 60}m`
    },
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
  {
    key: 'deep_sleep_min',
    label: '深睡',
    render: (r) => (r.deep_sleep_min != null ? `${r.deep_sleep_min}m` : '—'),
  },
  {
    key: 'light_sleep_min',
    label: '浅睡',
    render: (r) => (r.light_sleep_min != null ? `${r.light_sleep_min}m` : '—'),
  },
  {
    key: 'wake_count',
    label: '醒来',
    render: (r) => (r.wake_count != null ? `${r.wake_count} 次` : '—'),
  },
  {
    key: 'sleep_quality',
    label: '质量',
    render: (r) => (r.sleep_quality != null ? `${r.sleep_quality}/10` : '—'),
  },
]

export function VitalsSleepPage() {
  const [days, setDays] = useState<StatsDays>(7)
  const stats = useStats<VitalsStats>('/health/vitals-sleep', days)
  const trend = stats?.trend ?? []
  const avg = stats?.avg

  const fmtSleep = (m?: number) => {
    if (m == null) return '—'
    const total = Math.round(m)
    return `${Math.floor(total / 60)}h${total % 60}m`
  }
  const fmt = (v?: number, unit = '') => (v != null ? `${v}${unit}` : '—')

  const periodPicker = (
    <div className="flex justify-end">
      <StatsPeriodPicker
        value={days}
        onChange={(d) => {
          setDays(d)
          setGlobalStatsDays(d)
        }}
      />
    </div>
  )

  return (
    <RecordManager<VitalsRecord>
      title="睡眠体征"
      description="记录每日生命体征（血压、心率、血氧等）与睡眠质量。"
      apiPath="/health/vitals-sleep"
      fields={fields}
      columns={columns}
      extra={
        <>
          {periodPicker}
          <div className="grid gap-4 md:grid-cols-4">
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">统计天数</div>
                  <div className="mt-1 text-2xl font-semibold">{stats?.record_count ?? 0} 天</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均睡眠</div>
                  <div className="mt-1 text-2xl font-semibold">{fmtSleep(avg?.sleep_duration_min)}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均心率</div>
                  <div className="mt-1 text-2xl font-semibold text-rose-600">{fmt(avg?.heart_rate, ' bpm')}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均血氧</div>
                  <div className="mt-1 text-2xl font-semibold text-emerald-600">{fmt(avg?.blood_oxygen, '%')}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均体温</div>
                  <div className="mt-1 text-2xl font-semibold text-orange-600">{fmt(avg?.body_temp, '℃')}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均血糖</div>
                  <div className="mt-1 text-2xl font-semibold text-sky-600">{fmt(avg?.blood_glucose, ' mmol/L')}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均血压</div>
                  <div className="mt-1 text-2xl font-semibold">
                    {avg?.blood_pressure_high != null && avg.blood_pressure_low != null
                      ? `${avg.blood_pressure_high}/${avg.blood_pressure_low}`
                      : '—'}
                  </div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均睡眠质量</div>
                  <div className="mt-1 text-2xl font-semibold text-violet-600">{fmt(avg?.sleep_quality, ' 分')}</div>
                </CardContent>
              </Card>
            </div>

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
                title="心率趋势"
                data={trend}
                xKey="record_date"
                series={[{ key: 'heart_rate', name: '心率(bpm)', color: '#f43f5e' }]}
              />
              <LineChartCard
                title="血氧 / 体温趋势"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'blood_oxygen', name: '血氧(%)', color: '#10b981' },
                  { key: 'body_temp', name: '体温(℃)', color: '#f59e0b' },
                ]}
              />
              <LineChartCard
                title="血糖趋势"
                data={trend}
                xKey="record_date"
                series={[{ key: 'blood_glucose', name: '血糖(mmol/L)', color: '#0ea5e9' }]}
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
              <BarChartCard
                title="深睡 / 浅睡时长"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'deep_sleep_min', name: '深睡(分钟)', color: '#3b82f6' },
                  { key: 'light_sleep_min', name: '浅睡(分钟)', color: '#f59e0b' },
                ]}
              />
            </div>
        </>
      }
    />
  )
}
