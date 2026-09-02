import { useEffect, useState } from 'react'
import { Loader2, Pencil, Plus, Settings, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import { api } from '@/lib/api'

type StepsRecord = {
  id: number
  record_date: string
  period: string
  steps: number
  distance_km?: number
  calories?: number
}

type StepsStats = {
  trend: { record_date: string; steps: number; distance_km?: number; calories?: number }[]
  by_period: { period: string; steps: number }[]
  avg_steps?: number
  total_steps: number
  max_steps?: number
  record_count?: number
}

type MonthlyStats = { months: { month: string; steps: number; distance_km: number; days: number }[] }

const PERIODS = [
  { value: '08-10', label: '08:00-10:00' },
  { value: '10-12', label: '10:00-12:00' },
  { value: '12-14', label: '12:00-14:00' },
  { value: '14-16', label: '14:00-16:00' },
  { value: '16-18', label: '16:00-18:00' },
  { value: '18-20', label: '18:00-20:00' },
  { value: '20-22', label: '20:00-22:00' },
  { value: '22-00', label: '22:00-00:00' },
  { value: 'full', label: '全天（凌晨0点累计）' },
]

const periodLabel = (p: string) => PERIODS.find((x) => x.value === p)?.label ?? p

const EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  period: 'full',
  steps: '',
  calories: '',
}

export function StepsPage() {
  const [items, setItems] = useState<StepsRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<StepsRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [settingDialogOpen, setSettingDialogOpen] = useState(false)
  const [stride, setStride] = useState('70')

  const stats = useStats<StepsStats>('/health/steps')
  const [months, setMonths] = useState<MonthlyStats['months']>([])

  const PAGE_SIZE = 20
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<StepsRecord>('/health/steps', { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page])

  useEffect(() => {
    api.query<{ stride_cm: number }>('/health/steps/settings').then((r) => setStride(String(r.stride_cm)))
    api.query<MonthlyStats>('/health/steps/monthly').then((r) => setMonths(r.months))
  }, [])

  const openCreate = () => {
    setEditing(null)
    setForm(EMPTY)
    setDialogOpen(true)
  }

  const openEdit = (row: StepsRecord) => {
    setEditing(row)
    setForm({
      record_date: row.record_date,
      period: row.period,
      steps: String(row.steps),
      calories: String(row.calories ?? ''),
    })
    setDialogOpen(true)
  }

  const set = (key: keyof typeof EMPTY, value: string) => setForm((f) => ({ ...f, [key]: value }))

  const submit = async () => {
    const payload = {
      record_date: form.record_date,
      period: form.period,
      steps: Number(form.steps),
      calories: form.calories === '' ? null : Number(form.calories),
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/steps', editing.id, payload)
      else await api.create('/health/steps', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: StepsRecord) => {
    if (!window.confirm('确定删除这条步数记录吗？')) return
    await api.remove('/health/steps', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const saveSetting = async () => {
    await api.put('/health/steps/settings', { stride_cm: Number(stride) || 70 })
    setSettingDialogOpen(false)
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">步数统计</h1>
          <p className="text-sm text-muted-foreground">按时间段录入每日步数，自动按步幅计算距离，支持日/月统计。</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setSettingDialogOpen(true)}>
            <Settings /> 步幅({stride}cm)
          </Button>
          <Button onClick={openCreate}>
            <Plus /> 新增步数
          </Button>
        </div>
      </section>

      {stats && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">总步数</div>
              <div className="mt-1 text-2xl font-semibold">{stats.total_steps.toLocaleString()}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">日均步数</div>
              <div className="mt-1 text-2xl font-semibold">{stats.avg_steps?.toLocaleString() ?? '-'}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">单日最高</div>
              <div className="mt-1 text-2xl font-semibold">{stats.max_steps?.toLocaleString() ?? '-'}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">记录条数</div>
              <div className="mt-1 text-2xl font-semibold">{stats.record_count}</div>
            </CardContent>
          </Card>
        </div>
      )}

      {stats && (
        <div className="grid gap-4 lg:grid-cols-2">
          <LineChartCard
            title="每日步数趋势"
            data={stats.trend}
            xKey="record_date"
            series={[{ key: 'steps', name: '步数', color: '#10b981' }]}
            height={260}
          />
          <BarChartCard
            title="各时间段步数分布"
            data={stats.by_period.map((p) => ({ ...p, label: periodLabel(p.period) }))}
            xKey="label"
            series={[{ key: 'steps', name: '步数', color: '#3b82f6' }]}
            height={260}
          />
        </div>
      )}

      {months.length > 0 && (
        <LineChartCard
          title="月度步数统计（近12个月）"
          data={months}
          xKey="month"
          series={[{ key: 'steps', name: '步数', color: '#f59e0b' }]}
          height={240}
        />
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>时间段</TableHead>
                <TableHead>步数</TableHead>
                <TableHead>距离</TableHead>
                <TableHead>消耗</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                    <Loader2 className="mx-auto size-5 animate-spin" />
                  </TableCell>
                </TableRow>
              ) : items.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                    暂无记录，点击"新增步数"添加第一条数据
                  </TableCell>
                </TableRow>
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.record_date}</TableCell>
                    <TableCell>{periodLabel(row.period)}</TableCell>
                    <TableCell>{row.steps.toLocaleString()}</TableCell>
                    <TableCell>{row.distance_km != null ? `${row.distance_km} km` : '—'}</TableCell>
                    <TableCell>{row.calories != null ? `${row.calories} kcal` : '—'}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(row)}>
                          <Pencil />
                        </Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(row)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <div className="flex items-center justify-between text-sm text-muted-foreground">
        <span>共 {total} 条记录</span>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>
            上一页
          </Button>
          <span>
            {page} / {totalPages}
          </span>
          <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage(page + 1)}>
            下一页
          </Button>
        </div>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑步数记录' : '新增步数记录'}</DialogTitle>
            <DialogDescription>选择时间段录入步数，距离按步幅自动计算。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>
                日期 <span className="text-destructive">*</span>
              </Label>
              <Input type="date" value={form.record_date} onChange={(e) => set('record_date', e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>
                时间段 <span className="text-destructive">*</span>
              </Label>
              <Select value={form.period} onValueChange={(v) => set('period', v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {PERIODS.map((p) => (
                    <SelectItem key={p.value} value={p.value}>
                      {p.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>
                步数 <span className="text-destructive">*</span>
              </Label>
              <Input type="number" min="0" value={form.steps} onChange={(e) => set('steps', e.target.value)} disabled={!!editing} />
            </div>
            <div className="space-y-2">
              <Label>消耗(kcal)</Label>
              <Input type="number" step="0.1" value={form.calories} onChange={(e) => set('calories', e.target.value)} placeholder="自动≈步数*0.04" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={submit} disabled={saving || !form.record_date || !form.steps}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={settingDialogOpen} onOpenChange={setSettingDialogOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>步幅设置</DialogTitle>
            <DialogDescription>设置每步步幅（cm），用于自动计算步行距离。</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>每步步幅（cm）</Label>
            <Input type="number" step="0.1" value={stride} onChange={(e) => setStride(e.target.value)} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSettingDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={saveSetting}>保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}