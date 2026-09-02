import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type CheckupRecord = {
  id: number
  check_date: string
  item_name: string
  value?: number
  unit?: string
  reference_range?: string
  result?: string
  note?: string
}

type CheckupStats = {
  items: {
    item_name: string
    unit?: string
    reference_range?: string
    latest: { check_date: string; value?: number; result?: string } | null
    count: number
  }[]
  abnormal_count: number
}

const resultMeta: Record<string, { label: string; className: string }> = {
  normal: { label: '正常', className: 'bg-green-100 text-green-700' },
  high: { label: '偏高', className: 'bg-red-100 text-red-700' },
  low: { label: '偏低', className: 'bg-amber-100 text-amber-700' },
}

const fields: FieldDef[] = [
  { key: 'check_date', label: '检查日期', type: 'date', required: true },
  { key: 'item_name', label: '指标名称', type: 'text', required: true, placeholder: '如：空腹血糖' },
  { key: 'value', label: '数值', type: 'number', step: '0.01' },
  { key: 'unit', label: '单位', type: 'text', placeholder: '如：mmol/L' },
  { key: 'reference_range', label: '参考范围', type: 'text', placeholder: '如：3.9-6.1' },
  {
    key: 'result',
    label: '结果',
    type: 'select',
    options: [
      { value: 'normal', label: '正常' },
      { value: 'high', label: '偏高' },
      { value: 'low', label: '偏低' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<CheckupRecord>[] = [
  { key: 'check_date', label: '检查日期' },
  { key: 'item_name', label: '指标名称' },
  { key: 'value', label: '数值', render: (r) => (r.value != null ? String(r.value) : '—') },
  { key: 'unit', label: '单位', render: (r) => r.unit ?? '—' },
  { key: 'reference_range', label: '参考范围', render: (r) => r.reference_range ?? '—' },
  {
    key: 'result',
    label: '结果',
    render: (r) =>
      r.result ? (
        <Badge className={resultMeta[r.result]?.className}>
          {resultMeta[r.result]?.label ?? r.result}
        </Badge>
      ) : (
        '—'
      ),
  },
]

export function CheckupPage() {
  const stats = useStats<CheckupStats>('/health/checkup')
  const items = stats?.items ?? []

  return (
    <RecordManager<CheckupRecord>
      title="体检指标"
      description="管理各项体检数据与参考范围，跟踪指标变化。"
      apiPath="/health/checkup"
      fields={fields}
      columns={columns}
      extra={
        items.length > 0 && (
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-sm font-medium">
                指标概览
                {stats && stats.abnormal_count > 0 && (
                  <Badge className="bg-red-100 text-red-700">
                    {stats.abnormal_count} 项异常
                  </Badge>
                )}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {items.map((item) => (
                  <div key={item.item_name} className="rounded-lg border p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-medium">{item.item_name}</span>
                      {item.latest?.result && (
                        <Badge className={resultMeta[item.latest.result]?.className}>
                          {resultMeta[item.latest.result]?.label}
                        </Badge>
                      )}
                    </div>
                    <div className="mt-1 text-xl font-semibold">
                      {item.latest?.value != null ? item.latest.value : '—'}
                      <span className="ml-1 text-xs font-normal text-muted-foreground">
                        {item.unit ?? ''}
                      </span>
                    </div>
                    <div className="text-xs text-muted-foreground">
                      参考 {item.reference_range ?? '—'} · {item.count} 次记录
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        )
      }
    />
  )
}
