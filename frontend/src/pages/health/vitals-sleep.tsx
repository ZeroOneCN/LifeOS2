import { useState } from 'react'
import {
  BarChartCard,
  LineChartCard,
} from '@/components/health/charts'
import {
  StatsPeriodPicker,
  setGlobalStatsDays,
  useStats,
  type StatsDays,
} from '@/components/health/chart-utils'
import { Card, CardContent } from '@/components/ui/card'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'
import { DASH, formatDecimal, formatDuration, formatInt, formatPercent } from '@/lib/format'

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
    hr_min?: number
    hr_max?: number
    hr_avg?: number
    hr_samples?: number
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

/** 本页整列无采集值时隐藏（null / 0 均视为未采集），避免空列占宽 */
const blank = (key: keyof VitalsRecord) => (rows: VitalsRecord[]) =>
  rows.length > 0 && rows.every((r) => r[key] == null || r[key] === 0)

const columns: ColumnDef<VitalsRecord>[] = [
  { key: 'record_date', label: '日期' },
  {
    key: 'sleep',
    label: '睡眠时段',
    hidden: (rows) => rows.length > 0 && rows.every((r) => !(r.bedtime && r.wake_time)),
    render: (r) =>
      r.bedtime && r.wake_time ? `${r.bedtime.slice(0, 5)} - ${r.wake_time.slice(0, 5)}` : '—',
  },
  {
    key: 'sleep_duration_min',
    label: '睡眠',
    hidden: blank('sleep_duration_min'),
    render: (r) => formatDuration(r.sleep_duration_min),
  },
  {
    key: 'bp',
    label: '血压',
    hidden: (rows) =>
      rows.length > 0 && rows.every((r) => !(r.blood_pressure_high && r.blood_pressure_low)),
    render: (r) =>
      r.blood_pressure_high && r.blood_pressure_low
        ? `${r.blood_pressure_high}/${r.blood_pressure_low}`
        : '—',
  },
  {
    key: 'heart_rate',
    label: '心率',
    hidden: blank('heart_rate'),
    render: (r) => (r.heart_rate ? `${formatInt(r.heart_rate)} bpm` : DASH),
  },
  {
    key: 'blood_oxygen',
    label: '血氧',
    hidden: blank('blood_oxygen'),
    render: (r) => (r.blood_oxygen ? formatPercent(r.blood_oxygen) : DASH),
  },
  {
    key: 'blood_glucose',
    label: '血糖',
    hidden: blank('blood_glucose'),
    render: (r) => (r.blood_glucose ? `${formatDecimal(r.blood_glucose, 1)} mmol/L` : DASH),
  },
  {
    key: 'body_temp',
    label: '体温',
    hidden: blank('body_temp'),
    render: (r) => (r.body_temp ? `${formatDecimal(r.body_temp, 1)}℃` : DASH),
  },
  {
    key: 'deep_sleep_min',
    label: '深睡',
    hidden: blank('deep_sleep_min'),
    render: (r) => (r.deep_sleep_min != null ? formatDuration(r.deep_sleep_min) : DASH),
  },
  {
    key: 'light_sleep_min',
    label: '浅睡',
    hidden: blank('light_sleep_min'),
    render: (r) => (r.light_sleep_min != null ? formatDuration(r.light_sleep_min) : DASH),
  },
  {
    key: 'wake_count',
    label: '醒来',
    // 醒来次数 0 是有效值（一觉到天亮），只在整列缺失时隐藏
    hidden: (rows) => rows.length > 0 && rows.every((r) => r.wake_count == null),
    render: (r) => (r.wake_count != null ? `${formatInt(r.wake_count)} 次` : DASH),
  },
  {
    key: 'sleep_quality',
    label: '质量',
    hidden: blank('sleep_quality'),
    render: (r) => (r.sleep_quality != null ? `${formatDecimal(r.sleep_quality, 1)}/10` : DASH),
  },
]

export function VitalsSleepPage() {
  const [days, setDays] = useState<StatsDays>(7)
  const [refresh, setRefresh] = useState(0)
  const { data: stats } = useStats<VitalsStats>('/health/vitals-sleep', days, refresh)
  const trend = stats?.trend ?? []
  const avg = stats?.avg

  const fmtSleep = (m?: number) => formatDuration(m)
  /** 生命体征数值：按量级统一小数位（心率整数、血糖/体温 1 位） */
  const fmt = (v?: number, unit = '', digits = 1) =>
    v != null ? `${formatDecimal(v, digits)}${unit}` : DASH

  const periodPicker = (
    <div className="flex items-center gap-2">
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
      headerExtra={periodPicker}
      onMutate={() => setRefresh((v) => v + 1)}
      extra={
        <>
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
                  <div className="mt-1 text-2xl font-semibold text-danger">{fmt(avg?.heart_rate, ' bpm', 0)}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均血氧</div>
                  <div className="mt-1 text-2xl font-semibold text-success">{avg?.blood_oxygen != null ? formatPercent(avg.blood_oxygen) : DASH}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均体温</div>
                  <div className="mt-1 text-2xl font-semibold text-warning">{fmt(avg?.body_temp, '℃')}</div>
                </CardContent>
              </Card>
              <Card>
                <CardContent className="py-4">
                  <div className="text-sm text-muted-foreground">平均血糖</div>
                  <div className="mt-1 text-2xl font-semibold text-info">{fmt(avg?.blood_glucose, ' mmol/L')}</div>
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
                  <div className="mt-1 text-2xl font-semibold text-decor-violet">{fmt(avg?.sleep_quality, ' 分')}</div>
                </CardContent>
              </Card>
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              <LineChartCard
                title="血压趋势"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'blood_pressure_high', name: '高压', color: 'danger' },
                  { key: 'blood_pressure_low', name: '低压', color: 'chart-5' },
                ]}
              />
              <LineChartCard
                title="心率趋势"
                data={trend}
                xKey="record_date"
                series={[{ key: 'heart_rate', name: '心率(bpm)', color: 'chart-7' }]}
              />
              <LineChartCard
                title="血氧 / 体温趋势"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'blood_oxygen', name: '血氧(%)', color: 'success' },
                  { key: 'body_temp', name: '体温(℃)', color: 'warning' },
                ]}
              />
              <LineChartCard
                title="血糖趋势"
                data={trend}
                xKey="record_date"
                series={[{ key: 'blood_glucose', name: '血糖(mmol/L)', color: 'info' }]}
              />
              <LineChartCard
                title="睡眠时长与质量"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'sleep_duration_min', name: '时长(分钟)', color: 'chart-6' },
                  { key: 'sleep_quality', name: '质量(分)', color: 'chart-2' },
                ]}
              />
              <BarChartCard
                title="深睡 / 浅睡时长"
                data={trend}
                xKey="record_date"
                series={[
                  { key: 'deep_sleep_min', name: '深睡(分钟)', color: 'chart-5' },
                  { key: 'light_sleep_min', name: '浅睡(分钟)', color: 'chart-3' },
                ]}
              />
            </div>
        </>
      }
    />
  )
}
