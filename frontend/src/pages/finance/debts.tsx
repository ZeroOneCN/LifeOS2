import { useEffect, useState } from 'react'
import {
  AlertTriangle,
  ArrowDownCircle,
  ArrowUpCircle,
  Banknote,
  Bookmark,
  HandCoins,
  Landmark,
  Loader2,
  Pencil,
  Plus,
  Receipt,
  Trash2,
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

type Currency = { id: number; currency: string; name?: string; rate_to_cny: number; symbol?: string }
type Fmt = (cny: number) => string

const directionMeta: Record<string, { label: string; className: string }> = {
  lend: { label: '借出', className: 'bg-blue-100 text-blue-700' },
  borrow: { label: '借入', className: 'bg-amber-100 text-amber-700' },
}
const statusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '进行中', className: 'bg-blue-100 text-blue-700' },
  settled: { label: '已结清', className: 'bg-green-100 text-green-700' },
}

const investCategories = ['美股', '港股', '外汇', '加密货币-合约', '加密货币-现货', '加密货币-钱包(Alpha)']

type DebtRecord = {
  id: number
  debt_date: string
  name: string
  direction: 'lend' | 'borrow'
  counterparty?: string
  amount: number
  remaining?: number
  interest_rate?: number
  due_date?: string
  status: 'active' | 'settled'
  note?: string
}
type DebtStats = {
  total: number; active: number; settled: number
  borrow_total: number; lend_total: number; outstanding: number; overdue: number
  by_direction: { direction: string; label: string; amount: number }[]
  by_status: { status: string; label: string; count: number }[]
  overdue_list: { name: string; counterparty?: string; direction: string; remaining: number; due_date?: string }[]
}
type LoanSync = { total_remaining: number; platform_count: number; platforms: { platform_id: number; name: string; remaining: number; bill_count: number }[] }

/* ---------------- 民间借贷 ---------------- */

function DebtTab({ fmtMoney }: { fmtMoney: Fmt }) {
  const stats = useStats<DebtStats>('/finance/debts')
  const [items, setItems] = useState<DebtRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [loanSync, setLoanSync] = useState<LoanSync | null>(null)
  const [dialog, setDialog] = useState<null | { editing?: DebtRecord }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [repayTarget, setRepayTarget] = useState<DebtRecord | null>(null)
  const [repayForm, setRepayForm] = useState({ repay_date: '', amount: '' })
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const totalPages = Math.max(1, Math.ceil(total / 10))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<DebtRecord>('/finance/debts', { page, page_size: 10 })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    load()
    api.query<LoanSync>('/finance/debts/loan-sync').then(setLoanSync).catch(() => setLoanSync(null))
  }, [page])

  const remaining = (d: DebtRecord) => (d.remaining != null ? d.remaining : d.amount)

  const openCreate = () => {
    setForm({ debt_date: new Date().toISOString().slice(0, 10), name: '', direction: 'borrow', counterparty: '', amount: '', remaining: '', interest_rate: '', due_date: '', status: 'active', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      debt_date: form.debt_date, name: form.name, direction: form.direction,
      counterparty: form.counterparty || null, amount: Number(form.amount),
      remaining: form.remaining ? Number(form.remaining) : null,
      interest_rate: form.interest_rate ? Number(form.interest_rate) : null,
      due_date: form.due_date || null, status: form.status, note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/debts', dialog.editing.id, payload)
      else await api.create('/finance/debts', payload)
      setDialog(null)
      await load()
    } finally {
      setSaving(false)
    }
  }
  const remove = async (d: DebtRecord) => {
    if (!(await confirm())) return
    await api.remove('/finance/debts', d.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const openRepay = (d: DebtRecord) => {
    setRepayForm({ repay_date: new Date().toISOString().slice(0, 10), amount: String(remaining(d)) })
    setRepayTarget(d)
  }
  const submitRepay = async () => {
    if (!repayTarget) return
    setSaving(true)
    try {
      await api.post(`/finance/debts/${repayTarget.id}/repay`, {
        repay_date: repayForm.repay_date, amount: Number(repayForm.amount),
      })
      setRepayTarget(null)
      await load()
    } catch (e) {
      window.alert((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {stats && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Wallet} label="民间债务总数" value={String(stats.total)} />
            <StatCard icon={ArrowDownCircle} label="借出应收" value={fmtMoney(stats.lend_total)} className="text-blue-500" />
            <StatCard icon={ArrowUpCircle} label="借入应付" value={fmtMoney(stats.borrow_total)} className="text-amber-500" />
            <StatCard icon={HandCoins} label="未结清余额" value={fmtMoney(stats.outstanding)} className="text-indigo-500" />
          </section>

          {stats.overdue > 0 && (
            <Card className="border-red-200 bg-red-50">
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium text-red-700">
                  <AlertTriangle className="size-4" /> 已逾期 {stats.overdue} 笔待处理
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1.5 text-sm">
                {stats.overdue_list.map((o, i) => (
                  <div key={i} className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-white/70 px-3 py-1.5">
                    <span>{o.name}{o.counterparty ? `（${o.counterparty}）` : ''}<Badge className={`ml-2 ${directionMeta[o.direction]?.className}`}>{directionMeta[o.direction]?.label}</Badge></span>
                    <span className="text-muted-foreground">到期 {o.due_date ?? '—'} · 剩余 <span className="font-medium text-red-700">{fmtMoney(o.remaining)}</span></span>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
        </>
      )}

      {/* 网贷只读同步 */}
      {loanSync && loanSync.platform_count > 0 && (
        <Card className="border-indigo-200 bg-indigo-50/60">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium text-indigo-700">
              <Receipt className="size-4" /> 网贷欠款同步（来源：账单管理 · 网贷借还）
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            <div className="flex flex-wrap gap-2 pb-1">
              {loanSync.platforms.map((p) => (
                <Badge key={p.platform_id} variant="outline" className="bg-white/80">
                  {p.name}：<span className="font-medium text-red-700">{fmtMoney(p.remaining)}</span>（{p.bill_count} 笔待还）
                </Badge>
              ))}
              <Badge className="bg-indigo-100 text-indigo-700">合计待还 {fmtMoney(loanSync.total_remaining)}</Badge>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="p-0">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-lg font-medium">民间借贷明细</CardTitle>
            <Button onClick={openCreate}><Plus /> 新增借款</Button>
          </CardHeader>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead><TableHead>名称</TableHead><TableHead>方向</TableHead><TableHead>对方</TableHead>
                <TableHead className="text-right">额度</TableHead><TableHead className="text-right">剩余</TableHead><TableHead>利率</TableHead><TableHead>还款日</TableHead><TableHead>状态</TableHead><TableHead className="w-28 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow><TableCell colSpan={10} className="h-24 text-center text-muted-foreground"><Loader2 className="mx-auto size-5 animate-spin" /></TableCell></TableRow>
                ) : (
                  <TableRow><TableCell colSpan={10} className="h-24 text-center text-muted-foreground">暂无民间借款记录</TableCell></TableRow>
                )
              ) : items.map((d) => (
                <TableRow key={d.id}>
                  <TableCell>{d.debt_date}</TableCell>
                  <TableCell className="font-medium">{d.name}</TableCell>
                  <TableCell><Badge className={directionMeta[d.direction]?.className}>{directionMeta[d.direction]?.label}</Badge></TableCell>
                  <TableCell>{d.counterparty ?? '—'}</TableCell>
                  <TableCell className="text-right">{fmtMoney(d.amount)}</TableCell>
                  <TableCell className={`text-right font-medium ${remaining(d) > 0 ? 'text-red-600' : ''}`}>{fmtMoney(remaining(d))}</TableCell>
                  <TableCell>{d.interest_rate != null ? `${d.interest_rate}%` : '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{d.due_date ?? '—'}</TableCell>
                  <TableCell><Badge className={statusMeta[d.status]?.className}>{statusMeta[d.status]?.label}</Badge></TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      {d.status === 'active' && remaining(d) > 0 && (
                        <Button variant="ghost" size="sm" onClick={() => openRepay(d)} title="还款/收款"><Banknote /></Button>
                      )}
                      <Button variant="ghost" size="icon" onClick={() => { setForm({ debt_date: d.debt_date, name: d.name, direction: d.direction, counterparty: d.counterparty ?? '', amount: String(d.amount), remaining: d.remaining != null ? String(d.remaining) : '', interest_rate: d.interest_rate != null ? String(d.interest_rate) : '', due_date: d.due_date ?? '', status: d.status, note: d.note ?? '' }); setDialog({ editing: d }) }}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(d)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />

      {/* 新增/编辑弹窗 */}
      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑借款' : '新增借款'}</DialogTitle>
            <DialogDescription>记参与民间借款，支持灵活还款。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>日期 *</Label><Input type="date" value={form.debt_date} onChange={(e) => setForm({ ...form, debt_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>债务名称 *</Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="如 朋友借款 / 房贷" /></div>
            <div className="space-y-2"><Label>方向 *</Label>
              <Select value={form.direction} onValueChange={(v) => setForm({ ...form, direction: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="borrow">借入（应付）</SelectItem><SelectItem value="lend">借出（应收）</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>对方</Label><Input value={form.counterparty} onChange={(e) => setForm({ ...form, counterparty: e.target.value })} placeholder="债权人 / 借款人" /></div>
            <div className="space-y-2"><Label>额度使用(总额) *</Label><Input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>剩余债务</Label><Input type="number" min={0} step="0.01" value={form.remaining} onChange={(e) => setForm({ ...form, remaining: e.target.value })} /></div>
            <div className="space-y-2"><Label>年利率(%)</Label><Input type="number" step="0.01" min={0} value={form.interest_rate} onChange={(e) => setForm({ ...form, interest_rate: e.target.value })} /></div>
            <div className="space-y-2"><Label>还款日</Label><Input type="date" value={form.due_date} onChange={(e) => setForm({ ...form, due_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>状态</Label>
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="active">进行中</SelectItem><SelectItem value="settled">已结清</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>取消</Button>
            <Button onClick={save} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 还款弹窗 */}
      <Dialog open={repayTarget !== null} onOpenChange={(o) => !o && setRepayTarget(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{repayTarget ? `${repayTarget.direction === 'borrow' ? '还款' : '收款'}` : ''}</DialogTitle>
            <DialogDescription>
              {repayTarget ? `${repayTarget.name}（${directionMeta[repayTarget.direction]?.label}）· 剩余 ${fmtMoney(remaining(repayTarget))}` : ''}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>日期 *</Label><Input type="date" value={repayForm.repay_date} onChange={(e) => setRepayForm({ ...repayForm, repay_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>金额 *</Label><Input type="number" min={0.01} step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRepayTarget(null)}>取消</Button>
            <Button onClick={submitRepay} disabled={saving}><Banknote className="size-4" /> 确认{repayTarget?.direction === 'borrow' ? '还款' : '收款'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 投资记账 ---------------- */

type Investment = { id: number; platform: string; account?: string; category: string; pnl: number; note?: string }
type InvStats = { count: number; total_pnl: number; profit: number; loss: number; by_category: { category: string; amount: number }[]; by_platform: { platform: string; amount: number }[] }

function InvestTab({ fmtMoney }: { fmtMoney: Fmt }) {
  const [items, setItems] = useState<Investment[]>([])
  const [stats, setStats] = useState<InvStats | null>(null)
  const [dialog, setDialog] = useState<null | { editing?: Investment }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Investment>('/finance/investments', { page_size: 100 })
    setItems(res.items)
    api.stats<InvStats>('/finance/investments').then(setStats).catch(() => setStats(null))
  }
  useEffect(() => { load() }, [])

  const openCreate = () => {
    setForm({ platform: '', account: '', category: '美股', pnl: '', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      platform: form.platform, account: form.account || null, category: form.category,
      pnl: Number(form.pnl), note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/investments', dialog.editing.id, payload)
      else await api.create('/finance/investments', payload)
      setDialog(null)
      await load()
    } finally {
      setSaving(false)
    }
  }
  const remove = async (iv: Investment) => {
    if (!(await confirm())) return
    await api.remove('/finance/investments', iv.id)
    await load()
  }

  return (
    <div className="flex flex-col gap-4">
      {stats && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Wallet} label="投资平台数" value={`${stats.count} 个`} />
            <StatCard icon={ArrowUpCircle} label="整体盈亏" value={fmtMoney(stats.total_pnl)} className={stats.total_pnl >= 0 ? 'text-green-600' : 'text-red-600'} />
            <StatCard icon={ArrowUpCircle} label="盈利合计" value={fmtMoney(stats.profit)} className="text-green-600" />
            <StatCard icon={ArrowDownCircle} label="亏损合计" value={fmtMoney(stats.loss)} className="text-red-600" />
          </section>
          {stats.by_category.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium">按投资类别盈亏</CardTitle></CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {stats.by_category.map((c) => (
                    <Badge key={c.category} variant="outline">
                      {c.category}：<span className={c.amount >= 0 ? 'text-green-600' : 'text-red-600'}>{fmtMoney(c.amount)}</span>
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
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-lg font-medium">投资平台记账</CardTitle>
            <Button onClick={openCreate}><Plus /> 新增投资</Button>
          </CardHeader>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>平台</TableHead><TableHead>账号</TableHead><TableHead>类别</TableHead><TableHead className="text-right">盈亏总额</TableHead><TableHead>备注</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="h-16 text-center text-muted-foreground">暂无投资记账</TableCell></TableRow>
              ) : items.map((iv) => (
                <TableRow key={iv.id}>
                  <TableCell className="font-medium">{iv.platform}</TableCell>
                  <TableCell>{iv.account ?? '—'}</TableCell>
                  <TableCell><Badge variant="outline">{iv.category}</Badge></TableCell>
                  <TableCell className={`text-right font-medium ${iv.pnl >= 0 ? 'text-green-600' : 'text-red-600'}`}>{fmtMoney(iv.pnl)}</TableCell>
                  <TableCell className="text-muted-foreground">{iv.note ?? '—'}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => { setForm({ platform: iv.platform, account: iv.account ?? '', category: iv.category, pnl: String(iv.pnl), note: iv.note ?? '' }); setDialog({ editing: iv }) }}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(iv)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑投资' : '新增投资'}</DialogTitle>
            <DialogDescription>记录各投资平台的盈亏总额，简明即可。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>平台 *</Label><Input value={form.platform} onChange={(e) => setForm({ ...form, platform: e.target.value })} placeholder="如 富途 / 币安" /></div>
            <div className="space-y-2"><Label>平台账号</Label><Input value={form.account} onChange={(e) => setForm({ ...form, account: e.target.value })} /></div>
            <div className="space-y-2"><Label>类别 *</Label>
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{investCategories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>盈亏总额 *</Label><Input type="number" step="0.01" value={form.pnl} onChange={(e) => setForm({ ...form, pnl: e.target.value })} placeholder="正为盈利，负为亏损" /></div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>取消</Button>
            <Button onClick={save} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 备忘录 ---------------- */

type Memo = { id: number; title: string; content?: string; memo_date?: string }

function MemoTab() {
  const [items, setItems] = useState<Memo[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Memo }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Memo>('/finance/memos', { page_size: 100 })
    setItems(res.items)
  }
  useEffect(() => { load() }, [])

  const openCreate = () => { setForm({ title: '', content: '', memo_date: new Date().toISOString().slice(0, 10) }); setDialog({}) }
  const save = async () => {
    const payload = { title: form.title, content: form.content || null, memo_date: form.memo_date || null }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/memos', dialog.editing.id, payload)
      else await api.create('/finance/memos', payload)
      setDialog(null)
      await load()
    } finally {
      setSaving(false)
    }
  }
  const remove = async (m: Memo) => {
    if (!(await confirm())) return
    await api.remove('/finance/memos', m.id)
    await load()
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardContent className="p-0">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
            <CardTitle className="text-lg font-medium">备忘录（模糊记忆）</CardTitle>
            <Button onClick={openCreate}><Plus /> 新增备忘</Button>
          </CardHeader>
          <div className="grid gap-2 p-4 sm:grid-cols-2 lg:grid-cols-3">
            {items.length === 0 ? (
              <p className="col-span-full py-6 text-center text-sm text-muted-foreground">暂无备忘，记录那些有点印象却容易忘的事</p>
            ) : items.map((m) => (
              <div key={m.id} className="rounded-lg border p-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{m.title}</div>
                    {m.memo_date && <div className="mt-0.5 text-xs text-muted-foreground">{m.memo_date}</div>}
                  </div>
                  <div className="flex shrink-0 gap-0.5">
                    <Button variant="ghost" size="icon" onClick={() => { setForm({ title: m.title, content: m.content ?? '', memo_date: m.memo_date ?? '' }); setDialog({ editing: m }) }}><Pencil /></Button>
                    <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(m)}><Trash2 /></Button>
                  </div>
                </div>
                {m.content && <p className="mt-2 whitespace-pre-wrap text-sm text-muted-foreground">{m.content}</p>}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑备忘' : '新增备忘'}</DialogTitle>
            <DialogDescription>记录那些暂时想不起来但有模糊印象的事项。</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2"><Label>标题 *</Label><Input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></div>
            <div className="space-y-2"><Label>内容</Label><Textarea className="min-h-[120px]" value={form.content} onChange={(e) => setForm({ ...form, content: e.target.value })} placeholder="写下你的模糊记忆…" /></div>
            <div className="space-y-2"><Label>日期</Label><Input type="date" value={form.memo_date} onChange={(e) => setForm({ ...form, memo_date: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>取消</Button>
            <Button onClick={save} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 汇率设置 ---------------- */

function RateTab({ currencies, setCurrencies, currency, setCurrency }: {
  currencies: Currency[]
  setCurrencies: (c: Currency[]) => void
  currency: Currency | null
  setCurrency: (c: Currency) => void
}) {
  const { dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这个币种吗？' })
  const [editing, setEditing] = useState<Currency | null>(null)
  const [rateValue, setRateValue] = useState('')

  const saveRate = async () => {
    if (!editing) return
    const v = Number(rateValue)
    if (!v || v <= 0) return
    const updated = await api.update<Currency>('/finance/currencies', editing.id, {
      currency: editing.currency, name: editing.name, symbol: editing.symbol, rate_to_cny: v,
    })
    setCurrencies(currencies.map((c) => (c.id === updated.id ? updated : c)))
    setEditing(null)
  }
  const resetToCny = () => {
    const c = currencies.find((x) => x.currency === 'CNY')
    if (c) setCurrency(c)
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">币种与汇率（相对人民币）</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {currencies.map((c) => (
            <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm">
              <span className="flex items-center gap-2">
                <b>{c.name ?? c.currency}</b>
                <Badge variant="outline">{c.symbol ?? ''}{c.currency}</Badge>
              </span>
              <span className="flex items-center gap-2">
                {editing?.id === c.id ? (
                  <>
                    <Input className="w-28" type="number" step="0.0001" value={rateValue} onChange={(e) => setRateValue(e.target.value)} />
                    <Button size="sm" onClick={saveRate}>保存</Button>
                    <Button size="sm" variant="outline" onClick={() => setEditing(null)}>取消</Button>
                  </>
                ) : (
                  <>
                    <span className="text-muted-foreground">1 {c.currency} ≈ {c.rate_to_cny} 人民币</span>
                    <Button size="sm" variant="outline" onClick={() => { setEditing(c); setRateValue(String(c.rate_to_cny)) }}>编辑</Button>
                  </>
                )}
                {c.currency === 'CNY' && (
                  <Button size="sm" variant="ghost" onClick={resetToCny}>当前显示：人民币</Button>
                )}
                {c.currency !== 'CNY' && (
                  <Button size="sm" variant="ghost" onClick={() => setCurrency(c)} className={currency?.currency === c.currency ? 'text-indigo-600' : ''}>
                    {currency?.currency === c.currency ? '当前显示' : '设为显示'}
                  </Button>
                )}
              </span>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">{currency ? `${currency.name ?? currency.currency}（${currency.symbol ?? ''}）显示` : '显示币种'}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-1.5 text-sm">
          <p className="text-muted-foreground">
            当前以 <b>{currency?.name ?? '人民币'}</b> 显示页面金额。所有金额以人民币存储，切换币种仅改变显示换算。
          </p>
          <div className="flex flex-wrap items-center gap-2">
            {currencies.map((c) => (
              <Button key={c.id} size="sm" variant={currency?.currency === c.currency ? 'default' : 'outline'} onClick={() => setCurrency(c)}>
                {c.name ?? c.currency}
              </Button>
            ))}
          </div>
        </CardContent>
      </Card>
      {confirmDialog}
    </div>
  )
}

/* ---------------- 页面 ---------------- */

function StatCard({ icon: Icon, label, value, className }: { icon: typeof Wallet; label: string; value: string; className?: string }) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
      </CardHeader>
      <CardContent><div className="text-2xl font-semibold">{value}</div></CardContent>
    </Card>
  )
}

type TabKey = 'debt' | 'invest' | 'memo' | 'rate'

export function DebtsPage() {
  const [tab, setTab] = useState<TabKey>('debt')
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [currency, setCurrency] = useState<Currency | null>(null)

  useEffect(() => {
    api.query<Currency[]>('/finance/currencies').then((list) => {
      setCurrencies(list)
      const cny = list.find((c) => c.currency === 'CNY')
      setCurrency(cny ?? list[0] ?? null)
    }).catch(() => {})
  }, [])

  const fmtMoney: Fmt = (cny: number) => {
    const r = currency
    if (!r || !r.rate_to_cny) return `¥${cny.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
    const v = cny / r.rate_to_cny
    const s = r.symbol ?? ''
    const sign = v < 0 ? '-' : ''
    return `${sign}${s}${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
  }

  const tabs: { key: TabKey; label: string; icon: typeof Wallet }[] = [
    { key: 'debt', label: '民间借贷', icon: HandCoins },
    { key: 'invest', label: '投资记账', icon: Landmark },
    { key: 'memo', label: '备忘录', icon: Bookmark },
    { key: 'rate', label: '汇率设置', icon: Wallet },
  ]

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">债务管理</h1>
          <p className="text-sm text-muted-foreground">
            管理民间借贷与网贷同步，并维护投资记账与汇率换算。
          </p>
        </div>
        {currency && <Badge variant="outline" className="text-base">显示：{currency.name ?? currency.currency} {currency.symbol ?? ''}</Badge>}
      </section>

      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {tabs.map((t) => (
          <Button key={t.key} variant={tab === t.key ? 'default' : 'ghost'} className="flex-1" onClick={() => setTab(t.key)}>
            <t.icon className="size-4" /> {t.label}
          </Button>
        ))}
      </div>

      {tab === 'debt' && <DebtTab fmtMoney={fmtMoney} />}
      {tab === 'invest' && <InvestTab fmtMoney={fmtMoney} />}
      {tab === 'memo' && <MemoTab />}
      {tab === 'rate' && <RateTab currencies={currencies} setCurrencies={setCurrencies} currency={currency} setCurrency={setCurrency} />}
    </div>
  )
}