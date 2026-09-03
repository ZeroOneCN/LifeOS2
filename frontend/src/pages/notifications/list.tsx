import { useEffect, useState } from 'react'
import {
  Bell,
  CheckCheck,
  CheckCircle2,
  Loader2,
  Mail,
  Pencil,
  Plus,
  Trash2,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'

type NotificationRecord = {
  id: number
  title: string
  content?: string
  category: string
  source?: string
  read: boolean
  notify_date: string
  note?: string
}

type NotificationStats = {
  total: number
  unread: number
  today: number
  by_category: { category: string; count: number }[]
  trend: { notify_date: string; count: number }[]
}

const categories = ['系统', '健康', '财务', '生活', '投资', '其他']

const categoryStyle: Record<string, string> = {
  系统: 'bg-blue-100 text-blue-700',
  健康: 'bg-green-100 text-green-700',
  财务: 'bg-amber-100 text-amber-700',
  生活: 'bg-purple-100 text-purple-700',
  投资: 'bg-cyan-100 text-cyan-700',
  其他: 'bg-gray-100 text-gray-600',
}

function StatCard({
  icon: Icon,
  label,
  value,
  className,
}: {
  icon: typeof Bell
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

export function NotificationList() {
  const [items, setItems] = useState<NotificationRecord[]>([])
  const [stats, setStats] = useState<NotificationStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const totalPages = Math.max(1, Math.ceil(total / 10))
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<NotificationRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条通知吗？此操作不可恢复。',
  })

  const load = async () => {
    setLoading(true)
    try {
      const [listRes, statsRes] = await Promise.all([
        api.list<NotificationRecord>('/notifications', { page, page_size: 10 }),
        api.query<NotificationStats>('/notifications/stats?days=30'),
      ])
      setItems(listRes.items)
      setTotal(listRes.total)
      setStats(statsRes)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [page]) // eslint-disable-line react-hooks/exhaustive-deps

  const openCreate = () => {
    setEditing(null)
    setForm({ title: '', category: '系统', source: '', notify_date: '', content: '', read: 'false' })
    setDialogOpen(true)
  }

  const openEdit = (row: NotificationRecord) => {
    setEditing(row)
    setForm({
      title: row.title,
      category: row.category,
      source: row.source ?? '',
      notify_date: row.notify_date,
      content: row.content ?? '',
      read: String(row.read),
    })
    setDialogOpen(true)
  }

  const submit = async () => {
    const today = new Date().toISOString().slice(0, 10)
    const payload: Record<string, unknown> = {
      title: form.title || null,
      category: form.category || null,
      source: form.source || null,
      notify_date: form.notify_date || today,
      content: form.content || null,
      read: form.read === 'true',
    }
    setSaving(true)
    try {
      if (editing) await api.update('/notifications', editing.id, payload)
      else await api.create('/notifications', payload)
      setDialogOpen(false)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const toggleRead = async (row: NotificationRecord) => {
    await api.update('/notifications', row.id, {
      title: row.title,
      category: row.category,
      source: row.source ?? null,
      notify_date: row.notify_date,
      content: row.content ?? null,
      read: !row.read,
    })
    await load()
  }

  const readAll = async () => {
    await api.post('/notifications/read-all')
    await load()
  }

  const remove = async (row: NotificationRecord) => {
    if (!(await confirm())) return
    await api.remove('/notifications', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const byCategory = stats?.by_category ?? []
  const trend = stats?.trend ?? []

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-end gap-2">
        <Button variant="outline" onClick={readAll} disabled={!stats || stats.unread === 0}>
          <CheckCheck /> 全部标为已读
        </Button>
        <Button onClick={openCreate}>
          <Plus /> 发布通知
        </Button>
      </div>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard icon={Mail} label="未读通知" value={String(stats?.unread ?? '—')} className="text-blue-500" />
        <StatCard icon={Bell} label="今日通知" value={String(stats?.today ?? '—')} className="text-amber-500" />
        <StatCard icon={CheckCircle2} label="通知总数" value={String(stats?.total ?? '—')} className="text-green-500" />
      </section>

      {byCategory.length > 0 || trend.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="通知类型分布"
            data={byCategory}
            xKey="category"
            series={[{ key: 'count', name: '数量', color: '#6366f1' }]}
          />
          <LineChartCard
            title="近30天通知趋势"
            data={trend}
            xKey="notify_date"
            series={[{ key: 'count', name: '通知数', color: '#0ea5e9' }]}
          />
        </div>
      ) : null}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">通知列表</CardTitle>
          <CardDescription>未读通知以蓝色圆点标记</CardDescription>
        </CardHeader>
        <CardContent className={`space-y-2 transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
          {items.length === 0 ? (
            loading ? (
              <div className="flex justify-center py-12 text-muted-foreground">
                <Loader2 className="size-5 animate-spin" />
              </div>
            ) : (
              <p className="py-12 text-center text-sm text-muted-foreground">
                暂无通知，点击"发布通知"创建第一条
              </p>
            )
          ) : (
            items.map((row) => (
              <div
                key={row.id}
                className={`flex items-start justify-between gap-4 rounded-lg border px-4 py-3 ${
                  row.read ? 'opacity-70' : ''
                }`}
              >
                <div className="flex min-w-0 gap-3">
                  <span
                    className={`mt-1.5 size-2 shrink-0 rounded-full ${
                      row.read ? 'bg-transparent' : 'bg-blue-500'
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span
                        className={`truncate text-sm font-medium ${
                          row.read ? 'text-muted-foreground' : ''
                        }`}
                      >
                        {row.title}
                      </span>
                      <Badge className={categoryStyle[row.category] ?? categoryStyle.其他}>
                        {row.category}
                      </Badge>
                    </div>
                    {row.content && (
                      <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">
                        {row.content}
                      </p>
                    )}
                    <div className="mt-1 flex gap-3 text-xs text-muted-foreground">
                      <span>{row.source ?? '—'}</span>
                      <span>{row.notify_date}</span>
                    </div>
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <Button variant="ghost" size="sm" onClick={() => toggleRead(row)} title={row.read ? '标记为未读' : '标记为已读'}>
                    {row.read ? <Mail className="size-4" /> : <CheckCheck className="size-4" />}
                  </Button>
                  <Button variant="ghost" size="icon" onClick={() => openEdit(row)}>
                    <Pencil />
                  </Button>
                  <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(row)}>
                    <Trash2 />
                  </Button>
                </div>
              </div>
            ))
          )}
        </CardContent>
        {totalPages > 1 && (
          <CardFooter className="flex items-center justify-end gap-2">
            <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>
              上一页
            </Button>
            <span className="text-sm text-muted-foreground">
              {page} / {totalPages}
            </span>
            <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage(page + 1)}>
              下一页
            </Button>
          </CardFooter>
        )}
      </Card>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑通知' : '发布通知'}</DialogTitle>
            <DialogDescription>{editing ? '修改并保存本条通知。' : '填写信息创建一条新通知。'}</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label htmlFor="title">通知标题<span className="text-destructive"> *</span></Label>
              <Input id="title" value={form.title ?? ''} onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))} placeholder="通知标题" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="category">类型<span className="text-destructive"> *</span></Label>
              <Select value={form.category ?? ''} onValueChange={(v) => setForm((f) => ({ ...f, category: v }))}>
                <SelectTrigger id="category">
                  <SelectValue placeholder="请选择类型" />
                </SelectTrigger>
                <SelectContent>
                  {categories.map((c) => (
                    <SelectItem key={c} value={c}>{c}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="source">来源模块</Label>
              <Input id="source" value={form.source ?? ''} onChange={(e) => setForm((f) => ({ ...f, source: e.target.value }))} placeholder="如 健康中心" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="notify_date">通知日期<span className="text-destructive"> *</span></Label>
              <Input id="notify_date" type="date" value={form.notify_date ?? ''} onChange={(e) => setForm((f) => ({ ...f, notify_date: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="read">已读状态</Label>
              <Select value={form.read ?? 'false'} onValueChange={(v) => setForm((f) => ({ ...f, read: v }))}>
                <SelectTrigger id="read">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="false">未读</SelectItem>
                  <SelectItem value="true">已读</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2">
              <Label htmlFor="content">通知内容</Label>
              <Textarea id="content" value={form.content ?? ''} onChange={(e) => setForm((f) => ({ ...f, content: e.target.value }))} placeholder="通知详细内容" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>取消</Button>
            <Button onClick={submit} disabled={saving}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}