import { AlertCircle, CheckCircle2, ListChecks } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type TodoRecord = {
  id: number
  title: string
  category?: string
  priority: 'high' | 'medium' | 'low'
  due_date?: string
  done: boolean
  note?: string
}

type TodoStats = {
  total: number
  pending: number
  done: number
  overdue: number
  by_priority: { priority: string; count: number }[]
}

const fields: FieldDef[] = [
  { key: 'title', label: '事项', type: 'text', required: true },
  { key: 'category', label: '分类', type: 'text', placeholder: '如 缴费 / 健康 / 工作' },
  {
    key: 'priority',
    label: '优先级',
    type: 'select',
    options: [
      { value: 'high', label: '高' },
      { value: 'medium', label: '中' },
      { value: 'low', label: '低' },
    ],
  },
  { key: 'due_date', label: '截止日期', type: 'date' },
  {
    key: 'done',
    label: '是否完成',
    type: 'boolean',
    options: [
      { value: 'false', label: '未完成' },
      { value: 'true', label: '已完成' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const priorityMeta: Record<string, { label: string; className: string }> = {
  high: { label: '高', className: 'bg-red-100 text-red-700' },
  medium: { label: '中', className: 'bg-amber-100 text-amber-700' },
  low: { label: '低', className: 'bg-blue-100 text-blue-700' },
}

const columns: ColumnDef<TodoRecord>[] = [
  { key: 'title', label: '事项' },
  { key: 'category', label: '分类', render: (r) => r.category ?? '—' },
  {
    key: 'priority',
    label: '优先级',
    render: (r) => (
      <Badge className={priorityMeta[r.priority]?.className}>{priorityMeta[r.priority]?.label ?? r.priority}</Badge>
    ),
  },
  { key: 'due_date', label: '截止日期', render: (r) => r.due_date ?? '—' },
  {
    key: 'done',
    label: '状态',
    render: (r) =>
      r.done ? (
        <Badge className="bg-green-100 text-green-700">已完成</Badge>
      ) : (
        <Badge className="bg-amber-100 text-amber-700">待办</Badge>
      ),
  },
]

function StatChip({
  icon: Icon,
  label,
  value,
  className,
}: {
  icon: typeof ListChecks
  label: string
  value: string
  className?: string
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
      </CardContent>
    </Card>
  )
}

export function TodosPage() {
  const stats = useStats<TodoStats>('/lifestyle/todos')
  const byPriority = stats?.by_priority ?? []

  return (
    <RecordManager<TodoRecord>
      title="待办清单"
      description="管理日常待办事项，按时完成任务。"
      apiPath="/lifestyle/todos"
      fields={fields}
      columns={columns}
      extra={
        stats ? (
          <>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <StatChip icon={ListChecks} label="待办总数" value={String(stats.total)} />
              <StatChip
                icon={AlertCircle}
                label="待处理"
                value={String(stats.pending)}
                className="text-amber-500"
              />
              <StatChip
                icon={CheckCircle2}
                label="已完成"
                value={String(stats.done)}
                className="text-green-500"
              />
              <StatChip
                icon={AlertCircle}
                label="已逾期"
                value={String(stats.overdue)}
                className="text-red-500"
              />
            </div>
            {byPriority.length > 0 && (
              <BarChartCard
                title="优先级分布"
                data={byPriority}
                xKey="priority"
                series={[{ key: 'count', name: '数量', color: '#ec4899' }]}
              />
            )}
          </>
        ) : null
      }
    />
  )
}
