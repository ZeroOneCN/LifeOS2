import { useEffect, useRef, useState } from 'react'
import {
  BookOpen,
  Loader2,
  Pencil,
  Plus,
  Settings2,
  Trash2,
  Upload,
  Wallet,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
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
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'
import { toast } from 'sonner'

const PAGE_SIZE = 10

type Ledger = { id: number; name: string }
type Platform = { id: number; name: string }

type Record = {
  id: number
  record_date: string
  platform_id?: number
  platform_name?: string
  product_name: string
  spec?: string
  total_price: number
  unit_price?: number
  order_no?: string
  ledger_id?: number
  note?: string
}

type Stats = {
  total: number
  count: number
  monthly_trend: { month: string; amount: number }[]
  by_platform: { platform_id: number; platform: string; amount: number }[]
  by_ledger: { ledger_id: number; ledger: string; amount: number }[]
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

type RecordForm = {
  record_date: string
  platform_id: string
  product_name: string
  spec: string
  total_price: string
  unit_price: string
  order_no: string
  ledger_id: string
  note: string
}

const emptyForm: RecordForm = {
  record_date: new Date().toISOString().slice(0, 10),
  platform_id: '',
  product_name: '',
  spec: '',
  total_price: '',
  unit_price: '',
  order_no: '',
  ledger_id: '',
  note: '',
}

function StatCard({ icon: Icon, label, value, hint }: { icon: typeof Wallet; label: string; value: string; hint?: string }) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

export function ShoppingPage() {
  const [ledgers, setLedgers] = useState<Ledger[]>([])
  const [platforms, setPlatforms] = useState<Platform[]>([])
  const [currentLedger, setCurrentLedger] = useState<string>('')

  const [records, setRecords] = useState<Record[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [stats, setStats] = useState<Stats | null>(null)
  const [refresh, setRefresh] = useState(0)

  // 弹窗状态
  const [ledgerDialog, setLedgerDialog] = useState<null | { mode: 'create' } | { mode: 'rename'; id: number; name: string }>(null)
  const [ledgerName, setLedgerName] = useState('')
  const [platformDialog, setPlatformDialog] = useState(false)
  const [newPlatform, setNewPlatform] = useState('')
  const [recordDialog, setRecordDialog] = useState(false)
  const [editing, setEditing] = useState<Record | null>(null)
  const [form, setForm] = useState<RecordForm>(emptyForm)
  const [saving, setSaving] = useState(false)

  const fileRef = useRef<HTMLInputElement>(null)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const loadLedgers = async () => {
    const res = await api.list<Ledger>('/finance/shopping/ledgers', { page_size: 100 })
    setLedgers(res.items)
    return res.items
  }
  const loadPlatforms = async () => {
    const res = await api.list<Platform>('/finance/shopping/platforms', { page_size: 100 })
    setPlatforms(res.items)
  }

  useEffect(() => {
    loadLedgers()
    loadPlatforms()
  }, [])

  useEffect(() => {
    const ledgerParam = currentLedger ? Number(currentLedger) : undefined
    setLoading(true)
    api
      .list<Record>('/finance/shopping/records', {
        page,
        page_size: PAGE_SIZE,
        extra: { ledger_id: ledgerParam },
      })
      .then((res) => {
        setRecords(res.items)
        setTotal(res.total)
      })
      .finally(() => setLoading(false))
    loadStats()
  }, [currentLedger, page, refresh])

  const loadStats = () => {
    const ledgerParam = currentLedger ? Number(currentLedger) : undefined
    api
      .query<Stats>(`/finance/shopping/records/stats?days=3650${currentLedger ? `&ledger_id=${ledgerParam}` : ''}`)
      .then(setStats)
      .catch(() => setStats(null))
  }

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  // 账本操作
  const openCreateLedger = () => {
    setLedgerName('')
    setLedgerDialog({ mode: 'create' })
  }
  const saveLedger = async () => {
    const name = ledgerName.trim()
    if (!name) return
    const mode = ledgerDialog?.mode
    if (mode === 'create') {
      const item = await api.create<Ledger>('/finance/shopping/ledgers', { name })
      const next = await loadLedgers()
      setCurrentLedger(String(item.id))
      setPage(1)
      setLedgerDialog(null)
      setLedgers(next)
    } else if (mode === 'rename' && ledgerDialog) {
      await api.update('/finance/shopping/ledgers', (ledgerDialog as { id: number }).id, { name })
      await loadLedgers()
      setLedgerDialog(null)
    }
  }
  const removeLedger = async () => {
    if (!currentLedger) return
    if (!(await confirm())) return
    await api.remove('/finance/shopping/ledgers', Number(currentLedger))
    const next = await loadLedgers()
    setCurrentLedger(next.length ? String(next[0].id) : '')
    setPage(1)
    setLedgerDialog(null)
  }

  const addPlatform = async () => {
    const name = newPlatform.trim()
    if (!name) return
    const item = await api.create<Platform>('/finance/shopping/platforms', { name })
    setPlatforms((p) => [...p, item])
    setNewPlatform('')
  }
  const removePlatform = async (id: number) => {
    if (!(await confirm())) return
    await api.remove('/finance/shopping/platforms', id)
    loadPlatforms()
  }

  // 记录操作
  const openCreate = () => {
    setEditing(null)
    setForm({ ...emptyForm, ledger_id: currentLedger || '' })
    setRecordDialog(true)
  }
  const openEdit = (row: Record) => {
    setEditing(row)
    setForm({
      record_date: row.record_date,
      platform_id: row.platform_id ? String(row.platform_id) : '',
      product_name: row.product_name,
      spec: row.spec ?? '',
      total_price: String(row.total_price),
      unit_price: row.unit_price != null ? String(row.unit_price) : '',
      order_no: row.order_no ?? '',
      ledger_id: row.ledger_id ? String(row.ledger_id) : currentLedger || '',
      note: row.note ?? '',
    })
    setRecordDialog(true)
  }
  const submitRecord = async () => {
    const payload = {
      record_date: form.record_date,
      platform_id: form.platform_id ? Number(form.platform_id) : null,
      product_name: form.product_name,
      spec: form.spec || null,
      total_price: Number(form.total_price),
      unit_price: form.unit_price ? Number(form.unit_price) : null,
      order_no: form.order_no || null,
      ledger_id: form.ledger_id ? Number(form.ledger_id) : null,
      note: form.note || null,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/finance/shopping/records', editing.id, payload)
      else await api.create('/finance/shopping/records', payload)
      setRecordDialog(false)
      setPage(1)
    } finally {
      setSaving(false)
    }
  }
  const removeRecord = async (row: Record) => {
    if (!(await confirm())) return
    await api.remove('/finance/shopping/records', row.id)
    if (records.length === 1 && page > 1) setPage(page - 1)
    else {
      setLoading(true)
      const res = await api.list<Record>('/finance/shopping/records', {
        page,
        page_size: PAGE_SIZE,
        extra: { ledger_id: currentLedger ? Number(currentLedger) : undefined },
      })
      setRecords(res.items)
      setTotal(res.total)
      setLoading(false)
      loadStats()
    }
  }

  // xlsx 导入
  const importXlsx = async (file: File) => {
    const fd = new FormData()
    fd.append('file', file)
    try {
      const res = await api.upload<{ imported: number; skipped: number }>('/finance/shopping/import', fd)
      setPage(1)
      setRefresh((v) => v + 1)
      toast.success('导入成功', { description: `共导入 ${res.imported} 条，跳过 ${res.skipped} 条` })
    } catch (e) {
      toast.error('导入失败', { description: (e as Error).message })
    }
  }

  const platformName = (id?: number) => platforms.find((p) => p.id === id)?.name ?? '未分类'

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">购物记录</h1>
          <p className="text-sm text-muted-foreground">管理购物明细、多账本切换与批量导入。</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Select value={currentLedger} onValueChange={(v) => { setCurrentLedger(v); setPage(1) }}>
            <SelectTrigger className="w-40">
              <SelectValue placeholder="选择账本" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">全部账本</SelectItem>
              {ledgers.map((l) => (
                <SelectItem key={l.id} value={String(l.id)}>{l.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button variant="outline" size="icon" title="新建账本" onClick={openCreateLedger}>
            <Plus />
          </Button>
          <Button variant="outline" size="icon" title="账本管理" onClick={() => setLedgerDialog({ mode: 'rename', id: Number(currentLedger), name: ledgers.find((l) => l.id === Number(currentLedger))?.name ?? '' })}>
            <BookOpen />
          </Button>
          <Button variant="outline" size="icon" title="平台管理" onClick={() => setPlatformDialog(true)}>
            <Settings2 />
          </Button>
          <Button variant="outline" onClick={() => fileRef.current?.click()}>
            <Upload /> 导入 xlsx
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept=".xlsx,.xlsm"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) importXlsx(f)
              e.target.value = ''
            }}
          />
          <Button onClick={openCreate}>
            <Plus /> 新增记录
          </Button>
        </div>
      </section>

      {stats && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Wallet} label="消费总额" value={fmt(stats.total)} hint={`${stats.count} 笔记录`} />
            <StatCard icon={Wallet} label="平均单笔" value={stats.count > 0 ? fmt(stats.total / stats.count) : '¥0.00'} hint="总消费 / 笔数" />
            <StatCard icon={Wallet} label="涉及平台" value={`${stats.by_platform.length} 个`} hint={stats.by_platform[0] ? `最多 ${stats.by_platform[0].platform}` : '暂无消费平台'} />
            <StatCard icon={Wallet} label="涉及账本" value={`${stats.by_ledger.length} 个`} hint={stats.by_ledger[0] ? `最多 ${stats.by_ledger[0].ledger}` : '暂无账本'} />
          </section>
          <section className="grid gap-4 lg:grid-cols-2">
            <LineChartCard title="月度消费趋势" data={stats.monthly_trend} xKey="month" series={[{ key: 'amount', name: '消费', color: '#ef4444' }]} />
            <BarChartCard title="按平台消费" data={stats.by_platform} xKey="platform" series={[{ key: 'amount', name: '金额', color: '#4f46e5' }]} />
          </section>
          {stats.by_ledger.length > 0 && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium">按账本消费</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {stats.by_ledger.map((l) => (
                    <Badge key={l.ledger_id} variant="outline">
                      {l.ledger}：{fmt(l.amount)}
                    </Badge>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>平台</TableHead>
                <TableHead>商品名称</TableHead>
                <TableHead>规格</TableHead>
                <TableHead className="text-right">总价</TableHead>
                <TableHead className="text-right">单价</TableHead>
                <TableHead>订单号</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && records.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {records.length === 0 ? (
                loading ? (
                  <TableRow><TableCell colSpan={8} className="h-24 text-center text-muted-foreground"><Loader2 className="mx-auto size-5 animate-spin" /></TableCell></TableRow>
                ) : (
                  <TableRow><TableCell colSpan={8} className="h-24 text-center text-muted-foreground">暂无购物记录，点击"新增记录"或导入 xlsx 添加</TableCell></TableRow>
                )
              ) : (
                records.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.record_date}</TableCell>
                    <TableCell>{platformName(row.platform_id)}</TableCell>
                    <TableCell>{row.product_name}</TableCell>
                    <TableCell>{row.spec ?? '—'}</TableCell>
                    <TableCell className="text-right font-medium">{fmt(row.total_price)}</TableCell>
                    <TableCell className="text-right">{row.unit_price != null ? fmt(row.unit_price) : '—'}</TableCell>
                    <TableCell className="text-muted-foreground">{row.order_no ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(row)}><Pencil /></Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeRecord(row)}><Trash2 /></Button>
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

      {/* 账本管理弹窗 */}
      <Dialog open={ledgerDialog !== null} onOpenChange={(o) => !o && setLedgerDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{ledgerDialog?.mode === 'create' ? '新建账本' : '账本管理'}</DialogTitle>
            <DialogDescription>账本用于分类管理不同的购物记录。</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            {ledgerDialog?.mode === 'rename' && (
              <div className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                <span>当前选择账本：{ledgers.find((l) => l.id === Number(currentLedger))?.name ?? '—'}</span>
                <Button variant="outline" size="sm" onClick={removeLedger}>删除账本</Button>
              </div>
            )}
            <Label>账本名称</Label>
            <Input value={ledgerName} onChange={(e) => setLedgerName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && saveLedger()} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setLedgerDialog(null)}>关闭</Button>
            <Button onClick={saveLedger} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 平台管理弹窗 */}
      <Dialog open={platformDialog} onOpenChange={setPlatformDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>平台管理</DialogTitle>
            <DialogDescription>添加或删除购物平台，如淘宝、京东等。</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="flex gap-2">
              <Input value={newPlatform} onChange={(e) => setNewPlatform(e.target.value)} placeholder="输入平台名称" onKeyDown={(e) => e.key === 'Enter' && addPlatform()} />
              <Button onClick={addPlatform}><Plus /> 添加</Button>
            </div>
            <div className="space-y-1.5">
              {platforms.map((p) => (
                <div key={p.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <span>{p.name}</span>
                  <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removePlatform(p.id)}><Trash2 /></Button>
                </div>
              ))}
              {platforms.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">暂无平台</p>}
            </div>
          </div>
          <DialogFooter>
            <Button onClick={() => setPlatformDialog(false)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 记录新增/编辑弹窗 */}
      <Dialog open={recordDialog} onOpenChange={setRecordDialog}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑购物记录' : '新增购物记录'}</DialogTitle>
            <DialogDescription>{editing ? '修改并保存本条记录。' : '填写购物明细创建一条记录。'}</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>日期 <span className="text-destructive">*</span></Label><DatePicker value={form.record_date} onChange={(v) => setForm({ ...form, record_date: v })} /></div>
            <div className="space-y-2"><Label>平台</Label>
              <Select value={form.platform_id} onValueChange={(v) => setForm({ ...form, platform_id: v })}>
                <SelectTrigger><SelectValue placeholder="选择平台" /></SelectTrigger>
                <SelectContent>
                  {platforms.map((p) => <SelectItem key={p.id} value={String(p.id)}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>商品名称 <span className="text-destructive">*</span></Label><Input value={form.product_name} onChange={(e) => setForm({ ...form, product_name: e.target.value })} /></div>
            <div className="space-y-2"><Label>规格</Label><Input value={form.spec} onChange={(e) => setForm({ ...form, spec: e.target.value })} /></div>
            <div className="space-y-2"><Label>总价 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.total_price} onChange={(e) => setForm({ ...form, total_price: e.target.value })} /></div>
            <div className="space-y-2"><Label>单价</Label><Input type="number" min={0} step="0.01" value={form.unit_price} onChange={(e) => setForm({ ...form, unit_price: e.target.value })} /></div>
            <div className="space-y-2"><Label>订单号</Label><Input value={form.order_no} onChange={(e) => setForm({ ...form, order_no: e.target.value })} /></div>
            <div className="space-y-2"><Label>账本</Label>
              <Select value={form.ledger_id} onValueChange={(v) => setForm({ ...form, ledger_id: v })}>
                <SelectTrigger><SelectValue placeholder="选择账本" /></SelectTrigger>
                <SelectContent>
                  {ledgers.map((l) => <SelectItem key={l.id} value={String(l.id)}>{l.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRecordDialog(false)}>取消</Button>
            <Button onClick={submitRecord} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}