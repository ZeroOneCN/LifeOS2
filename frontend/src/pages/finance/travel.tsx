import { useEffect, useState } from 'react'
import {
  ChevronDown,
  ChevronUp,
  Download,
  History,
  Loader2,
  Pencil,
  Plane,
  Plus,
  Trash2,
  TrendingUp,
  Wallet,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
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
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { api } from '@/lib/api'

const PAGE_SIZE = 10

type Ledger = { id: number; name: string; start_date?: string; end_date?: string; note?: string }
type TravelDetail = {
  id: number
  ledger_id?: number
  detail_date: string
  begin_time?: string
  end_time?: string
  category: string
  item: string
  original_price: number
  discount: number
  actual_price: number
  transport_info?: string
  payment_method?: string
  note?: string
}
type Stats = {
  total_actual: number
  total_original: number
  total_discount: number
  count: number
  by_category: { category: string; amount: number }[]
  monthly_trend: { month: string; amount: number }[]
}

const CATEGORY_OPTIONS = ['交通', '住宿', '餐饮', '门票', '购物', '其他']

type ContentSection = {
  type: 'h2' | 'paragraph' | 'kv' | 'table'
  text?: string
  label?: string
  header?: string[]
  rows?: string[][]
}

type TravelReport = {
  id: number
  title: string
  summary?: string
  period_start?: string
  period_end?: string
  created_at?: string
  content?: ContentSection[]
}

function ReportContent({ content }: { content?: ContentSection[] }) {
  const sections = Array.isArray(content) ? content : []
  return (
    <div className="space-y-3">
      {sections.map((s, i) => {
        if (s.type === 'h2')
          return (
            <h3 key={i} className="border-l-4 border-indigo-500 pl-3 text-sm font-semibold">
              {s.text}
            </h3>
          )
        return (
          <div key={i}>
            {s.label && <div className="mb-1 text-xs font-semibold text-indigo-600">{s.label}</div>}
            <div className="overflow-hidden rounded-lg border">
              <div className="overflow-x-auto">
                <table className="w-full min-w-[280px] text-sm">
                  <tbody>
                    {(s.rows ?? []).map((row, ri) => (
                      <tr key={ri} className="border-t odd:bg-muted/30">
                        {row.map((c, ci) => (
                          <td key={ci} className="px-3 py-1.5">
                            {c}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )
      })}
      {sections.length === 0 && (
        <p className="py-4 text-center text-sm text-muted-foreground">暂无报告内容</p>
      )}
    </div>
  )
}

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`

function duration(begin?: string, end?: string): string {
  if (!begin || !end) return '—'
  const b = begin.split(':').map(Number)
  const e = end.split(':').map(Number)
  const bm = b[0] * 60 + b[1]
  const em = e[0] * 60 + e[1]
  const diff = em >= bm ? em - bm : em + 1440 - bm
  const h = Math.floor(diff / 60)
  const m = diff % 60
  return m === 0 ? `${h} 小时` : `${h} 小时 ${m} 分`
}

type DetailForm = {
  detail_date: string
  begin_time: string
  end_time: string
  category: string
  item: string
  original_price: string
  discount: string
  transport_info: string
  payment_method: string
  note: string
}

const emptyForm: DetailForm = {
  detail_date: new Date().toISOString().slice(0, 10),
  begin_time: '',
  end_time: '',
  category: '交通',
  item: '',
  original_price: '',
  discount: '0',
  transport_info: '',
  payment_method: '',
  note: '',
}

function StatCard({ icon: Icon, label, value }: { icon: typeof Wallet; label: string; value: string }) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className="size-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
      </CardContent>
    </Card>
  )
}

export function TravelPage() {
  const [ledgers, setLedgers] = useState<Ledger[]>([])
  const [currentLedger, setCurrentLedger] = useState<string>('')
  const [items, setItems] = useState<TravelDetail[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [stats, setStats] = useState<Stats | null>(null)

  const [detailDialog, setDetailDialog] = useState(false)
  const [editing, setEditing] = useState<TravelDetail | null>(null)
  const [form, setForm] = useState<DetailForm>(emptyForm)
  const [saving, setSaving] = useState(false)

  const [reportDialog, setReportDialog] = useState(false)
  const [reportDays, setReportDays] = useState('30')
  const [reportLoading, setReportLoading] = useState(false)
  const [report, setReport] = useState<TravelReport | null>(null)
  const [reportCollapsed, setReportCollapsed] = useState(false)
  const [reportHistory, setReportHistory] = useState<TravelReport[]>([])
  const [exportingId, setExportingId] = useState<number | null>(null)

  // 新建行程名称弹窗
  const [ledgerDialog, setLedgerDialog] = useState(false)
  const [ledgerName, setLedgerName] = useState('')
  const [ledgerSaving, setLedgerSaving] = useState(false)
  const [ledgerNote, setLedgerNote] = useState('')

  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const loadLedgers = async () => {
    const res = await api.list<Ledger>('/finance/travel/ledgers', { page_size: 100 })
    setLedgers(res.items)
    return res.items
  }

  useEffect(() => {
    loadLedgers().then((items) => {
      if (items.length > 0 && !currentLedger) setCurrentLedger(String(items[0].id))
    })
  }, [])

  useEffect(() => {
    const ledgerParam = currentLedger ? Number(currentLedger) : undefined
    setLoading(true)
    api
      .list<TravelDetail>('/finance/travel/details', {
        page,
        page_size: PAGE_SIZE,
        extra: { ledger_id: ledgerParam },
      })
      .then((res) => {
        setItems(res.items)
        setTotal(res.total)
      })
      .finally(() => setLoading(false))
    api
      .query<Stats>(`/finance/travel/details/stats?days=3650${currentLedger ? `&ledger_id=${ledgerParam}` : ''}`)
      .then(setStats)
      .catch(() => setStats(null))
  }, [currentLedger, page])

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const openCreateLedger = () => {
    setLedgerName('')
    setLedgerNote('')
    setLedgerDialog(true)
  }
  const saveLedger = async () => {
    const name = ledgerName.trim()
    if (!name || ledgerSaving) return
    setLedgerSaving(true)
    try {
      const item = await api.create<Ledger>('/finance/travel/ledgers', {
        name,
        note: ledgerNote.trim() || null,
        start_date: new Date().toISOString().slice(0, 10),
      })
      const next = await loadLedgers()
      setCurrentLedger(String(item.id))
      setPage(1)
      setLedgers(next)
      setLedgerDialog(false)
    } finally {
      setLedgerSaving(false)
    }
  }
  const removeLedger = async () => {
    if (!currentLedger) return
    if (!(await confirm())) return
    await api.remove('/finance/travel/ledgers', Number(currentLedger))
    const next = await loadLedgers()
    setCurrentLedger(next.length ? String(next[0].id) : '')
    setPage(1)
  }

  const openCreate = () => {
    setEditing(null)
    setForm(emptyForm)
    setDetailDialog(true)
  }
  const openEdit = (row: TravelDetail) => {
    setEditing(row)
    setForm({
      detail_date: row.detail_date,
      begin_time: row.begin_time?.slice(0, 5) ?? '',
      end_time: row.end_time?.slice(0, 5) ?? '',
      category: row.category,
      item: row.item,
      original_price: String(row.original_price),
      discount: String(row.discount),
      transport_info: row.transport_info ?? '',
      payment_method: row.payment_method ?? '',
      note: row.note ?? '',
    })
    setDetailDialog(true)
  }

  const autoActual = () => {
    const o = Number(form.original_price) || 0
    const d = Number(form.discount) || 0
    return Math.max(0, o - d)
  }

  const submit = async () => {
    const payload = {
      ledger_id: currentLedger ? Number(currentLedger) : null,
      detail_date: form.detail_date,
      begin_time: form.begin_time || null,
      end_time: form.end_time || null,
      category: form.category,
      item: form.item,
      original_price: Number(form.original_price),
      discount: Number(form.discount) || 0,
      transport_info: form.transport_info || null,
      payment_method: form.payment_method || null,
      note: form.note || null,
    }
    setSaving(true)
    try {
      if (editing) await api.update('/finance/travel/details', editing.id, payload)
      else await api.create('/finance/travel/details', payload)
      setDetailDialog(false)
      setPage(1)
    } finally {
      setSaving(false)
    }
  }

  const removeItem = async (row: TravelDetail) => {
    if (!(await confirm())) return
    await api.remove('/finance/travel/details', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else {
      setLoading(true)
      const res = await api.list<TravelDetail>('/finance/travel/details', {
        page,
        page_size: PAGE_SIZE,
        extra: { ledger_id: currentLedger ? Number(currentLedger) : undefined },
      })
      setItems(res.items)
      setTotal(res.total)
      setLoading(false)
    }
  }

  const generateReport = async () => {
    setReportLoading(true)
    try {
      const res = await api.create<TravelReport>('/finance/travel/report/generate', {
        ledger_id: currentLedger ? Number(currentLedger) : null,
        days: Number(reportDays),
      })
      setReport(res)
      setReportCollapsed(false)
      await loadReportHistory()
    } catch (e) {
      toast.error('生成失败', { description: (e as Error).message })
    } finally {
      setReportLoading(false)
    }
  }
  const loadReportHistory = async () => {
    api
      .query<TravelReport[]>('/finance/travel/report')
      .then(setReportHistory)
      .catch(() => setReportHistory([]))
  }
  const exportReport = (id: number) => {
    setExportingId(id)
    api
      .download(`/finance/travel/report/${id}/export`, '旅行开支报告.pdf')
      .catch((e) => toast.error('导出失败', { description: (e as Error).message }))
      .finally(() => setExportingId(null))
  }
  const deleteReport = async (id: number) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/travel/report', id)
      if (report?.id === id) setReport(null)
      await loadReportHistory()
    } catch (e) {
      toast.error('删除失败', { description: (e as Error).message })
    }
  }
  const viewReport = (r: TravelReport) => {
    setReport(r)
    setReportCollapsed(false)
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">旅行开支</h1>
          <p className="text-sm text-muted-foreground">多行程账本管理、费用明细与旅行报告。</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Select value={currentLedger} onValueChange={(v) => { setCurrentLedger(v); setPage(1) }}>
            <SelectTrigger className="w-44"><SelectValue placeholder="选择行程" /></SelectTrigger>
            <SelectContent>
              {ledgers.map((l) => <SelectItem key={l.id} value={String(l.id)}>{l.name}</SelectItem>)}
            </SelectContent>
          </Select>
          <Button variant="outline" size="icon" title="新建行程" onClick={openCreateLedger}><Plus /></Button>
          <Button variant="outline" size="icon" title="删除当前行程" className="text-destructive" onClick={removeLedger}><Trash2 /></Button>
          <Button variant="outline" onClick={() => { setReportDialog(true); setReport(null); loadReportHistory() }}><TrendingUp /> 旅行报告</Button>
          <Button onClick={openCreate}><Plus /> 新增明细</Button>
        </div>
      </section>

      {stats && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Wallet} label="实付合计" value={fmt(stats.total_actual)} />
            <StatCard icon={Wallet} label="原价合计" value={fmt(stats.total_original)} />
            <StatCard icon={Wallet} label="优惠金额" value={fmt(stats.total_discount)} />
            <StatCard icon={Plane} label="明细笔数" value={`${stats.count} 笔`} />
          </section>
          <section className="grid gap-4 lg:grid-cols-2">
            <BarChartCard title="按分类支出" data={stats.by_category} xKey="category" series={[{ key: 'amount', name: '实付', color: '#4f46e5' }]} />
            <LineChartCard title="月度开支趋势" data={stats.monthly_trend} xKey="month" series={[{ key: 'amount', name: '实付', color: '#ef4444' }]} />
          </section>
        </>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>时间段</TableHead>
                <TableHead>时长</TableHead>
                <TableHead>分类</TableHead>
                <TableHead>项目</TableHead>
                <TableHead className="text-right">原价</TableHead>
                <TableHead className="text-right">优惠</TableHead>
                <TableHead className="text-right">实付</TableHead>
                <TableHead>交通</TableHead>
                <TableHead>支付方式</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow><TableCell colSpan={11} className="h-24 text-center text-muted-foreground"><Loader2 className="mx-auto size-5 animate-spin" /></TableCell></TableRow>
                ) : (
                  <TableRow><TableCell colSpan={11} className="h-24 text-center text-muted-foreground">暂无行程明细，点击"新增明细"添加</TableCell></TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.detail_date}</TableCell>
                    <TableCell>{row.begin_time ? `${row.begin_time.slice(0, 5)}-${row.end_time?.slice(0, 5)}` : '—'}</TableCell>
                    <TableCell className="text-muted-foreground">{duration(row.begin_time, row.end_time)}</TableCell>
                    <TableCell><Badge variant="secondary">{row.category}</Badge></TableCell>
                    <TableCell>{row.item}</TableCell>
                    <TableCell className="text-right text-muted-foreground">{fmt(row.original_price)}</TableCell>
                    <TableCell className="text-right text-green-600">{row.discount > 0 ? `-${fmt(row.discount)}` : '—'}</TableCell>
                    <TableCell className="text-right font-medium">{fmt(row.actual_price)}</TableCell>
                    <TableCell className="text-muted-foreground">{row.transport_info ?? '—'}</TableCell>
                    <TableCell className="text-muted-foreground">{row.payment_method ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(row)}><Pencil /></Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeItem(row)}><Trash2 /></Button>
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
          <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>上一页</Button>
          <span>{page} / {totalPages}</span>
          <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage(page + 1)}>下一页</Button>
        </div>
      </div>

      {/* 明细新增/编辑弹窗 */}
      <Dialog open={detailDialog} onOpenChange={setDetailDialog}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑行程明细' : '新增行程明细'}</DialogTitle>
            <DialogDescription>{editing ? '修改并保存本条明细。' : '填写费用与日程信息创建明细。'}</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>日期 <span className="text-destructive">*</span></Label><Input type="date" value={form.detail_date} onChange={(e) => setForm({ ...form, detail_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>分类 <span className="text-destructive">*</span></Label>
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CATEGORY_OPTIONS.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>开始时间</Label><Input type="time" value={form.begin_time} onChange={(e) => setForm({ ...form, begin_time: e.target.value })} /></div>
            <div className="space-y-2"><Label>结束时间</Label><Input type="time" value={form.end_time} onChange={(e) => setForm({ ...form, end_time: e.target.value })} /></div>
            <div className="space-y-2"><Label>项目 <span className="text-destructive">*</span></Label><Input value={form.item} onChange={(e) => setForm({ ...form, item: e.target.value })} /></div>
            <div className="space-y-2"><Label>支付方式</Label><Input value={form.payment_method} onChange={(e) => setForm({ ...form, payment_method: e.target.value })} /></div>
            <div className="space-y-2"><Label>原价 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.original_price} onChange={(e) => setForm({ ...form, original_price: e.target.value })} /></div>
            <div className="space-y-2"><Label>优惠</Label><Input type="number" min={0} step="0.01" value={form.discount} onChange={(e) => setForm({ ...form, discount: e.target.value })} /></div>
            <div className="col-span-2 space-y-1">
              <Label>实付（自动 = 原价 - 优惠）</Label>
              <div className="rounded-lg border px-3 py-2 text-sm font-medium">{fmt(autoActual())}</div>
            </div>
            <div className="col-span-2 space-y-2"><Label>交通信息</Label><Input value={form.transport_info} onChange={(e) => setForm({ ...form, transport_info: e.target.value })} placeholder="航班/车次等" /></div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDetailDialog(false)}>取消</Button>
            <Button onClick={submit} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 新建行程名称弹窗 */}
      <Dialog open={ledgerDialog} onOpenChange={setLedgerDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>新建行程</DialogTitle>
            <DialogDescription>为本次旅行创建一个账本，便于分类记录明细。</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1">
              <Label>行程名称 <span className="text-destructive">*</span></Label>
              <Input value={ledgerName} onChange={(e) => setLedgerName(e.target.value)} placeholder="如 2026 国庆之旅" onKeyDown={(e) => e.key === 'Enter' && saveLedger()} />
            </div>
            <div className="space-y-1">
              <Label>备注（可选）</Label>
              <Textarea value={ledgerNote} onChange={(e) => setLedgerNote(e.target.value)} placeholder="目的地 / 同行人 等" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setLedgerDialog(false)}>取消</Button>
            <Button onClick={saveLedger} disabled={ledgerSaving}>{ledgerSaving && <Loader2 className="animate-spin" />}创建</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 旅行报告弹窗 */}
      <Dialog open={reportDialog} onOpenChange={(o) => { setReportDialog(o); if (!o) setReport(null) }}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>旅行报告</DialogTitle>
            <DialogDescription>生成并保存报告，可预览内容、导出 PDF，历史报告自动留存。</DialogDescription>
          </DialogHeader>
          <div className="flex flex-wrap items-center gap-3">
            <div className="space-y-1">
              <Label>统计天数</Label>
              <Input className="w-24" type="number" min={1} value={reportDays} onChange={(e) => setReportDays(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>行程</Label>
              <Select value={currentLedger} onValueChange={setCurrentLedger}>
                <SelectTrigger className="w-44"><SelectValue placeholder="全部行程" /></SelectTrigger>
                <SelectContent>
                  {ledgers.map((l) => <SelectItem key={l.id} value={String(l.id)}>{l.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>&nbsp;</Label>
              <Button onClick={generateReport} disabled={reportLoading}>{reportLoading ? <Loader2 className="animate-spin" /> : <Plus />}生成并保存</Button>
            </div>
          </div>

          {report && (
            <div className="space-y-2 rounded-lg border p-3">
              <div className="flex items-start justify-between gap-2">
                <button type="button" className="min-w-0 flex-1 text-left" onClick={() => setReportCollapsed((v) => !v)}>
                  <div className="flex items-center gap-1">
                    <ChevronDown className={`size-4 text-indigo-600 transition-transform ${reportCollapsed ? '-rotate-90' : ''}`} />
                    <span className="font-medium">{report.title}</span>
                  </div>
                  {report.summary && <p className="mt-1 text-sm text-muted-foreground">{report.summary}</p>}
                </button>
                <div className="flex shrink-0 items-center gap-1">
                  <Button size="sm" variant="ghost" onClick={() => setReportCollapsed((v) => !v)} title={reportCollapsed ? '展开' : '收起'}>
                    {reportCollapsed ? <ChevronDown className="size-4" /> : <ChevronUp className="size-4" />}
                  </Button>
                  <Button size="sm" variant="outline" onClick={() => exportReport(report.id)} disabled={exportingId === report.id}>
                    {exportingId === report.id ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
                    导出 PDF
                  </Button>
                </div>
              </div>
              {!reportCollapsed && <ReportContent content={report.content} />}
            </div>
          )}

          <div>
            <div className="mb-1 flex items-center gap-1.5 text-sm font-medium">
              <History className="size-4" /> 历史报告（{reportHistory.length}）
            </div>
            {reportHistory.length === 0 ? (
              <p className="py-4 text-center text-sm text-muted-foreground">暂无历史报告，先生成一份吧。</p>
            ) : (
              <div className="space-y-1.5">
                {reportHistory.map((r) => (
                  <div key={r.id} className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm">
                    <button type="button" className="min-w-0 flex-1 text-left" onClick={() => viewReport(r)}>
                      <div className="truncate font-medium">{r.title}</div>
                      <div className="text-xs text-muted-foreground">
                        {r.period_start && r.period_end ? `${r.period_start} ~ ${r.period_end}` : ''}
                        {r.created_at ? ` · ${r.created_at}` : ''}
                      </div>
                    </button>
                    <Button size="sm" variant="ghost" onClick={() => exportReport(r.id)} disabled={exportingId === r.id}>
                      {exportingId === r.id ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
                    </Button>
                    <Button size="sm" variant="ghost" className="text-destructive" onClick={() => deleteReport(r.id)}>
                      <Trash2 className="size-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <DialogFooter>
            <Button onClick={() => { setReportDialog(false); setReport(null) }}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}