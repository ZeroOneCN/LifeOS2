import { AlertCircle, CheckCircle2, Clock, Inbox } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'

type ReminderRecord = {
  id: number
  reminder_date: string
  title: string
  category: string
  amount?: number
  due_date?: string
  status: 'pending' | 'done'
  note?: string
}

type ReminderStats = {
  total: number
  pending: number
  done: number
  overdue: number
  recent: { reminder_date: string; title: string; category: string; due_date?: string; status: string }[]
}

const categories = ['缴费', '还款', '订阅', '保险', '其他']

const fields: FieldDef[] = [
  { key: 'reminder_date', label: '提醒日期', type: 'date', required: true },
  { key: 'title', label: '标题', type: 'text', required: true, placeholder: '如 交本月电费' },
  {
    key: 'category',
    label: '类型',
    type: 'select',
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'amount', label: '金额', type: 'number', step: '0.01', min: 0 },
  { key: 'due_date', label: '截止日期', type: 'date' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'pending', label: '待处理' },
      { value: 'done', label: '已完成' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const columns: ColumnDef<ReminderRecord>[] = [
  { key: 'reminder_date', label: '提醒日期' },
  { key: 'title', label: '标题' },
  { key: 'category', label: '类型', render: (r) => r.category ?? '—' },
  {
    key: 'amount',
    label: '金额',
    render: (r) =>
      r.amount != null
        ? `¥${r.amount.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
        : '—',
  },
  { key: 'due_date', label: '截止', render: (r) => r.due_date ?? '—' },
  {
    key: 'status',
    label: '状态',
    render: (r) =>
      r.status === 'done' ? (
        <Badge className="bg-green-100 text-green-700">已完成</Badge>
      ) : (
        <Badge className="bg-amber-100 text-amber-700">待处理</Badge>
      ),
  },
]

function StatChip({
  icon: Icon,
  label,
  value,
  className,
}: {
  icon: typeof Clock
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

export function RemindersPage() {
  const stats = useStats<ReminderStats>('/finance/reminders')

  return (
    <RecordManager<ReminderRecord>
      title="账单提醒"
      description="设置缴费、还款提醒，避免遗漏每一笔待办。"
      apiPath="/finance/reminders"
      fields={fields}
      columns={columns}
      extra={
        stats ? (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatChip icon={Inbox} label="提醒总数" value={String(stats.total)} />
            <StatChip
              icon={Clock}
              label="待处理"
              value={String(stats.pending)}
              className="text-amber-500"
            />
            <StatChip
              icon={AlertCircle}
              label="已逾期"
              value={String(stats.overdue)}
              className="text-red-500"
            />
            <StatChip
              icon={CheckCircle2}
              label="已完成"
              value={String(stats.done)}
              className="text-green-500"
            />
          </div>
        ) : null
      }
    />
  )
}
