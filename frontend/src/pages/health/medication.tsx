import { useEffect, useState } from 'react'
import { AlertTriangle, Loader2, Pencil, Plus, Trash2 } from 'lucide-react'

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
import { useConfirm } from '@/components/ui/confirm-dialog'
import { BarChartCard, LineChartCard, useStats } from '@/components/health/charts'
import { api } from '@/lib/api'

type MedRecord = {
  id: number
  record_date: string
  medicine_name: string
  meal_slot: string
  dosage?: string
  taken: boolean
  note?: string
}

type MedStats = {
  today: { taken_count: number; pending_count: number; items: { id: number; medicine_name: string; meal_label: string; taken: boolean }[] }
  by_slot: { meal_slot: string; meal_label: string; total: number; taken: number }[]
  by_medicine: { medicine_name: string; count: number }[]
  adherence_rate: number
  trend: { record_date: string; total: number; taken: number }[]
}

type Purchase = {
  id: number
  buy_date: string
  medicine_name: string
  channel?: string
  unit?: string
  quantity: number
  unit_price: number
  total_price: number
  note?: string
}

type Stock = {
  id: number
  medicine_name: string
  stock_qty: number
  threshold?: number
  unit?: string
  is_low: boolean
  purchased?: number
  consumed?: number
  avg_daily?: number | null
  days_left?: number | null
  predicted_date?: string | null
}

const MEAL_LABEL: Record<string, string> = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐' }
type Tab = 'med' | 'purchase' | 'stock'

const MED_EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  medicine_name: '',
  meal_slot: 'breakfast',
  dosage: '',
  taken: '',
  note: '',
}
const PUR_EMPTY = {
  buy_date: new Date().toISOString().slice(0, 10),
  medicine_name: '',
  channel: '',
  unit: '',
  quantity: '',
  unit_price: '',
  total_price: '',
  note: '',
}
const STOCK_EMPTY = { medicine_name: '', stock_qty: '', threshold: '', unit: '' }

export function MedicationPage() {
  const [tab, setTab] = useState<Tab>('med')
  const [medItems, setMedItems] = useState<MedRecord[]>([])
  const [medTotal, setMedTotal] = useState(0)
  const [medPage, setMedPage] = useState(1)
  const [purItems, setPurItems] = useState<Purchase[]>([])
  const [stocks, setStocks] = useState<Stock[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<unknown>(null)
  const [saving, setSaving] = useState(false)
  const [medForm, setMedForm] = useState(MED_EMPTY)
  const [purForm, setPurForm] = useState(PUR_EMPTY)
  const [stockForm, setStockForm] = useState(STOCK_EMPTY)
  const { confirm, dialog: confirmDialog } = useConfirm()

  const stats = useStats<MedStats>('/health/medication')
  const PAGE_SIZE = 10
  const medPages = Math.max(1, Math.ceil(medTotal / PAGE_SIZE))

  const loadMed = async () => {
    const res = await api.list<MedRecord>('/health/medication', { page: medPage, page_size: PAGE_SIZE })
    setMedItems(res.items)
    setMedTotal(res.total)
  }

  useEffect(() => {
    setLoading(true)
    Promise.all([loadMed(), api.query<{ items: Purchase[] }>('/health/medication/purchases').then((r) => setPurItems(r.items))])
      .then(() => setLoading(false))
      .catch(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [medPage])

  useEffect(() => {
    api.query<{ items: Stock[] }>('/health/medication/stocks').then((r) => setStocks(r.items))
  }, [tab])

  const openMedCreate = () => {
    setEditing(null)
    setMedForm(MED_EMPTY)
    setDialogOpen(true)
  }
  const openMedEdit = (row: MedRecord) => {
    setEditing(row)
    setMedForm({
      record_date: row.record_date,
      medicine_name: row.medicine_name,
      meal_slot: row.meal_slot,
      dosage: row.dosage ?? '',
      taken: row.taken ? 'true' : 'false',
      note: row.note ?? '',
    })
    setDialogOpen(true)
  }
  const submitMed = async () => {
    const payload = {
      record_date: medForm.record_date,
      medicine_name: medForm.medicine_name,
      meal_slot: medForm.meal_slot,
      dosage: medForm.dosage === '' ? null : medForm.dosage,
      taken: medForm.taken === 'true',
      note: medForm.note === '' ? null : medForm.note,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/medication', (editing as MedRecord).id, payload)
      else await api.create('/health/medication', payload)
      setDialogOpen(false)
      await loadMed()
    } finally {
      setSaving(false)
    }
  }
  const removeMed = async (row: MedRecord) => {
    if (!(await confirm({ title: '确认删除', description: '确定删除这条用药记录吗？' }))) return
    await api.remove('/health/medication', row.id)
    await loadMed()
  }

  const openPurCreate = () => {
    setEditing(null)
    setPurForm(PUR_EMPTY)
    setDialogOpen(true)
  }
  const openPurEdit = (row: Purchase) => {
    setEditing(row)
    setPurForm({
      buy_date: row.buy_date,
      medicine_name: row.medicine_name,
      channel: row.channel ?? '',
      unit: row.unit ?? '',
      quantity: String(row.quantity),
      unit_price: String(row.unit_price),
      total_price: String(row.total_price ?? ''),
      note: row.note ?? '',
    })
    setDialogOpen(true)
  }
  const submitPur = async () => {
    const payload = {
      buy_date: purForm.buy_date,
      medicine_name: purForm.medicine_name,
      channel: purForm.channel === '' ? null : purForm.channel,
      unit: purForm.unit === '' ? null : purForm.unit,
      quantity: Number(purForm.quantity),
      unit_price: Number(purForm.unit_price),
      total_price: purForm.total_price === '' ? null : Number(purForm.total_price),
      note: purForm.note === '' ? null : purForm.note,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/medication/purchases', (editing as Purchase).id, payload)
      else await api.create('/health/medication/purchases', payload)
      setDialogOpen(false)
      const r = await api.query<{ items: Purchase[] }>('/health/medication/purchases')
      setPurItems(r.items)
    } finally {
      setSaving(false)
    }
  }
  const removePur = async (row: Purchase) => {
    if (!(await confirm({ title: '确认删除', description: '确定删除这条购药记录吗？' }))) return
    await api.remove('/health/medication/purchases', row.id)
    const r = await api.query<{ items: Purchase[] }>('/health/medication/purchases')
    setPurItems(r.items)
  }

  const removeStock = async (row: Stock) => {
    if (!(await confirm({ title: '确认删除', description: '确定删除该库存吗？' }))) return
    await api.remove('/health/medication/stocks', row.id)
    const r = await api.query<{ items: Stock[] }>('/health/medication/stocks')
    setStocks(r.items)
  }

  const openStockCreate = () => {
    setEditing(null)
    setStockForm(STOCK_EMPTY)
    setDialogOpen(true)
  }
  const openStockEdit = (row: Stock) => {
    setEditing(row)
    setStockForm({
      medicine_name: row.medicine_name,
      stock_qty: String(row.stock_qty),
      threshold: String(row.threshold ?? ''),
      unit: row.unit ?? '',
    })
    setDialogOpen(true)
  }
  const submitStock = async () => {
    const num = (v: string) => (v === '' ? null : Number(v))
    const payload = {
      medicine_name: stockForm.medicine_name,
      stock_qty: num(stockForm.stock_qty) ?? 0,
      threshold: num(stockForm.threshold),
      unit: stockForm.unit === '' ? null : stockForm.unit,
    }
    setSaving(true)
    try {
      if (editing) await api.put(`/health/medication/stocks/${(editing as Stock).id}`, payload)
      else await api.post('/health/medication/stocks', payload)
      setDialogOpen(false)
      const r = await api.query<{ items: Stock[] }>('/health/medication/stocks')
      setStocks(r.items)
    } finally {
      setSaving(false)
    }
  }

  const setMed = (k: keyof typeof MED_EMPTY, v: string) => setMedForm((f) => ({ ...f, [k]: v }))
  const setPur = (k: keyof typeof PUR_EMPTY, v: string) => setPurForm((f) => ({ ...f, [k]: v }))
  const setStock = (k: keyof typeof STOCK_EMPTY, v: string) => setStockForm((f) => ({ ...f, [k]: v }))

  const purchaseTotal = purItems.reduce((s, p) => s + (p.total_price || 0), 0)
  const lowCount = stocks.filter((s) => s.is_low).length

  const tabs: { key: Tab; label: string }[] = [
    { key: 'med', label: '用药记录' },
    { key: 'purchase', label: '购药记录' },
    { key: 'stock', label: `库存提醒${lowCount ? `(${lowCount})` : ''}` },
  ]

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">用药跟踪</h1>
          <p className="text-sm text-muted-foreground">记录每日早/午/晚用药、购药明细，并监控库存以触发低库存提醒。</p>
        </div>
        <div>
          {tab === 'med' && (
            <Button onClick={openMedCreate}>
              <Plus /> 新增用药
            </Button>
          )}
          {tab === 'purchase' && (
            <Button onClick={openPurCreate}>
              <Plus /> 新增购药
            </Button>
          )}
          {tab === 'stock' && (
            <Button onClick={openStockCreate}>
              <Plus /> 新增库存
            </Button>
          )}
        </div>
      </section>

      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {tabs.map((t) => (
          <Button
            key={t.key}
            variant={tab === t.key ? 'default' : 'ghost'}
            className="flex-1"
            onClick={() => setTab(t.key)}
          >
            {t.label}
          </Button>
        ))}
      </div>

      {tab === 'med' && stats && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">今日已服</div>
              <div className="mt-1 text-2xl font-semibold text-green-600">{stats.today.taken_count}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">今日待服</div>
              <div className="mt-1 text-2xl font-semibold text-amber-500">{stats.today.pending_count}</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">依从率</div>
              <div className="mt-1 text-2xl font-semibold">{stats.adherence_rate ?? '-'}%</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">低库存药品</div>
              <div className="mt-1 text-2xl font-semibold text-red-600">{lowCount}</div>
            </CardContent>
          </Card>
        </div>
      )}

      {tab === 'med' && stats && (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="今日分餐用药"
            data={stats.by_slot.map((s) => ({ ...s, label: s.meal_label }))}
            xKey="label"
            series={[
              { key: 'total', name: '计划', color: '#94a3b8' },
              { key: 'taken', name: '已服', color: '#10b981' },
            ]}
          />
          <LineChartCard
            title="每日用药趋势"
            data={stats.trend}
            xKey="record_date"
            series={[
              { key: 'total', name: '计划', color: '#94a3b8' },
              { key: 'taken', name: '已服', color: '#10b981' },
            ]}
          />
        </div>
      )}

      {tab === 'med' && (
        <Card>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>日期</TableHead>
                  <TableHead>药品</TableHead>
                  <TableHead>餐次</TableHead>
                  <TableHead>剂量</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead className="w-24 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {medItems.length === 0 && !loading ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                      暂无用药记录
                    </TableCell>
                  </TableRow>
                ) : (
                  medItems.map((row) => (
                    <TableRow key={row.id}>
                      <TableCell>{row.record_date}</TableCell>
                      <TableCell>{row.medicine_name}</TableCell>
                      <TableCell>{MEAL_LABEL[row.meal_slot] ?? row.meal_slot}</TableCell>
                      <TableCell>{row.dosage ?? '—'}</TableCell>
                      <TableCell>
                        {row.taken ? (
                          <Badge className="bg-green-100 text-green-700">已服</Badge>
                        ) : (
                          <Badge className="bg-amber-100 text-amber-700">未服</Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={() => openMedEdit(row)}>
                            <Pencil />
                          </Button>
                          <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeMed(row)}>
                            <Trash2 />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
            {medTotal > 0 && (
              <div className="flex items-center justify-between p-3 text-sm text-muted-foreground">
                <span>共 {medTotal} 条</span>
                <div className="flex items-center gap-2">
                  <Button variant="outline" size="sm" disabled={medPage <= 1} onClick={() => setMedPage(medPage - 1)}>上一页</Button>
                  <span>{medPage}/{medPages}</span>
                  <Button variant="outline" size="sm" disabled={medPage >= medPages} onClick={() => setMedPage(medPage + 1)}>下一页</Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'purchase' && (
        <>
          <div className="grid gap-4 md:grid-cols-2">
            <Card>
              <CardContent className="py-4">
                <div className="text-sm text-muted-foreground">购药总支出</div>
                <div className="mt-1 text-2xl font-semibold">¥{purchaseTotal.toFixed(2)}</div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="py-4">
                <div className="text-sm text-muted-foreground">购药记录数</div>
                <div className="mt-1 text-2xl font-semibold">{purItems.length}</div>
              </CardContent>
            </Card>
          </div>
          <Card>
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>日期</TableHead>
                    <TableHead>药品</TableHead>
                    <TableHead>渠道</TableHead>
                    <TableHead>数量·单位</TableHead>
                    <TableHead>单价</TableHead>
                    <TableHead>总价</TableHead>
                    <TableHead className="w-24 text-right">操作</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {purItems.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={7} className="h-24 text-center text-muted-foreground">暂无购药记录</TableCell>
                    </TableRow>
                  ) : (
                    purItems.map((row) => (
                      <TableRow key={row.id}>
                        <TableCell>{row.buy_date}</TableCell>
                        <TableCell>{row.medicine_name}</TableCell>
                        <TableCell>{row.channel ?? '—'}</TableCell>
                        <TableCell>{row.quantity}{row.unit ?? ''}</TableCell>
                        <TableCell>¥{row.unit_price}</TableCell>
                        <TableCell>¥{row.total_price}</TableCell>
                        <TableCell className="text-right">
                          <div className="flex justify-end gap-1">
                            <Button variant="ghost" size="icon" onClick={() => openPurEdit(row)}><Pencil /></Button>
                            <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removePur(row)}><Trash2 /></Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </>
      )}

      {tab === 'stock' && (
        <Card>
          <CardContent className="p-0">
            <div className="border-b bg-muted/30 px-4 py-2 text-xs text-muted-foreground">
              库存 = 累计购药 − 已服用次数，并按日均消耗自动预测可维持天数。
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>药品</TableHead>
                  <TableHead>当前库存</TableHead>
                  <TableHead>累计购药</TableHead>
                  <TableHead>已消耗</TableHead>
                  <TableHead>日均消耗</TableHead>
                  <TableHead>预计耗尽</TableHead>
                  <TableHead>阈值</TableHead>
                  <TableHead>状态</TableHead>
                  <TableHead className="w-24 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {stocks.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={9} className="h-24 text-center text-muted-foreground">暂无库存记录</TableCell>
                  </TableRow>
                ) : (
                  stocks.map((row) => (
                    <TableRow key={row.id}>
                      <TableCell>{row.medicine_name}</TableCell>
                      <TableCell className="font-medium">{row.stock_qty}{row.unit ?? ''}</TableCell>
                      <TableCell>{row.purchased ?? '—'}{row.unit ?? ''}</TableCell>
                      <TableCell>{row.consumed ?? 0}{row.unit ?? ''}</TableCell>
                      <TableCell>{row.avg_daily != null ? row.avg_daily.toFixed(3) : '—'}{row.unit ?? '/天'}</TableCell>
                      <TableCell>
                        {row.days_left != null ? (
                          <div className="flex items-center gap-1.5">
                            <span>约 {row.days_left} 天</span>
                            <span className="text-xs text-muted-foreground">{row.predicted_date}</span>
                          </div>
                        ) : (
                          '—'
                        )}
                      </TableCell>
                      <TableCell>{row.threshold ?? '—'}</TableCell>
                      <TableCell>
                        {row.is_low ? (
                          <Badge className="bg-red-100 text-red-700"><AlertTriangle className="mr-1 size-3" />低库存</Badge>
                        ) : (
                          <Badge className="bg-green-100 text-green-700">充足</Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={() => openStockEdit(row)}><Pencil /></Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="text-destructive"
                            onClick={() => removeStock(row)}
                          >
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
      )}

      {/* 新增/编辑弹窗 */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>
              {tab === 'med' && (editing ? '编辑用药记录' : '新增用药记录')}
              {tab === 'purchase' && (editing ? '编辑购药记录' : '新增购药记录')}
              {tab === 'stock' && (editing ? '编辑库存' : '新增库存')}
            </DialogTitle>
            <DialogDescription>
              {tab === 'med' && '按早/午/晚记录用药情况。'}
              {tab === 'purchase' && '登记购药明细，总价可自动计算。'}
              {tab === 'stock' && '记录当前库存与低库存阈值。'}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            {tab === 'med' && (
              <>
                <div className="space-y-2">
                  <Label>日期 <span className="text-destructive">*</span></Label>
                  <Input type="date" value={medForm.record_date} onChange={(e) => setMed('record_date', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>餐次</Label>
                  <Select value={medForm.meal_slot} onValueChange={(v) => setMed('meal_slot', v)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {Object.entries(MEAL_LABEL).map(([v, l]) => (
                        <SelectItem key={v} value={v}>{l}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>药品名称 <span className="text-destructive">*</span></Label>
                  <Input value={medForm.medicine_name} onChange={(e) => setMed('medicine_name', e.target.value)} />
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>剂量</Label>
                  <Input value={medForm.dosage} onChange={(e) => setMed('dosage', e.target.value)} placeholder="如：1片" />
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>是否已服用</Label>
                  <Select value={medForm.taken} onValueChange={(v) => setMed('taken', v)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="false">未服</SelectItem>
                      <SelectItem value="true">已服</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>备注</Label>
                  <Textarea value={medForm.note} onChange={(e) => setMed('note', e.target.value)} />
                </div>
              </>
            )}
            {tab === 'purchase' && (
              <>
                <div className="space-y-2">
                  <Label>购药日期 <span className="text-destructive">*</span></Label>
                  <Input type="date" value={purForm.buy_date} onChange={(e) => setPur('buy_date', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>药品名称 <span className="text-destructive">*</span></Label>
                  <Input value={purForm.medicine_name} onChange={(e) => setPur('medicine_name', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>购买渠道</Label>
                  <Input value={purForm.channel} onChange={(e) => setPur('channel', e.target.value)} placeholder="医院/药店/线上" />
                </div>
                <div className="space-y-2">
                  <Label>单位</Label>
                  <Input value={purForm.unit} onChange={(e) => setPur('unit', e.target.value)} placeholder="盒/片" />
                </div>
                <div className="space-y-2">
                  <Label>数量 <span className="text-destructive">*</span></Label>
                  <Input type="number" step="0.01" value={purForm.quantity} onChange={(e) => setPur('quantity', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>单价 <span className="text-destructive">*</span></Label>
                  <Input type="number" step="0.01" value={purForm.unit_price} onChange={(e) => setPur('unit_price', e.target.value)} />
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>总价（留空自动=数量×单价）</Label>
                  <Input type="number" step="0.01" value={purForm.total_price} onChange={(e) => setPur('total_price', e.target.value)} />
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>备注</Label>
                  <Textarea value={purForm.note} onChange={(e) => setPur('note', e.target.value)} />
                </div>
              </>
            )}
            {tab === 'stock' && (
              <>
                <div className="space-y-2 col-span-2">
                  <Label>药品名称 <span className="text-destructive">*</span></Label>
                  <Input value={stockForm.medicine_name} onChange={(e) => setStock('medicine_name', e.target.value)} />
                </div>
                <div className="space-y-2 col-span-2 rounded-lg border bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
                  库存由购药记录减用药记录自动计算，无需手动维护。
                </div>
                <div className="space-y-2">
                  <Label>低库存阈值</Label>
                  <Input type="number" step="0.01" value={stockForm.threshold} onChange={(e) => setStock('threshold', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>单位</Label>
                  <Input value={stockForm.unit} onChange={(e) => setStock('unit', e.target.value)} />
                </div>
              </>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>取消</Button>
            <Button
              onClick={tab === 'med' ? submitMed : tab === 'purchase' ? submitPur : submitStock}
              disabled={saving}
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