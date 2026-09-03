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
import { DatePicker } from '@/components/ui/date-picker'
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
import { Textarea } from '@/components/ui/textarea'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { BarChartCard, LineChartCard, StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import { api } from '@/lib/api'

type DietRecord = {
  id: number
  record_date: string
  meal_type: string
  food_name: string
  weight_g: number
  calories: number
  protein?: number
  carbs?: number
  fat?: number
  note?: string
}

type DietStats = {
  trend: { record_date: string; calories: number; protein: number; carbs: number; fat: number }[]
  by_meal: { meal_type: string; calories: number; count: number }[]
  total_calories: number
  total_protein: number
  avg_calories_per_day: number
}

const MEAL_LABEL: Record<string, string> = {
  breakfast: '早餐',
  lunch: '午餐',
  dinner: '晚餐',
  snack: '加餐',
}

type FoodHint = { name: string }

const EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  meal_type: '',
  food_name: '',
  weight_g: '',
  calories: '',
  protein: '',
  carbs: '',
  fat: '',
  note: '',
}

export function DietPage() {
  const [items, setItems] = useState<DietRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<DietRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [foodHints, setFoodHints] = useState<FoodHint[]>([])
  const [estimating, setEstimating] = useState(false)
  const estTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条饮食记录吗？此操作不可恢复。',
  })

  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const stats = useStats<DietStats>('/health/diet', days)
  const PAGE_SIZE = 10
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<DietRecord>('/health/diet', { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    api.query<{ items: FoodHint[] }>('/health/diet/foods').then((r) => setFoodHints(r.items))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page])

  const openCreate = () => {
    setEditing(null)
    setForm(EMPTY)
    setDialogOpen(true)
  }

  const openEdit = (row: DietRecord) => {
    setEditing(row)
    setForm({
      record_date: row.record_date,
      meal_type: row.meal_type,
      food_name: row.food_name,
      weight_g: String(row.weight_g ?? ''),
      calories: String(row.calories ?? ''),
      protein: String(row.protein ?? ''),
      carbs: String(row.carbs ?? ''),
      fat: String(row.fat ?? ''),
      note: row.note ?? '',
    })
    setDialogOpen(true)
  }

  // 识别食物营养：输入食物名+重量后自动推算
  useEffect(() => {
    if (editing) return
    if (estTimer.current) clearTimeout(estTimer.current)
    const food = form.food_name.trim()
    const weight = Number(form.weight_g)
    if (!food || !weight || weight <= 0) return
    estTimer.current = setTimeout(async () => {
      setEstimating(true)
      try {
        const est = await api.query<{ calories: number; protein: number; carbs: number; fat: number }>(
          `/health/diet/estimate?food_name=${encodeURIComponent(food)}&weight_g=${weight}`,
        )
        setForm((f) => ({ ...f, calories: String(est.calories), protein: String(est.protein), carbs: String(est.carbs), fat: String(est.fat) }))
      } catch {
        /* ignore */
      } finally {
        setEstimating(false)
      }
    }, 300)
    return () => {
      if (estTimer.current) clearTimeout(estTimer.current)
    }
  }, [form.food_name, form.weight_g, editing])

  const submit = async () => {
    const set = (v: string) => (v === '' ? null : Number(v))
    const payload = {
      record_date: form.record_date,
      meal_type: form.meal_type,
      food_name: form.food_name,
      weight_g: Number(form.weight_g),
      calories: set(form.calories),
      protein: set(form.protein),
      carbs: set(form.carbs),
      fat: set(form.fat),
      note: form.note === '' ? null : form.note,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/diet', editing.id, payload)
      else await api.create('/health/diet', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: DietRecord) => {
    if (!(await confirm())) return
    await api.remove('/health/diet', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const set = (key: keyof typeof EMPTY, value: string) => setForm((f) => ({ ...f, [key]: value }))

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-end gap-2">
        <StatsPeriodPicker
          value={days}
          onChange={(d) => {
            setDays(d)
            setGlobalStatsDays(d)
          }}
        />
        <Button onClick={openCreate}>
          <Plus /> 新增饮食记录
        </Button>
      </div>

      <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">总摄入热量</div>
              <div className="mt-1 text-2xl font-semibold">{stats?.total_calories ?? 0} kcal</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">总蛋白质</div>
              <div className="mt-1 text-2xl font-semibold">{stats?.total_protein ?? 0} g</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">日均热量</div>
              <div className="mt-1 text-2xl font-semibold">
                {stats?.avg_calories_per_day ?? '-'} kcal
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">今日记录数</div>
              <div className="mt-1 text-2xl font-semibold">{(stats?.trend ?? []).length}</div>
            </CardContent>
          </Card>
        </div>

      <div className="grid gap-4 lg:grid-cols-2">
          <LineChartCard
            title="每日热量摄入趋势"
            data={stats?.trend ?? []}
            xKey="record_date"
            series={[{ key: 'calories', name: '摄入(千卡)', color: '#f59e0b' }]}
          />
          <BarChartCard
            title="三餐热量分布"
            data={(stats?.by_meal ?? []).map((m) => ({ ...m, label: MEAL_LABEL[m.meal_type] ?? m.meal_type }))}
            xKey="label"
            series={[{ key: 'calories', name: '热量(kcal)', color: '#0ea5e9' }]}
          />
        </div>

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>餐次</TableHead>
                <TableHead>食物</TableHead>
                <TableHead>重量</TableHead>
                <TableHead>热量</TableHead>
                <TableHead>蛋白质</TableHead>
                <TableHead>碳水</TableHead>
                <TableHead>脂肪</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow>
                    <TableCell colSpan={9} className="h-24 text-center text-muted-foreground">
                      <Loader2 className="mx-auto size-5 animate-spin" />
                    </TableCell>
                  </TableRow>
                ) : (
                  <TableRow>
                    <TableCell colSpan={9} className="h-24 text-center text-muted-foreground">
                      暂无记录，点击"新增饮食记录"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.record_date}</TableCell>
                    <TableCell>{MEAL_LABEL[row.meal_type] ?? row.meal_type}</TableCell>
                    <TableCell>{row.food_name}</TableCell>
                    <TableCell>{row.weight_g} g</TableCell>
                    <TableCell>{row.calories} kcal</TableCell>
                    <TableCell>{row.protein ?? '-'} g</TableCell>
                    <TableCell>{row.carbs ?? '-'} g</TableCell>
                    <TableCell>{row.fat ?? '-'} g</TableCell>
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

      <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑饮食记录' : '新增饮食记录'}</DialogTitle>
            <DialogDescription>输入食物名称与重量，系统自动识别营养成分。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>
                日期 <span className="text-destructive">*</span>
              </Label>
              <DatePicker value={form.record_date} onChange={(v) => set('record_date', v)} />
            </div>
            <div className="space-y-2">
              <Label>
                餐次 <span className="text-destructive">*</span>
              </Label>
              <Select value={form.meal_type} onValueChange={(v) => set('meal_type', v)}>
                <SelectTrigger>
                  <SelectValue placeholder="请选择餐次" />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(MEAL_LABEL).map(([v, l]) => (
                    <SelectItem key={v} value={v}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2 col-span-2">
              <Label>
                食物名称 <span className="text-destructive">*</span>
              </Label>
              <Input
                list="food-list"
                value={form.food_name}
                onChange={(e) => set('food_name', e.target.value)}
                placeholder="如：鸡胸肉、米饭、苹果"
              />
              <datalist id="food-list">
                {foodHints.map((f) => (
                  <option key={f.name} value={f.name} />
                ))}
              </datalist>
            </div>
            <div className="space-y-2 col-span-2">
              <Label>
                重量（克） <span className="text-destructive">*</span>
              </Label>
              <Input
                type="number"
                step="1"
                value={form.weight_g}
                onChange={(e) => set('weight_g', e.target.value)}
                placeholder="如：150"
                disabled={!!editing}
              />
            </div>
            {['calories', 'protein', 'carbs', 'fat'].map((k) => (
              <div key={k} className="space-y-2">
                <Label>
                  {k === 'calories' ? '热量(kcal)' : k === 'protein' ? '蛋白质(g)' : k === 'carbs' ? '碳水(g)' : '脂肪(g)'}
                </Label>
                <Input
                  type="number"
                  step="0.1"
                  value={form[k as keyof typeof EMPTY]}
                  onChange={(e) => set(k as keyof typeof EMPTY, e.target.value)}
                  placeholder={estimating ? '识别中...' : '自动识别'}
                />
              </div>
            ))}
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
              disabled={saving || !form.meal_type || !form.food_name || !form.weight_g}
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