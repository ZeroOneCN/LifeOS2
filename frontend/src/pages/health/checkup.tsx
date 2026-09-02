import { useEffect, useState } from 'react'
import { Loader2, Pencil, Plus, Trash2 } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
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
import { Textarea } from '@/components/ui/textarea'
import { useStats } from '@/components/health/charts'
import { api } from '@/lib/api'

type CheckupRecord = {
  id: number
  check_date: string
  item_name: string
  value?: number
  unit?: string
  ref_low?: number
  ref_high?: number
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
  status_counts: { normal: number; high: number; low: number }
  abnormal_items: { check_date: string; value?: number; result?: string }[]
}

type Template = { id: number; item_name: string; category?: string; unit?: string; ref_low?: number; ref_high?: number }

const resultMeta: Record<string, { label: string; className: string }> = {
  normal: { label: '正常', className: 'bg-green-100 text-green-700' },
  high: { label: '偏高', className: 'bg-red-100 text-red-700' },
  low: { label: '偏低', className: 'bg-amber-100 text-amber-700' },
}

const EMPTY = {
  check_date: new Date().toISOString().slice(0, 10),
  template_id: '',
  item_name: '',
  value: '',
  unit: '',
  ref_low: '',
  ref_high: '',
  reference_range: '',
  note: '',
}

function judge(value: string, lo: string, hi: string): string {
  const v = Number(value)
  if (Number.isNaN(v)) return ''
  if (hi !== '' && v > Number(hi)) return 'high'
  if (lo !== '' && v < Number(lo)) return 'low'
  return 'normal'
}

export function CheckupPage() {
  const [items, setItems] = useState<CheckupRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<CheckupRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [templates, setTemplates] = useState<Template[]>([])

  const stats = useStats<CheckupStats>('/health/checkup')
  const PAGE_SIZE = 20
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const computedResult = judge(form.value, form.ref_low, form.ref_high)

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<CheckupRecord>('/health/checkup', { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    api.query<{ items: Template[] }>('/health/checkup/templates/standard').then((r) => setTemplates(r.items))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page])

  const openCreate = () => {
    setEditing(null)
    setForm(EMPTY)
    setDialogOpen(true)
  }

  const openEdit = (row: CheckupRecord) => {
    setEditing(row)
    setForm({
      check_date: row.check_date,
      template_id: '',
      item_name: row.item_name,
      value: String(row.value ?? ''),
      unit: row.unit ?? '',
      ref_low: String(row.ref_low ?? ''),
      ref_high: String(row.ref_high ?? ''),
      reference_range: row.reference_range ?? '',
      note: row.note ?? '',
    })
    setDialogOpen(true)
  }

  const set = (key: keyof typeof EMPTY | 'ref_low' | 'ref_high' | 'value', value: string) =>
    setForm((f) => ({ ...f, [key]: value }))

  // 选择标准模板自动填充指标/单位/参考范围
  const selectTemplate = (tplId: string) => {
    const tpl = templates.find((t) => String(t.id) === tplId)
    if (!tpl) return
    setForm((f) => ({
      ...f,
      template_id: tplId,
      item_name: tpl.item_name,
      unit: tpl.unit ?? '',
      ref_low: String(tpl.ref_low ?? ''),
      ref_high: String(tpl.ref_high ?? ''),
      reference_range: tpl.ref_low != null || tpl.ref_high != null
        ? `${tpl.ref_low ?? ''}~${tpl.ref_high ?? ''}`
        : '',
    }))
  }

  const submit = async () => {
    const num = (v: string) => (v === '' ? null : Number(v))
    const payload = {
      check_date: form.check_date,
      template_id: num(form.template_id),
      item_name: form.item_name,
      value: num(form.value),
      unit: form.unit === '' ? null : form.unit,
      ref_low: num(form.ref_low),
      ref_high: num(form.ref_high),
      reference_range: form.reference_range === '' ? null : form.reference_range,
      result: computedResult || null,
      note: form.note === '' ? null : form.note,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/checkup', editing.id, payload)
      else await api.create('/health/checkup', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: CheckupRecord) => {
    if (!window.confirm('确定删除这条体检记录吗？')) return
    await api.remove('/health/checkup', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const sc = stats?.status_counts

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">体检指标</h1>
          <p className="text-sm text-muted-foreground">使用标准模板录入，依据参考范围自动判断正常/异常，并提供分析。</p>
        </div>
        <Button onClick={openCreate}>
          <Plus /> 新增体检记录
        </Button>
      </section>

      {stats && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">异常指标</div>
              <div className="mt-1 text-2xl font-semibold text-red-600">{stats.abnormal_count} 项</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">正常</div>
              <div className="mt-1 text-2xl font-semibold text-green-600">{sc?.normal ?? 0} 项</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">偏高</div>
              <div className="mt-1 text-2xl font-semibold text-red-500">{sc?.high ?? 0} 项</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">偏低</div>
              <div className="mt-1 text-2xl font-semibold text-amber-500">{sc?.low ?? 0} 项</div>
            </CardContent>
          </Card>
        </div>
      )}

      {stats && stats.items.length > 0 && (
        <Card>
          <CardContent className="py-4">
            <div className="mb-2 text-sm font-medium text-muted-foreground">医院式分析</div>
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {stats.items.map((item) => (
                <div key={item.item_name} className="flex items-center justify-between rounded-lg border p-3">
                  <div>
                    <div className="text-sm font-medium">{item.item_name}</div>
                    <div className="text-xs text-muted-foreground">
                      参考 {item.reference_range ?? '—'} · {item.count} 次
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-lg font-semibold">
                      {item.latest?.value != null ? item.latest.value : '—'}
                      <span className="ml-1 text-xs font-normal text-muted-foreground">{item.unit ?? ''}</span>
                    </div>
                    {item.latest?.result && (
                      <Badge className={resultMeta[item.latest.result]?.className}>
                        {resultMeta[item.latest.result]?.label}
                      </Badge>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>检查日期</TableHead>
                <TableHead>指标</TableHead>
                <TableHead>数值</TableHead>
                <TableHead>单位</TableHead>
                <TableHead>参考范围</TableHead>
                <TableHead>结果</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell colSpan={7} className="h-24 text-center text-muted-foreground">
                    <Loader2 className="mx-auto size-5 animate-spin" />
                  </TableCell>
                </TableRow>
              ) : items.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={7} className="h-24 text-center text-muted-foreground">
                    暂无记录，点击"新增体检记录"添加第一条数据
                  </TableCell>
                </TableRow>
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.check_date}</TableCell>
                    <TableCell>{row.item_name}</TableCell>
                    <TableCell>{row.value != null ? row.value : '—'}</TableCell>
                    <TableCell>{row.unit ?? '—'}</TableCell>
                    <TableCell>{row.reference_range ?? '—'}</TableCell>
                    <TableCell>
                      {row.result ? (
                        <Badge className={resultMeta[row.result]?.className}>
                          {resultMeta[row.result]?.label ?? row.result}
                        </Badge>
                      ) : (
                        '—'
                      )}
                    </TableCell>
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
            <DialogTitle>{editing ? '编辑体检记录' : '新增体检记录'}</DialogTitle>
            <DialogDescription>选择标准模板或自定义，依据参考范围自动判断结果。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>
                检查日期 <span className="text-destructive">*</span>
              </Label>
              <Input type="date" value={form.check_date} onChange={(e) => set('check_date', e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>标准模板</Label>
              <Select value={form.template_id} onValueChange={selectTemplate} disabled={!!editing}>
                <SelectTrigger>
                  <SelectValue placeholder="选择模板自动填充" />
                </SelectTrigger>
                <SelectContent>
                  {templates.map((t) => (
                    <SelectItem key={t.id} value={String(t.id)}>
                      {t.category ? `[${t.category}] ` : ''}
                      {t.item_name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2 col-span-2">
              <Label>
                指标名称 <span className="text-destructive">*</span>
              </Label>
              <Input value={form.item_name} onChange={(e) => set('item_name', e.target.value)} disabled={!!editing} />
            </div>
            <div className="space-y-2">
              <Label>
                数值 <span className="text-destructive">*</span>
              </Label>
              <Input type="number" step="0.01" value={form.value} onChange={(e) => set('value', e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>单位</Label>
              <Input value={form.unit} onChange={(e) => set('unit', e.target.value)} disabled={!!editing} />
            </div>
            <div className="space-y-2">
              <Label>参考下限</Label>
              <Input type="number" step="0.01" value={form.ref_low} onChange={(e) => set('ref_low', e.target.value)} disabled={!!editing} />
            </div>
            <div className="space-y-2">
              <Label>参考上限</Label>
              <Input type="number" step="0.01" value={form.ref_high} onChange={(e) => set('ref_high', e.target.value)} disabled={!!editing} />
            </div>
            <div className="space-y-2 col-span-2">
              <Label>结果（自动判断）</Label>
              <div className="flex items-center gap-2 text-sm">
                {computedResult ? (
                  <>
                    <Badge className={resultMeta[computedResult]?.className}>
                      {resultMeta[computedResult]?.label}
                    </Badge>
                    <span className="text-muted-foreground">依据参考范围自动判断</span>
                  </>
                ) : (
                  <span className="text-muted-foreground">输入数值与参考范围后自动判断</span>
                )}
              </div>
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
            <Button onClick={submit} disabled={saving || !form.check_date || !form.item_name || form.value === ''}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}