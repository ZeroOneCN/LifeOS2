import { useEffect, useState } from 'react'
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
import { LineChartCard, useStats } from '@/components/health/charts'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { api } from '@/lib/api'

type BodyRecord = Record<string, unknown> & { id: number }

type BodyStats = {
  latest?: {
    record_date: string
    height_cm?: number
    weight_kg?: number
    bmi?: number
    body_fat_percent?: number
    muscle_percent?: number
  } | null
  trend: { record_date: string; weight_kg?: number; bmi?: number; body_fat_percent?: number; muscle_percent?: number }[]
  avg_bmi?: number
  avg_weight?: number
  max_weight?: number
  min_weight?: number
  changes: Record<string, number>
}

const COMPOSITION = [
  { key: 'body_fat_percent', label: '体脂率', unit: '%' },
  { key: 'fat_mass_kg', label: '脂肪量', unit: 'kg' },
  { key: 'visceral_fat', label: '内脏脂肪', unit: '等级' },
  { key: 'subcutaneous_fat_percent', label: '皮下脂肪率', unit: '%' },
  { key: 'subcutaneous_fat_kg', label: '皮下脂肪量', unit: 'kg' },
  { key: 'muscle_percent', label: '肌肉率', unit: '%' },
  { key: 'muscle_kg', label: '肌肉量', unit: 'kg' },
  { key: 'skeletal_muscle_percent', label: '骨骼肌率', unit: '%' },
  { key: 'skeletal_muscle_kg', label: '骨骼肌量', unit: 'kg' },
  { key: 'water_percent', label: '水分率', unit: '%' },
  { key: 'water_kg', label: '水分量', unit: 'kg' },
  { key: 'protein_percent', label: '蛋白质占比', unit: '%' },
  { key: 'protein_kg', label: '蛋白质含量', unit: 'kg' },
  { key: 'bone_percent', label: '骨量占比', unit: '%' },
  { key: 'bone_kg', label: '骨量', unit: 'kg' },
]

const SHAPE = [
  { key: 'foot_length_cm', label: '足长', unit: 'cm', male: true, female: true },
  { key: 'waist_circumference_cm', label: '腰围', unit: 'cm', male: true, female: true },
  { key: 'hip_circumference_cm', label: '臀围', unit: 'cm', male: true, female: true },
  { key: 'chest_circumference_cm', label: '胸围', unit: 'cm', male: true, female: true },
  { key: 'neck_circumference_cm', label: '颈围', unit: 'cm', male: true, female: true },
]

const EMPTY: Record<string, string> = {
  record_date: new Date().toISOString().slice(0, 10),
  gender: 'male',
  height_cm: '',
  weight_kg: '',
  ...Object.fromEntries(COMPOSITION.map((c) => [c.key, ''])),
  ...Object.fromEntries(SHAPE.map((s) => [s.key, ''])),
  note: '',
}

export function BodyPage() {
  const [items, setItems] = useState<BodyRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<BodyRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条体重记录吗？此操作不可恢复。',
  })

  const stats = useStats<BodyStats>('/health/body')
  const PAGE_SIZE = 10
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const gender = form.gender === 'female' ? 'female' : 'male'

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<BodyRecord>('/health/body', { page, page_size: PAGE_SIZE })
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

  const openEdit = (row: BodyRecord) => {
    setEditing(row)
    const f: Record<string, string> = { record_date: '', gender: 'male', ...EMPTY }
    for (const key of Object.keys(EMPTY)) {
      const v = row[key]
      f[key] = v === null || v === undefined ? '' : String(v)
    }
    setForm(f)
    setDialogOpen(true)
  }

  const set = (key: string, value: string) => setForm((prev) => ({ ...prev, [key]: value }))

  const bmiValue = (() => {
    const h = Number(form.height_cm)
    const w = Number(form.weight_kg)
    if (h > 0 && w > 0) return (w / (h / 100) ** 2).toFixed(1)
    return '-'
  })()

  const submit = async () => {
    const set = (v: string) => (v === '' ? null : Number(v))
    const payload: Record<string, unknown> = {
      record_date: form.record_date,
      gender: form.gender,
      note: form.note === '' ? null : form.note,
    }
    for (const k of ['height_cm', 'weight_kg', ...COMPOSITION.map((c) => c.key), ...SHAPE.map((s) => s.key)]) {
      payload[k] = set(form[k])
    }
    if (payload.height_cm && payload.weight_kg) {
      const h = (payload.height_cm as number) / 100
      payload.bmi = Math.round((payload.weight_kg as number) / (h * h) * 10) / 10
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/body', editing.id, payload)
      else await api.create('/health/body', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: BodyRecord) => {
    if (!(await confirm())) return
    await api.remove('/health/body', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const n = (v: unknown) => (typeof v === 'number' ? v.toFixed(1) : '-')

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Button onClick={openCreate}>
          <Plus /> 新增体重记录
        </Button>
      </div>

      {stats && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">当前体重</div>
              <div className="mt-1 text-2xl font-semibold">{stats.latest?.weight_kg ?? '-'} kg</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">最新 BMI</div>
              <div className="mt-1 text-2xl font-semibold">{stats.latest?.bmi ?? '-'}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">体脂率</div>
              <div className="mt-1 text-2xl font-semibold">
                {stats.latest?.body_fat_percent != null ? `${stats.latest.body_fat_percent}%` : '-'}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">平均体重</div>
              <div className="mt-1 text-2xl font-semibold">
                {stats.avg_weight ?? '-'} kg
                <span className="ml-2 text-sm text-muted-foreground">({stats.min_weight ?? '-'} ~ {stats.max_weight ?? '-'})</span>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {stats && (
        <div className="grid gap-4 lg:grid-cols-2">
          <LineChartCard
            title="体重趋势"
            data={stats.trend}
            xKey="record_date"
            series={[{ key: 'weight_kg', name: '体重(kg)', color: '#6366f1' }]}
          />
          <LineChartCard
            title="BMI 与体脂率趋势"
            data={stats.trend}
            xKey="record_date"
            series={[
              { key: 'bmi', name: 'BMI', color: '#10b981' },
              { key: 'body_fat_percent', name: '体脂率(%)', color: '#f43f5e' },
            ]}
          />
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>性别</TableHead>
                <TableHead>身高</TableHead>
                <TableHead>体重</TableHead>
                <TableHead>BMI</TableHead>
                <TableHead>体脂率</TableHead>
                <TableHead>肌肉率</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow>
                    <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                      <Loader2 className="mx-auto size-5 animate-spin" />
                    </TableCell>
                  </TableRow>
                ) : (
                  <TableRow>
                    <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                      暂无记录，点击"新增体重记录"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{String(row.record_date)}</TableCell>
                    <TableCell>{row.gender === 'female' ? '女' : '男'}</TableCell>
                    <TableCell>{n(row.height_cm)} cm</TableCell>
                    <TableCell>{n(row.weight_kg)} kg</TableCell>
                    <TableCell>{n(row.bmi)}</TableCell>
                    <TableCell>{n(row.body_fat_percent)} %</TableCell>
                    <TableCell>{n(row.muscle_percent)} %</TableCell>
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
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑体重记录' : '新增体重记录'}</DialogTitle>
            <DialogDescription>录入身高体重自动计算 BMI，体重记录已从睡眠体征迁出。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-3 gap-4">
            <div className="space-y-2">
              <Label>
                日期 <span className="text-destructive">*</span>
              </Label>
              <DatePicker value={form.record_date} onChange={(v) => set('record_date', v)} />
            </div>
            <div className="space-y-2">
              <Label>性别</Label>
              <Select value={form.gender} onValueChange={(v) => set('gender', v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="male">男</SelectItem>
                  <SelectItem value="female">女</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>身高(cm)</Label>
              <Input type="number" step="0.1" value={form.height_cm} onChange={(e) => set('height_cm', e.target.value)} placeholder="170" />
            </div>
            <div className="space-y-2">
              <Label>体重(kg)</Label>
              <Input type="number" step="0.1" value={form.weight_kg} onChange={(e) => set('weight_kg', e.target.value)} placeholder="65" />
            </div>
            <div className="space-y-2 col-span-2 flex items-end">
              <div className="text-sm text-muted-foreground">BMI：<span className="font-semibold text-foreground">{bmiValue}</span>（自动计算）</div>
            </div>
          </div>

          <div className="mt-2 text-sm font-medium text-muted-foreground">身体成分</div>
          <div className="grid grid-cols-3 gap-4">
            {COMPOSITION.map((c) => (
              <div key={c.key} className="space-y-2">
                <Label>{c.label}</Label>
                <Input type="number" step="0.1" value={form[c.key]} onChange={(e) => set(c.key, e.target.value)} placeholder={c.unit} />
              </div>
            ))}
          </div>

          <div className="mt-2 text-sm font-medium text-muted-foreground">
            身材参数（{gender === 'female' ? '女' : '男'}）
          </div>
          <div className="grid grid-cols-3 gap-4">
            {SHAPE.filter((s) => s[gender as 'male' | 'female']).map((s) => (
              <div key={s.key} className="space-y-2">
                <Label>{s.label}</Label>
                <Input type="number" step="0.1" value={form[s.key]} onChange={(e) => set(s.key, e.target.value)} placeholder={s.unit} />
              </div>
            ))}
          </div>

          <div className="space-y-2">
            <Label>备注</Label>
            <Input value={form.note} onChange={(e) => set('note', e.target.value)} />
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={submit} disabled={saving || !form.record_date}>
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