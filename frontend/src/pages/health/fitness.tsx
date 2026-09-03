import { useEffect, useRef, useState } from 'react'
import { Loader2, Pencil, Plus, Trash2 } from 'lucide-react'

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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Textarea } from '@/components/ui/textarea'
import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'

type FitnessRecord = {
  id: number
  record_date: string
  exercise_type: string
  duration_min: number
  calories?: number
  distance_km?: number
  note?: string
}

type FitnessStats = {
  by_type: { exercise_type: string; count: number; minutes: number; calories: number }[]
  trend: { record_date: string; count: number; minutes: number; calories: number }[]
  total_count: number
  total_minutes: number
  total_calories: number
}

const EXERCISE_SUGGESTIONS = [
  '跑步', '慢跑', '快走', '散步', '走路', '游泳', '骑行', '自行车',
  '力量训练', '举重', '跳绳', '羽毛球', '乒乓球', '篮球', '足球', '网球',
  '瑜伽', '普拉提', '舞蹈', '登山', '爬楼梯', '椭圆机', '划船机', '健身操', 'HIIT',
]

const EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  exercise_type: '',
  duration_min: '',
  calories: '',
  distance_km: '',
  note: '',
}

export function FitnessPage() {
  const [items, setItems] = useState<FitnessRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<FitnessRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [estimating, setEstimating] = useState(false)
  const estTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条运动记录吗？此操作不可恢复。',
  })

  const stats = useStats<FitnessStats>('/health/fitness')
  const PAGE_SIZE = 10
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<FitnessRecord>('/health/fitness', { page, page_size: PAGE_SIZE })
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

  const openCreate = () => {
    setEditing(null)
    setForm(EMPTY)
    setDialogOpen(true)
  }

  const openEdit = (row: FitnessRecord) => {
    setEditing(row)
    setForm({
      record_date: row.record_date,
      exercise_type: row.exercise_type,
      duration_min: String(row.duration_min ?? ''),
      calories: String(row.calories ?? ''),
      distance_km: String(row.distance_km ?? ''),
      note: row.note ?? '',
    })
    setDialogOpen(true)
  }

  const set = (key: keyof typeof EMPTY, value: string) => setForm((f) => ({ ...f, [key]: value }))

  // 运动热量估算：输入类型+时长后自动推算
  useEffect(() => {
    if (editing) return
    if (estTimer.current) clearTimeout(estTimer.current)
    const type = form.exercise_type.trim()
    const dur = Number(form.duration_min)
    if (!type || !dur || dur <= 0) return
    estTimer.current = setTimeout(async () => {
      setEstimating(true)
      try {
        const est = await api.query<{ calories: number }>(
          `/health/fitness/estimate?exercise_type=${encodeURIComponent(type)}&duration_min=${dur}`,
        )
        setForm((f) => ({ ...f, calories: String(est.calories) }))
      } catch {
        /* ignore */
      } finally {
        setEstimating(false)
      }
    }, 300)
    return () => {
      if (estTimer.current) clearTimeout(estTimer.current)
    }
  }, [form.exercise_type, form.duration_min, editing])

  const submit = async () => {
    const set = (v: string) => (v === '' ? null : Number(v))
    const payload = {
      record_date: form.record_date,
      exercise_type: form.exercise_type,
      duration_min: Number(form.duration_min),
      calories: set(form.calories),
      distance_km: set(form.distance_km),
      note: form.note === '' ? null : form.note,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/fitness', editing.id, payload)
      else await api.create('/health/fitness', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: FitnessRecord) => {
    if (!(await confirm())) return
    await api.remove('/health/fitness', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Button onClick={openCreate}>
          <Plus /> 新增运动记录
        </Button>
      </div>

      {stats && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">运动次数</div>
              <div className="mt-1 text-2xl font-semibold">{stats.total_count} 次</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">运动时长</div>
              <div className="mt-1 text-2xl font-semibold">{stats.total_minutes} 分钟</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">总消耗</div>
              <div className="mt-1 text-2xl font-semibold text-emerald-500">{stats.total_calories} kcal</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">平均每次消耗</div>
              <div className="mt-1 text-2xl font-semibold">
                {stats.total_count ? Math.round(stats.total_calories / stats.total_count) : '-'} kcal
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {stats && (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="运动类型时长分布（近 30 天）"
            data={stats.by_type.map((t) => ({ name: t.exercise_type, minutes: t.minutes }))}
            xKey="name"
            series={[{ key: 'minutes', name: '时长(分钟)', color: '#4f46e5' }]}
          />
          <LineChartCard
            title="每日运动消耗"
            data={stats.trend}
            xKey="record_date"
            series={[{ key: 'calories', name: '消耗(kcal)', color: '#f59e0b' }]}
          />
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>类型</TableHead>
                <TableHead>时长</TableHead>
                <TableHead>消耗</TableHead>
                <TableHead>距离</TableHead>
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
                    暂无记录，点击"新增运动记录"添加第一条数据
                  </TableCell>
                </TableRow>
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.record_date}</TableCell>
                    <TableCell>{row.exercise_type}</TableCell>
                    <TableCell>{row.duration_min} 分钟</TableCell>
                    <TableCell>{row.calories != null ? `${row.calories} kcal` : '—'}</TableCell>
                    <TableCell>{row.distance_km != null ? `${row.distance_km} km` : '—'}</TableCell>
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
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑运动记录' : '新增运动记录'}</DialogTitle>
            <DialogDescription>输入运动类型与时长，系统自动推算消耗热量（可按需修改）。</DialogDescription>
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
                时长(分钟) <span className="text-destructive">*</span>
              </Label>
              <Input type="number" min="1" value={form.duration_min} onChange={(e) => set('duration_min', e.target.value)} disabled={!!editing} placeholder="30" />
            </div>
            <div className="space-y-2 col-span-2">
              <Label>
                运动类型 <span className="text-destructive">*</span>
              </Label>
              <Input
                list="exercise-list"
                value={form.exercise_type}
                onChange={(e) => set('exercise_type', e.target.value)}
                placeholder="如：跑步、游泳、力量训练"
                disabled={!!editing}
              />
              <datalist id="exercise-list">
                {EXERCISE_SUGGESTIONS.map((t) => (
                  <option key={t} value={t} />
                ))}
              </datalist>
            </div>
            <div className="space-y-2">
              <Label>消耗热量(kcal)</Label>
              <Input
                type="number"
                step="0.1"
                value={form.calories}
                onChange={(e) => set('calories', e.target.value)}
                placeholder={estimating ? '推算中...' : '自动推算'}
              />
            </div>
            <div className="space-y-2">
              <Label>距离(km)</Label>
              <Input type="number" step="0.1" value={form.distance_km} onChange={(e) => set('distance_km', e.target.value)} placeholder="可选" />
            </div>
            <div className="space-y-2 col-span-2">
              <Label>备注</Label>
              <Textarea value={form.note} onChange={(e) => set('note', e.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button
              onClick={submit}
              disabled={saving || !form.record_date || !form.exercise_type || !form.duration_min}
            >
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