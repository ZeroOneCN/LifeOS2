import { useEffect, useState } from 'react'
import { AlertCircle, Banknote, CheckCircle2, Clock, Inbox, Repeat, User, Zap } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import { api } from '@/lib/api'
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

type AggregateItem = {
  source: string
  source_label: string
  title: string
  amount?: number
  due_date: string
  status: 'pending' | 'overdue'
}
type Aggregate = { total: number; pending: number; overdue: number; items: AggregateItem[] }

const sourceMeta: Record<string, { label: string; className: string; icon: typeof Inbox }> = {
  订阅: { label: '服务订阅', className: 'bg-indigo-100 text-indigo-700', icon: Repeat },
  水电气: { label: '水电账单', className: 'bg-sky-100 text-sky-700', icon: Zap },
  网贷: { label: '网贷账单', className: 'bg-red-100 text-red-700', icon: Banknote },
  手动: { label: '手动提醒', className: 'bg-gray-100 text-gray-600', icon: User },
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

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

export function RemindersPage() {
  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const [refresh, setRefresh] = useState(0)
  const stats = useStats<ReminderStats>('/finance/reminders', days, refresh)
  const [agg, setAgg] = useState<Aggregate | null>(null)

  useEffect(() => {
    api.query<Aggregate>('/finance/reminders/aggregate').then(setAgg).catch(() => setAgg(null))
  }, [refresh])

  const aggCards = agg
    ? [
        { icon: Inbox, label: '待办总数', value: String(agg.total), color: 'text-muted-foreground' },
        { icon: Clock, label: '待处理', value: String(agg.pending), color: 'text-amber-500' },
        { icon: AlertCircle, label: '已逾期', value: String(agg.overdue), color: 'text-red-500' },
      ]
    : []

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">账单提醒</h1>
          <p className="text-sm text-muted-foreground">汇总服务订阅、水电账单、网贷还款与手动提醒，避免遗漏。</p>
        </div>
      </section>

      {agg && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {aggCards.map((c) => (
              <Card key={c.label}>
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">{c.label}</CardTitle>
                  <c.icon className={`size-4 ${c.color}`} />
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-semibold">{c.value}</div>
                </CardContent>
              </Card>
            ))}
          </section>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">全部待办提醒（按到期日）</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1.5">
              {agg.items.length === 0 ? (
                <p className="py-4 text-center text-sm text-muted-foreground">暂无待办提醒</p>
              ) : (
                agg.items.map((it, i) => {
                  const meta = sourceMeta[it.source] ?? { label: it.source_label, className: 'bg-gray-100 text-gray-600', icon: Inbox }
                  const Icon = meta.icon
                  return (
                    <div
                      key={i}
                      className={`flex flex-wrap items-center justify-between gap-2 rounded-md border px-3 py-2 text-sm ${it.status === 'overdue' ? 'border-red-200 bg-red-50' : 'bg-white'}`}
                    >
                      <span className="flex items-center gap-2">
                        <span className={`flex size-6 items-center justify-center rounded-full ${meta.className}`}>
                          <Icon className="size-3.5" />
                        </span>
                        <Badge variant="outline">{meta.label}</Badge>
                        <span className="font-medium">{it.title}</span>
                      </span>
                      <span className="flex items-center gap-2 text-muted-foreground">
                        {it.amount != null && <span className="font-medium text-foreground">{fmt(it.amount)}</span>}
                        <span>到期 {it.due_date}</span>
                        {it.status === 'overdue' ? (
                          <Badge className="bg-red-100 text-red-700">已逾期</Badge>
                        ) : (
                          <Badge className="bg-amber-100 text-amber-700">待处理</Badge>
                        )}
                      </span>
                    </div>
                  )
                })
              )}
            </CardContent>
          </Card>
        </>
      )}

      <RecordManager<ReminderRecord>
        title="账单提醒"
        description="设置缴费、还款提醒，避免遗漏每一笔待办。"
        apiPath="/finance/reminders"
        fields={fields}
        columns={columns}
        monthMode
        monthField="reminder_date"
        onMutate={() => setRefresh((v) => v + 1)}
        extra={
          <>
            <div className="flex justify-end">
              <StatsPeriodPicker
                value={days}
                onChange={(d) => {
                  setDays(d)
                  setGlobalStatsDays(d)
                }}
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <StatChip icon={Inbox} label="手动提醒总数" value={String(stats?.total ?? 0)} />
              <StatChip icon={Clock} label="手动待处理" value={String(stats?.pending ?? 0)} className="text-amber-500" />
              <StatChip icon={AlertCircle} label="手动已逾期" value={String(stats?.overdue ?? 0)} className="text-red-500" />
              <StatChip icon={CheckCircle2} label="手动已完成" value={String(stats?.done ?? 0)} className="text-green-500" />
            </div>
          </>
        }
      />
    </div>
  )
}
