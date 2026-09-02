import { FileText } from 'lucide-react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type ReportRecord = {
  id: number
  report_date: string
  title: string
  summary?: string
  content?: string
}

type ReportsStats = {
  recent: { id: number; report_date: string; title: string; summary?: string }[]
  total_count: number
}

const fields: FieldDef[] = [
  { key: 'report_date', label: '报告日期', type: 'date', required: true },
  { key: 'title', label: '标题', type: 'text', required: true, placeholder: '如：9 月健康周报' },
  { key: 'summary', label: '摘要', type: 'textarea' },
  { key: 'content', label: '报告内容', type: 'textarea', full: true },
]

const columns: ColumnDef<ReportRecord>[] = [
  { key: 'report_date', label: '报告日期' },
  { key: 'title', label: '标题' },
  { key: 'summary', label: '摘要', render: (r) => r.summary ?? '—' },
]

export function ReportsPage() {
  const stats = useStats<ReportsStats>('/health/reports')
  const recent = stats?.recent ?? []

  return (
    <RecordManager<ReportRecord>
      title="健康报告"
      description="归档各时期的健康汇总报告与体检结论。"
      apiPath="/health/reports"
      fields={fields}
      columns={columns}
      extra={
        recent.length > 0 && (
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">最近报告</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {recent.map((r) => (
                <div key={r.id} className="flex items-start gap-3 rounded-lg border p-3">
                  <FileText className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                  <div>
                    <div className="text-sm font-medium">{r.title}</div>
                    <div className="text-xs text-muted-foreground">{r.report_date}</div>
                    {r.summary && (
                      <p className="mt-1 text-sm text-muted-foreground">{r.summary}</p>
                    )}
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        )
      }
    />
  )
}
