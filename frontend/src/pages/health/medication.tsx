import { Badge } from '@/components/ui/badge'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type MedRecord = {
  id: number
  record_date: string
  medicine_name: string
  dosage?: string
  frequency?: string
  taken: boolean
  note?: string
}

type MedStats = {
  today: {
    taken_count: number
    pending_count: number
    items: { id: number; medicine_name: string; taken: boolean }[]
  }
  adherence_rate?: number
  trend: { record_date: string; total: number; taken: number }[]
}

const fields: FieldDef[] = [
  { key: 'record_date', label: '日期', type: 'date', required: true },
  { key: 'medicine_name', label: '药品名称', type: 'text', required: true, placeholder: '如：维生素D' },
  { key: 'dosage', label: '剂量', type: 'text', placeholder: '如：1粒 / 500mg' },
  { key: 'frequency', label: '频次', type: 'text', placeholder: '如：每日1次' },
  {
    key: 'taken',
    label: '是否已服',
    type: 'boolean',
    options: [
      { value: 'true', label: '已服用' },
      { value: 'false', label: '未服用' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<MedRecord>[] = [
  { key: 'record_date', label: '日期' },
  { key: 'medicine_name', label: '药品名称' },
  { key: 'dosage', label: '剂量', render: (r) => r.dosage ?? '—' },
  { key: 'frequency', label: '频次', render: (r) => r.frequency ?? '—' },
  {
    key: 'taken',
    label: '状态',
    render: (r) =>
      r.taken ? (
        <Badge className="bg-green-100 text-green-700">已服用</Badge>
      ) : (
        <Badge className="bg-amber-100 text-amber-700">未服用</Badge>
      ),
  },
]

export function MedicationPage() {
  const stats = useStats<MedStats>('/health/medication')
  const trend = stats?.trend ?? []

  return (
    <RecordManager<MedRecord>
      title="用药跟踪"
      description="记录每日用药情况，及时掌握服药依从性。"
      apiPath="/health/medication"
      fields={fields}
      columns={columns}
      extra={
        stats && (
          <div className="grid gap-4 lg:grid-cols-2">
            <div className="grid grid-cols-2 gap-4">
              <div className="rounded-lg border p-4">
                <div className="text-sm text-muted-foreground">今日待服</div>
                <div className="mt-1 text-2xl font-semibold">
                  {stats.today.pending_count} 项
                </div>
              </div>
              <div className="rounded-lg border p-4">
                <div className="text-sm text-muted-foreground">近 30 天依从率</div>
                <div className="mt-1 text-2xl font-semibold">
                  {stats.adherence_rate != null ? `${stats.adherence_rate}%` : '—'}
                </div>
              </div>
              <div className="col-span-2 space-y-2">
                {stats.today.items.length === 0 && (
                  <p className="rounded-lg border p-4 text-center text-sm text-muted-foreground">
                    今日暂无用药记录
                  </p>
                )}
                {stats.today.items.map((item) => (
                  <div
                    key={item.id}
                    className="flex items-center justify-between rounded-lg border px-3 py-2"
                  >
                    <span className="text-sm font-medium">{item.medicine_name}</span>
                    <Badge className={item.taken ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}>
                      {item.taken ? '已服' : '待服'}
                    </Badge>
                  </div>
                ))}
              </div>
            </div>
            <BarChartCard
              title="每日服药情况"
              data={trend}
              xKey="record_date"
              series={[
                { key: 'taken', name: '已服', color: '#10b981' },
                { key: 'total', name: '应服', color: '#94a3b8' },
              ]}
            />
          </div>
        )
      }
    />
  )
}
