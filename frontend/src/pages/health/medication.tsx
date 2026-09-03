import { useEffect, useState } from 'react'
import { AlertTriangle, Loader2, Pencil, Plus, StickyNote, Trash2 } from 'lucide-react'

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
import { DatePicker } from '@/components/ui/date-picker'
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
import { Switch } from '@/components/ui/switch'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { BarChartCard, LineChartCard, StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import { api } from '@/lib/api'

type MedRecord = {
  id: number
  record_date: string
  medicine_name: string
  dose_breakfast: number
  dose_lunch: number
  dose_dinner: number
  taken_breakfast: boolean
  taken_lunch: boolean
  taken_dinner: boolean
  frequency?: string
  note?: string
}

type MedStats = {
  today: {
    taken_count: number
    pending_count: number
    items: {
      id: number
      medicine_name: string
      dose_breakfast: number
      dose_lunch: number
      dose_dinner: number
      taken_breakfast: boolean
      taken_lunch: boolean
      taken_dinner: boolean
    }[]
  }
  by_slot: { meal_slot: string; meal_label: string; total: number; taken: number }[]
  by_medicine: { medicine_name: string; count: number }[]
  adherence_rate: number | null
  trend: { record_date: string; total: number; taken: number }[]
  total_pills?: number
}

type Purchase = {
  id: number
  buy_date: string
  medicine_name: string
  channel?: string
  unit?: string
  quantity: number
  pills_per_unit?: number
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
  total_pills?: number
  avg_daily?: number | null
  days_left?: number | null
  predicted_date?: string | null
}

const MEAL_ORDER = ['breakfast', 'lunch', 'dinner'] as const
const MEAL_LABEL: Record<string, string> = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐' }
type Tab = 'med' | 'purchase' | 'stock'

const PILLS_KEY: Record<string, keyof MedRecord> = {
  breakfast: 'dose_breakfast',
  lunch: 'dose_lunch',
  dinner: 'dose_dinner',
}
const TAKEN_KEY: Record<string, keyof MedRecord> = {
  breakfast: 'taken_breakfast',
  lunch: 'taken_lunch',
  dinner: 'taken_dinner',
}

const MED_EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  medicine_name: '',
  dose_breakfast: '0',
  dose_lunch: '0',
  dose_dinner: '0',
  taken_breakfast: false,
  taken_lunch: false,
  taken_dinner: false,
  note: '',
}
const PUR_EMPTY = {
  buy_date: new Date().toISOString().slice(0, 10),
  medicine_name: '',
  channel: '',
  unit: '',
  quantity: '',
  pills_per_unit: '',
  unit_price: '',
  total_price: '',
  note: '',
}
const STOCK_EMPTY = { medicine_name: '', threshold: '' }

export function MedicationPage() {
  const [tab, setTab] = useState<Tab>('med')
  const [medItems, setMedItems] = useState<MedRecord[]>([])
  const [medTotal, setMedTotal] = useState(0)
  const [medPage, setMedPage] = useState(1)
  const [purItems, setPurItems] = useState<Purchase[]>([])
  const [purTotal, setPurTotal] = useState(0)
  const [purPage, setPurPage] = useState(1)
  const [purStats, setPurStats] = useState<{ total_count: number; total_price: number } | null>(null)
  const [stocks, setStocks] = useState<Stock[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<MedRecord | Purchase | Stock | null>(null)
  const [saving, setSaving] = useState(false)
  const [medForm, setMedForm] = useState(MED_EMPTY)
  const [purForm, setPurForm] = useState(PUR_EMPTY)
  const [stockForm, setStockForm] = useState(STOCK_EMPTY)
  const [formError, setFormError] = useState('')
  const { confirm, dialog: confirmDialog } = useConfirm()

  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const stats = useStats<MedStats>('/health/medication', days)
  const PAGE_SIZE = 10
  const medPages = Math.max(1, Math.ceil(medTotal / PAGE_SIZE))
  const purPages = Math.max(1, Math.ceil(purTotal / PAGE_SIZE))

  const loadMed = async () => {
    const res = await api.list<MedRecord>('/health/medication', { page: medPage, page_size: PAGE_SIZE })
    setMedItems(res.items)
    setMedTotal(res.total)
  }
  const loadPur = async () => {
    const res = await api.list<Purchase>('/health/medication/purchases', { page: purPage, page_size: PAGE_SIZE })
    setPurItems(res.items)
    setPurTotal(res.total)
    api
      .stats<{ total_count: number; total_price: number }>('/health/medication/purchases', 'all')
      .then(setPurStats)
      .catch(() => {})
  }
  const loadStock = async () => {
    const r = await api.query<{ items: Stock[] }>('/health/medication/stocks')
    setStocks(r.items)
  }

  useEffect(() => {
    if (tab === 'med') {
      setLoading(true)
      loadMed().finally(() => setLoading(false))
    } else if (tab === 'purchase') {
      setLoading(true)
      loadPur().finally(() => setLoading(false))
    } else {
      setLoading(true)
      loadStock().finally(() => setLoading(false))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, medPage])

  useEffect(() => {
    if (tab === 'purchase') {
      setLoading(true)
      loadPur().finally(() => setLoading(false))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [purPage])

  useEffect(() => {
    api.query<{ items: Stock[] }>('/health/medication/stocks').then((r) => setStocks(r.items))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab])

  const openMedCreate = () => {
    setEditing(null)
    setMedForm(MED_EMPTY)
    setFormError('')
    setDialogOpen(true)
  }
  const openMedEdit = (row: MedRecord) => {
    setEditing(row)
    setMedForm({
      record_date: row.record_date,
      medicine_name: row.medicine_name,
      dose_breakfast: String(row.dose_breakfast ?? 0),
      dose_lunch: String(row.dose_lunch ?? 0),
      dose_dinner: String(row.dose_dinner ?? 0),
      taken_breakfast: row.taken_breakfast,
      taken_lunch: row.taken_lunch,
      taken_dinner: row.taken_dinner,
      note: row.note ?? '',
    })
    setFormError('')
    setDialogOpen(true)
  }
  const submitMed = async () => {
    if (!medForm.record_date) {
      setFormError('请选择日期')
      return
    }
    if (!medForm.medicine_name.trim()) {
      setFormError('请填写药品名称')
      return
    }
    const toInt = (v: string) => Math.max(0, Math.floor(Number(v) || 0))
    setSaving(true)
    try {
      const payload = {
        record_date: medForm.record_date,
        medicine_name: medForm.medicine_name.trim(),
        dose_breakfast: toInt(medForm.dose_breakfast),
        dose_lunch: toInt(medForm.dose_lunch),
        dose_dinner: toInt(medForm.dose_dinner),
        taken_breakfast: medForm.taken_breakfast,
        taken_lunch: medForm.taken_lunch,
        taken_dinner: medForm.taken_dinner,
        note: medForm.note === '' ? null : medForm.note,
      }
      if (editing) await api.update('/health/medication', (editing as MedRecord).id, payload)
      else await api.create('/health/medication', payload)
      setDialogOpen(false)
      setFormError('')
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
    setFormError('')
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
      pills_per_unit: row.pills_per_unit != null ? String(row.pills_per_unit) : '',
      unit_price: String(row.unit_price),
      total_price: String(row.total_price ?? ''),
      note: row.note ?? '',
    })
    setFormError('')
    setDialogOpen(true)
  }
  const submitPur = async () => {
    if (!purForm.buy_date || !purForm.medicine_name.trim()) {
      setFormError('请填写购药日期与药品名称')
      return
    }
    if (!purForm.quantity || Number(purForm.quantity) <= 0 || !purForm.unit_price || Number(purForm.unit_price) < 0) {
      setFormError('请填写有效数量与单价')
      return
    }
    setSaving(true)
    try {
      const payload = {
        buy_date: purForm.buy_date,
        medicine_name: purForm.medicine_name.trim(),
        channel: purForm.channel === '' ? null : purForm.channel,
        unit: purForm.unit === '' ? null : purForm.unit,
        quantity: Number(purForm.quantity),
        pills_per_unit: purForm.pills_per_unit === '' ? null : Number(purForm.pills_per_unit),
        unit_price: Number(purForm.unit_price),
        total_price: purForm.total_price === '' ? null : Number(purForm.total_price),
        note: purForm.note === '' ? null : purForm.note,
      }
      if (editing) await api.update('/health/medication/purchases', (editing as Purchase).id, payload)
      else await api.create('/health/medication/purchases', payload)
      setDialogOpen(false)
      setFormError('')
      await loadPur()
      await loadStock()
    } finally {
      setSaving(false)
    }
  }
  const removePur = async (row: Purchase) => {
    if (!(await confirm({ title: '确认删除', description: '确定删除这条购药记录吗？' }))) return
    await api.remove('/health/medication/purchases', row.id)
    await loadPur()
    await loadStock()
  }

  const removeStock = async (row: Stock) => {
    if (!(await confirm({ title: '确认删除', description: '确定删除该库存吗？' }))) return
    await api.remove('/health/medication/stocks', row.id)
    await loadStock()
  }
  const submitStock = async () => {
    if (!stockForm.medicine_name.trim()) {
      setFormError('请填写药品名称')
      return
    }
    setSaving(true)
    try {
      const payload = {
        medicine_name: stockForm.medicine_name.trim(),
        stock_qty: 0,
        threshold: stockForm.threshold === '' ? null : Number(stockForm.threshold),
        unit: '粒',
      }
      if (editing) await api.put(`/health/medication/stocks/${(editing as Stock).id}`, payload)
      else await api.post('/health/medication/stocks', payload)
      setDialogOpen(false)
      setFormError('')
      await loadStock()
    } finally {
      setSaving(false)
    }
  }

  const setMed = (k: keyof typeof MED_EMPTY, v: string | boolean) =>
    setMedForm((f) => ({ ...f, [k]: v }))
  const setPur = (k: keyof typeof PUR_EMPTY, v: string) => setPurForm((f) => ({ ...f, [k]: v }))
  const setStock = (k: keyof typeof STOCK_EMPTY, v: string) => setStockForm((f) => ({ ...f, [k]: v }))

  const openStockCreate = () => {
    setEditing(null)
    setStockForm(STOCK_EMPTY)
    setFormError('')
    setDialogOpen(true)
  }
  const openStockEdit = (row: Stock) => {
    setEditing(row)
    setStockForm({
      medicine_name: row.medicine_name,
      threshold: row.threshold != null ? String(row.threshold) : '',
    })
    setFormError('')
    setDialogOpen(true)
  }

  const purchaseTotal = purStats?.total_price ?? 0
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
          <p className="text-sm text-muted-foreground">每日按早/午/晚记录剂量与服用情况，登记购药并按粒监控库存。</p>
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

      {tab === 'med' && (
        <div className="flex justify-end">
          <StatsPeriodPicker
            value={days}
            onChange={(d) => {
              setDays(d)
              setGlobalStatsDays(d)
            }}
          />
        </div>
      )}

      {tab === 'med' && (
        <div className="grid gap-4 md:grid-cols-4">
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">今日已服</div>
              <div className="mt-1 text-2xl font-semibold text-green-600">{stats?.today?.taken_count ?? 0} 粒</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">今日待服</div>
              <div className="mt-1 text-2xl font-semibold text-amber-500">{stats?.today?.pending_count ?? 0} 粒</div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4">
              <div className="text-sm text-muted-foreground">依从率</div>
              <div className="mt-1 text-2xl font-semibold">{stats?.adherence_rate ?? '-'}%</div>
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

      {tab === 'med' && (
        <div className="grid gap-4 lg:grid-cols-2">
          <BarChartCard
            title="今日分餐用药"
            data={(stats?.by_slot ?? []).map((s) => ({ ...s, label: s.meal_label }))}
            xKey="label"
            series={[
              { key: 'total', name: '计划(粒)', color: '#94a3b8' },
              { key: 'taken', name: '已服(粒)', color: '#10b981' },
            ]}
          />
          <LineChartCard
            title="每日用药趋势"
            data={stats?.trend ?? []}
            xKey="record_date"
            series={[
              { key: 'total', name: '计划(粒)', color: '#94a3b8' },
              { key: 'taken', name: '已服(粒)', color: '#10b981' },
            ]}
          />
        </div>
      )}

      {tab === 'med' && (
        <Card>
          <CardContent className="p-0">
            <div className="border-b bg-muted/30 px-4 py-2 text-xs text-muted-foreground">
              同一药品同一天合并为一行，剂量按粒、餐次按 早/午/晚 填 1/0/0。
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>日期</TableHead>
                  <TableHead>药品</TableHead>
                  <TableHead>早餐</TableHead>
                  <TableHead>午餐</TableHead>
                  <TableHead>晚餐</TableHead>
                  <TableHead>服用状态</TableHead>
                  <TableHead>备注</TableHead>
                  <TableHead className="w-24 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody className={`transition-opacity duration-200 ${loading ? 'pointer-events-none opacity-60' : ''}`}>
                {medItems.length === 0 ? (
                  loading ? (
                    <TableRow>
                      <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                        <Loader2 className="mx-auto size-5 animate-spin" />
                      </TableCell>
                    </TableRow>
                  ) : (
                    <TableRow>
                      <TableCell colSpan={8} className="h-24 text-center text-muted-foreground">
                        暂无用药记录
                      </TableCell>
                    </TableRow>
                  )
                ) : (
                  medItems.map((row) => (
                    <TableRow key={row.id}>
                      <TableCell>
                        <span className="inline-flex items-center gap-1">
                          {row.record_date}
                          {row.note && (
                            <StickyNote className="size-3.5 text-amber-500" />
                          )}
                        </span>
                      </TableCell>
                      <TableCell>{row.medicine_name}</TableCell>
                      {MEAL_ORDER.map((meal) => {
                        const dose = row[PILLS_KEY[meal]] as number
                        const taken = row[TAKEN_KEY[meal]] as boolean
                        return (
                          <TableCell key={meal}>
                            <span className={dose ? (taken ? 'font-medium text-green-600' : 'font-medium') : 'text-muted-foreground'}>
                              {dose || '—'}
                            </span>
                          </TableCell>
                        )
                      })}
                      <TableCell>
                        <div className="flex gap-1">
                          {MEAL_ORDER.map((meal) => {
                            const taken = row[TAKEN_KEY[meal]] as boolean
                            const dose = row[PILLS_KEY[meal]] as number
                            if (!dose) return null
                            return taken ? (
                              <Badge key={meal} className="bg-green-100 text-green-700">
                                {MEAL_LABEL[meal]}已服
                              </Badge>
                            ) : (
                              <Badge key={meal} className="bg-amber-100 text-amber-700">
                                {MEAL_LABEL[meal]}未服
                              </Badge>
                            )
                          })}
                          {row.dose_breakfast + row.dose_lunch + row.dose_dinner === 0 && <span className="text-xs text-muted-foreground">无剂量</span>}
                        </div>
                      </TableCell>
                      <TableCell>
                        {row.note ? (
                          <span
                            title={row.note}
                            className="block max-w-64 truncate text-xs text-muted-foreground"
                          >
                            {row.note}
                          </span>
                        ) : (
                          '—'
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
              <div className="p-3">
                <PaginationBar page={medPage} totalPages={medPages} total={medTotal} onPageChange={setMedPage} />
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
                <div className="mt-1 text-2xl font-semibold">{purStats?.total_count ?? purTotal}</div>
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
                    <TableHead>每盒/瓶粒</TableHead>
                    <TableHead>购入粒数</TableHead>
                    <TableHead>单价</TableHead>
                    <TableHead>总价</TableHead>
                    <TableHead className="w-24 text-right">操作</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody className={`transition-opacity duration-200 ${loading ? 'pointer-events-none opacity-60' : ''}`}>
                  {purItems.length === 0 ? (
                    loading ? (
                      <TableRow>
                        <TableCell colSpan={9} className="h-24 text-center text-muted-foreground">
                          <Loader2 className="mx-auto size-5 animate-spin" />
                        </TableCell>
                      </TableRow>
                    ) : (
                      <TableRow>
                        <TableCell colSpan={9} className="h-24 text-center text-muted-foreground">暂无购药记录</TableCell>
                      </TableRow>
                    )
                  ) : (
                    purItems.map((row) => (
                      <TableRow key={row.id}>
                        <TableCell>{row.buy_date}</TableCell>
                        <TableCell>{row.medicine_name}</TableCell>
                        <TableCell>{row.channel ?? '—'}</TableCell>
                        <TableCell>
                          {row.quantity}
                          {row.unit ?? ''}
                        </TableCell>
                        <TableCell>{row.pills_per_unit != null ? `${row.pills_per_unit} 粒` : '—'}</TableCell>
                        <TableCell>{row.quantity * (row.pills_per_unit ?? 0)} 粒</TableCell>
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
              {purTotal > 0 && (
                <div className="p-3">
                  <PaginationBar page={purPage} totalPages={purPages} total={purTotal} onPageChange={setPurPage} />
                </div>
              )}
            </CardContent>
          </Card>
        </>
      )}

      {tab === 'stock' && (
        <Card>
          <CardContent className="p-0">
            <div className="border-b bg-muted/30 px-4 py-2 text-xs text-muted-foreground">
              库存(粒) = 累计购入粒数(Σ 盒/瓶 × 每盒/瓶粒) − 已服用粒数，并按日均消耗自动预测可维持天数。
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>药品</TableHead>
                  <TableHead>当前库存</TableHead>
                  <TableHead>累计购入</TableHead>
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
                      <TableCell className="font-medium">
                        {row.stock_qty} {row.unit ?? '粒'}
                      </TableCell>
                      <TableCell>{row.purchased ?? '—'} 粒</TableCell>
                      <TableCell>{row.consumed ?? 0} 粒</TableCell>
                      <TableCell>{row.avg_daily != null ? row.avg_daily.toFixed(3) : '—'} 粒/天</TableCell>
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
                      <TableCell>{row.threshold ?? '—'} 粒</TableCell>
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

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>
              {tab === 'med' && (editing ? '编辑用药记录' : '新增用药记录')}
              {tab === 'purchase' && (editing ? '编辑购药记录' : '新增购药记录')}
              {tab === 'stock' && (editing ? '编辑库存' : '新增库存')}
            </DialogTitle>
            <DialogDescription>
              {tab === 'med' && '同一药品同一天一行，早/午/晚剂量按粒填写，未服用填写 0。'}
              {tab === 'purchase' && '登记购药明细与每盒/瓶粒数，总价可自动计算。'}
              {tab === 'stock' && '设置低库存阈值，库存自动按粒统计。'}
            </DialogDescription>
          </DialogHeader>
          {formError && (
            <div className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{formError}</div>
          )}
          <div className="grid grid-cols-2 gap-4">
            {tab === 'med' && (
              <>
                <div className="space-y-2">
                  <Label>日期 <span className="text-destructive">*</span></Label>
                  <DatePicker value={medForm.record_date} onChange={(v) => setMed('record_date', v)} />
                </div>
                <div className="space-y-2">
                  <Label>药品名称 <span className="text-destructive">*</span></Label>
                  <Input value={medForm.medicine_name} onChange={(e) => setMed('medicine_name', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>早餐剂量（粒）</Label>
                  <Input
                    type="number"
                    step="1"
                    min={0}
                    value={medForm.dose_breakfast}
                    onChange={(e) => setMed('dose_breakfast', e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>午餐剂量（粒）</Label>
                  <Input
                    type="number"
                    step="1"
                    min={0}
                    value={medForm.dose_lunch}
                    onChange={(e) => setMed('dose_lunch', e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>晚餐剂量（粒）</Label>
                  <Input
                    type="number"
                    step="1"
                    min={0}
                    value={medForm.dose_dinner}
                    onChange={(e) => setMed('dose_dinner', e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>早餐已服</Label>
                  <Switch checked={medForm.taken_breakfast} onCheckedChange={(v) => setMed('taken_breakfast', v)} />
                </div>
                <div className="space-y-2">
                  <Label>午餐已服</Label>
                  <Switch checked={medForm.taken_lunch} onCheckedChange={(v) => setMed('taken_lunch', v)} />
                </div>
                <div className="space-y-2">
                  <Label>晚餐已服</Label>
                  <Switch checked={medForm.taken_dinner} onCheckedChange={(v) => setMed('taken_dinner', v)} />
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
                  <DatePicker value={purForm.buy_date} onChange={(v) => setPur('buy_date', v)} />
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
                  <Input value={purForm.unit} onChange={(e) => setPur('unit', e.target.value)} placeholder="盒/瓶" />
                </div>
                <div className="space-y-2">
                  <Label>数量 <span className="text-destructive">*</span></Label>
                  <Input type="number" step="0.01" min={0} value={purForm.quantity} onChange={(e) => setPur('quantity', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>每盒/瓶粒数</Label>
                  <Input type="number" step="1" min={0} value={purForm.pills_per_unit} onChange={(e) => setPur('pills_per_unit', e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>单价 <span className="text-destructive">*</span></Label>
                  <Input type="number" step="0.01" min={0} value={purForm.unit_price} onChange={(e) => setPur('unit_price', e.target.value)} />
                </div>
                <div className="space-y-2">
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
                  库存由购药记录(按粒)减已服用粒数自动计算，无需手动维护。
                </div>
                <div className="space-y-2 col-span-2">
                  <Label>低库存阈值（粒）</Label>
                  <Input type="number" step="1" min={0} value={stockForm.threshold} onChange={(e) => setStock('threshold', e.target.value)} />
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