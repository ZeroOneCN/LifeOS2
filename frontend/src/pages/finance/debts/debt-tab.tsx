import { useEffect, useState } from 'react'
import {
  AlertTriangle,
  ArrowDownCircle,
  ArrowUpCircle,
  Banknote,
  HandCoins,
  ListTree,
  Loader2,
  Pencil,
  Plus,
  Receipt,
  Trash2,
  Wallet,
} from 'lucide-react'
import { toast } from 'sonner'

import { useRealtime } from '@/hooks/use-realtime'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'
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
  stickyLeftClass,
  stickyRightClass,
} from '@/components/ui/table'
import { Textarea } from '@/components/ui/textarea'
import { StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/chart-utils'
import { Hint, Tip } from '@/components/ui/tip'
import { api } from '@/lib/api'

import {
  channelMeta,
  channelOptions,
  directionMeta,
  statusMeta,
  type DebtPayment,
  type DebtRecord,
  type DebtStats,
  type Fmt,
  type LoanSync,
} from './shared'
import { StatCard } from './stat-card'

/* ---------------- 民间借贷 ---------------- */

export function DebtTab({ fmtMoney }: { fmtMoney: Fmt }) {
  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const [refresh, setRefresh] = useState(0)
  const realtimeTick = useRealtime(30_000)
  const { data: stats } = useStats<DebtStats>('/finance/debts', days, refresh)
  const [items, setItems] = useState<DebtRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [loanSync, setLoanSync] = useState<LoanSync | null>(null)
  const [dialog, setDialog] = useState<null | { editing?: DebtRecord }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [repayTarget, setRepayTarget] = useState<DebtRecord | null>(null)
  const [repayForm, setRepayForm] = useState({ repay_date: '', amount: '', discount: '', note: '' })
  const [detailTarget, setDetailTarget] = useState<DebtRecord | null>(null)
  const [payments, setPayments] = useState<DebtPayment[]>([])
  const [saving, setSaving] = useState(false)
  const [editPaymentTarget, setEditPaymentTarget] = useState<{ debt: DebtRecord; payment: DebtPayment } | null>(null)
  const [editPaymentForm, setEditPaymentForm] = useState({ repay_date: '', amount: '', discount: '', note: '' })
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
  }, [page, realtimeTick])

  const remaining = (d: DebtRecord) => (d.remaining != null ? d.remaining : d.amount)

  const openCreate = () => {
    setForm({ debt_date: new Date().toISOString().slice(0, 10), name: '', direction: 'borrow', counterparty: '', amount: '', remaining: '', interest_rate: '', interest_total: '', channel: '现金', due_date: '', status: 'active', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      debt_date: form.debt_date, name: form.name, direction: form.direction,
      counterparty: form.counterparty || null, amount: Number(form.amount),
      remaining: form.remaining ? Number(form.remaining) : null,
      interest_rate: form.interest_rate ? Number(form.interest_rate) : null,
      interest_total: form.interest_total ? Number(form.interest_total) : 0,
      channel: form.channel || null,
      due_date: form.due_date || null, status: form.status, note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/debts', dialog.editing.id, payload)
      else await api.create('/finance/debts', payload)
      setDialog(null)
      await load()
      setRefresh((v) => v + 1)
      toast.success(dialog?.editing ? '借贷记录已更新' : '借贷记录已添加')
    } catch (e) {
      toast.error(dialog?.editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const remove = async (d: DebtRecord) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/debts', d.id)
      if (items.length === 1 && page > 1) setPage(page - 1)
      else await load()
      setRefresh((v) => v + 1)
      toast.success('借贷记录已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openRepay = (d: DebtRecord) => {
    setRepayForm({ repay_date: new Date().toISOString().slice(0, 10), amount: String(remaining(d)), discount: '', note: '' })
    setRepayTarget(d)
  }
  // 实际金额（实付）= 还款金额（清账额）- 优惠金额，实付为派生展示值
  const actualOf = (amount: string, discount: string) =>
    Math.max(0, (Number(amount) || 0) - (Number(discount) || 0))
  const submitRepay = async () => {
    if (!repayTarget) return
    const amount = Number(repayForm.amount) || 0  // 本次清账金额
    const discount = Number(repayForm.discount) || 0
    if (!repayForm.amount || amount <= 0) {
      toast.error('请填写有效的还款金额')
      return
    }
    if (discount < 0) {
      toast.error('优惠金额不能为负')
      return
    }
    if (discount > amount) {
      toast.error('优惠金额不能大于还款金额')
      return
    }
    const remain = remaining(repayTarget)
    if (amount > remain + 1e-6) {
      toast.error('还款金额超过剩余', { description: `剩余 ${fmtMoney(remain)}` })
      return
    }
    setSaving(true)
    try {
      await api.post(`/finance/debts/${repayTarget.id}/repay`, {
        repay_date: repayForm.repay_date, amount, discount, note: repayForm.note || null,
      })
      setRepayTarget(null)
      await load()
      setRefresh((v) => v + 1)
      toast.success('还款已记录')
    } catch (e) {
      toast.error('还款失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  const openDetail = async (d: DebtRecord) => {
    setDetailTarget(d)
    setPayments([])
    try {
      const list = await api.query<DebtPayment[]>(`/finance/debts/${d.id}/payments`)
      setPayments(list)
    } catch {
      setPayments([])
    }
  }
  const hasPaid = (d: DebtRecord) => Math.max(0, d.amount - remaining(d))
  const deletePayment = async (p: DebtPayment, d: DebtRecord) => {
    if (!(await confirm())) return
    try {
      await api.del(`/finance/debts/${d.id}/payments/${p.id}`)
      setPayments((prev) => prev.filter((x) => x.id !== p.id))
      await load()
      setRefresh((v) => v + 1)
      toast.success('还款明细已删除，剩余金额已回滚')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openEditPayment = (p: DebtPayment, d: DebtRecord) => {
    setEditPaymentForm({
      repay_date: p.repay_date,
      amount: String(p.amount || 0),  // 还款/清账金额（含优惠部分）
      discount: String(p.discount ?? 0),
      note: p.note ?? '',
    })
    setEditPaymentTarget({ debt: d, payment: p })
  }

  const submitEditPayment = async () => {
    if (!editPaymentTarget) return
    const { debt, payment } = editPaymentTarget
    const amount = Number(editPaymentForm.amount) || 0  // 本次清账金额
    const discount = Number(editPaymentForm.discount) || 0
    if (!editPaymentForm.repay_date || !editPaymentForm.amount) {
      toast.error('请填写日期和金额')
      return
    }
    if (amount <= 0) {
      toast.error('请填写有效的还款金额')
      return
    }
    if (discount < 0 || discount > amount) {
      toast.error('优惠金额需在 0 与还款金额之间')
      return
    }
    setSaving(true)
    try {
      await api.patch(`/finance/debts/${debt.id}/payments/${payment.id}`, {
        repay_date: editPaymentForm.repay_date,
        amount,
        discount,
        note: editPaymentForm.note || null,
      })
      setEditPaymentTarget(null)
      // 重新加载债务列表和还款明细，确保弹窗数据实时同步
      await load()
      const updated = await api.query<DebtRecord>(`/finance/debts/${debt.id}`)
      setDetailTarget(updated)
      const list = await api.query<DebtPayment[]>(`/finance/debts/${debt.id}/payments`)
      setPayments(list)
      setRefresh((v) => v + 1)
      toast.success('还款明细已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  /** 整列无有效值时隐藏，避免整列「—」占宽；任一记录填写则恢复显示 */
  const showInterest =
    items.length === 0 ||
    items.some((d) => (d.interest_total ?? 0) > 0 || (d.interest_rate ?? 0) > 0)
  const showDue = items.length === 0 || items.some((d) => !!d.due_date)
  const colCount = 13 - (showInterest ? 0 : 1) - (showDue ? 0 : 1)

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <StatsPeriodPicker
          value={days}
          onChange={(d) => {
            setDays(d)
            setGlobalStatsDays(d)
          }}
        />
      </div>
      <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Wallet} label="民间债务总数" value={String(stats?.total ?? 0)} />
            <StatCard icon={ArrowDownCircle} label="借出应收" value={fmtMoney(stats?.lend_total ?? 0)} className={(stats?.lend_total ?? 0) > 0 ? 'text-success' : 'text-muted-foreground'} />
            <StatCard icon={ArrowUpCircle} label="借入应付" value={fmtMoney(stats?.borrow_total ?? 0)} className={(stats?.borrow_total ?? 0) > 0 ? 'text-danger' : 'text-muted-foreground'} />
            <StatCard icon={HandCoins} label="未结清余额" value={fmtMoney(stats?.outstanding ?? 0)} className={(stats?.outstanding ?? 0) > 0 ? 'text-danger' : 'text-muted-foreground'} />
          </section>

          {(stats?.overdue ?? 0) > 0 && (
            <Card className="border-danger/40 bg-danger-muted">
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium text-danger-muted-foreground">
                  <AlertTriangle className="size-4" /> 已逾期 {stats?.overdue ?? 0} 笔待处理
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1.5 text-sm">
                {(stats?.overdue_list ?? []).map((o, i) => (
                  <div key={i} className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-white/70 dark:bg-white/5 px-3 py-1.5">
                    <span>{o.name}{o.counterparty ? `（${o.counterparty}）` : ''}<Badge className={`ml-2 ${directionMeta[o.direction]?.className}`}>{directionMeta[o.direction]?.label}</Badge></span>
                    <span className="text-muted-foreground">到期 {o.due_date ?? '—'} · 剩余 <span className="font-medium text-danger-muted-foreground">{fmtMoney(o.remaining)}</span></span>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
        </>

      {/* 网贷只读同步 */}
      {loanSync && loanSync.platform_count > 0 && (
        <Card className="border-decor-indigo/30 bg-decor-indigo/10">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium text-decor-indigo">
              <Receipt className="size-4" /> 网贷欠款同步（来源：账单管理 · 网贷借还）
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-2">
              {loanSync.platforms.map((p) => (
                <Badge key={p.platform_id} variant="outline" className="bg-white/80 dark:bg-white/5">
                  {p.name}：<span className="font-medium text-danger">{fmtMoney(p.remaining)}</span>
                  <span className="text-muted-foreground">（{p.bill_count} 笔）</span>
                </Badge>
              ))}
              <Badge className="bg-decor-indigo/15 text-decor-indigo">合计 {fmtMoney(loanSync.total_remaining)}</Badge>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="p-0">
          <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
            <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">民间借贷明细</CardTitle>
            <CardHeaderActions>
              <Button onClick={openCreate}><Plus /> 新增借款</Button>
            </CardHeaderActions>
          </CardHeader>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className={`w-24 ${stickyLeftClass}`}>日期</TableHead><TableHead>名称</TableHead><TableHead>对方</TableHead><TableHead>方向</TableHead><TableHead>途径</TableHead>
                <TableHead className="text-right">额度</TableHead><TableHead className="text-right">已还</TableHead><TableHead className="text-right">剩余</TableHead>{showInterest && <TableHead className="text-right">利息</TableHead>}{showDue && <TableHead>到期</TableHead>}<TableHead>备注</TableHead><TableHead>状态</TableHead><TableHead className={`w-28 text-right ${stickyRightClass}`}>操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow><TableCell colSpan={colCount} className="h-24 text-center text-muted-foreground"><Loader2 className="mx-auto size-5 animate-spin" /></TableCell></TableRow>
                ) : (
                  <TableRow><TableCell colSpan={colCount} className="h-24 text-center text-muted-foreground">暂无民间借款记录</TableCell></TableRow>
                )
              ) : items.map((d) => {
                const paid = hasPaid(d)
                const intr = d.interest_total ?? 0
                return (
                <TableRow key={d.id}>
                  <TableCell className={`whitespace-nowrap text-muted-foreground ${stickyLeftClass}`}>{d.debt_date}</TableCell>
                  <TableCell className="font-medium">
                    <span className="block max-w-[140px] truncate" title={d.name}>{d.name}</span>
                  </TableCell>
                  <TableCell>
                    <span className="block max-w-[120px] truncate" title={d.counterparty ?? ''}>{d.counterparty ?? '—'}</span>
                  </TableCell>
                  <TableCell><Badge className={directionMeta[d.direction]?.className}>{directionMeta[d.direction]?.label}</Badge></TableCell>
                  <TableCell>{d.channel ? <Badge variant="outline" className={channelMeta[d.channel]?.className}>{d.channel}</Badge> : '—'}</TableCell>
                  <TableCell className="text-right">{fmtMoney(d.amount)}</TableCell>
                  <TableCell className="text-right text-muted-foreground">{paid > 0 ? fmtMoney(paid) : '—'}</TableCell>
                  <TableCell className={`text-right font-medium ${remaining(d) > 0 ? 'text-danger' : 'text-muted-foreground'}`}>{fmtMoney(remaining(d))}</TableCell>
                  {showInterest && (
                    <TableCell className="text-right">
                      <div className="font-medium">{intr > 0 ? fmtMoney(intr) : '—'}</div>
                      {d.interest_rate != null && d.interest_rate > 0 && <div className="text-xs text-muted-foreground">{d.interest_rate}%/年</div>}
                    </TableCell>
                  )}
                  {showDue && <TableCell className="text-muted-foreground">{d.due_date ?? '—'}</TableCell>}
                  <TableCell className="max-w-[160px] truncate text-muted-foreground">
                    {d.note ? <span className="block max-w-[160px] truncate" title={d.note}>{d.note}</span> : '—'}
                  </TableCell>
                  <TableCell><Badge className={statusMeta[d.status]?.className}>{statusMeta[d.status]?.label}</Badge></TableCell>
                  <TableCell className={`text-right ${stickyRightClass}`}>
                    <div className="flex justify-end gap-1">
                      <Tip label="还款明细"><Button variant="ghost" size="icon" onClick={() => openDetail(d)}><ListTree /></Button></Tip>
                      {d.status === 'active' && remaining(d) > 0 && (
                        <Tip label="还款/收款"><Button variant="ghost" size="icon" onClick={() => openRepay(d)}><Banknote /></Button></Tip>
                      )}
                      <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setForm({ debt_date: d.debt_date, name: d.name, direction: d.direction, counterparty: d.counterparty ?? '', amount: String(d.amount), remaining: d.remaining != null ? String(d.remaining) : '', interest_rate: d.interest_rate != null ? String(d.interest_rate) : '', interest_total: d.interest_total != null ? String(d.interest_total) : '', channel: d.channel ?? '现金', due_date: d.due_date ?? '', status: d.status, note: d.note ?? '' }); setDialog({ editing: d }) }}><Pencil /></Button></Tip>
                      <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(d)}><Trash2 /></Button></Tip>
                    </div>
                  </TableCell>
                </TableRow>
                )
              })}
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
            <div className="space-y-2"><Label>日期 *</Label><DatePicker value={form.debt_date} onChange={(v) => setForm({ ...form, debt_date: v })} /></div>
            <div className="space-y-2"><Label>债务名称 *</Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="如 朋友借款 / 房贷" /></div>
            <div className="space-y-2"><Label>方向 *</Label>
              <Select value={form.direction} onValueChange={(v) => setForm({ ...form, direction: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="borrow">借入（应付）</SelectItem><SelectItem value="lend">借出（应收）</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>对方</Label><Input value={form.counterparty} onChange={(e) => setForm({ ...form, counterparty: e.target.value })} placeholder="债权人 / 借款人" /></div>
            <div className="space-y-2"><Label>途径</Label>
              <Select value={form.channel || '现金'} onValueChange={(v) => setForm({ ...form, channel: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{channelOptions.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>额度使用(总额) *</Label><Input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>剩余债务</Label><Input type="number" min={0} step="0.01" value={form.remaining} onChange={(e) => setForm({ ...form, remaining: e.target.value })} /></div>
            <div className="space-y-2"><Label>年利率(%)</Label><Input type="number" step="0.01" min={0} value={form.interest_rate} onChange={(e) => setForm({ ...form, interest_rate: e.target.value })} placeholder="参考备注" /></div>
            <div className="space-y-2"><Label>应付利息总额</Label><Input type="number" step="0.01" min={0} value={form.interest_total} onChange={(e) => setForm({ ...form, interest_total: e.target.value })} placeholder="0 表示不计息" /></div>
            <div className="space-y-2"><Label>还款日</Label><DatePicker value={form.due_date} onChange={(v) => setForm({ ...form, due_date: v })} /></div>
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
            <div className="space-y-2"><Label>日期 *</Label><DatePicker value={repayForm.repay_date} onChange={(v) => setRepayForm({ ...repayForm, repay_date: v })} /></div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">{repayTarget?.direction === 'borrow' ? '还款金额' : '收款金额'} *<Hint text="本次清账金额（含优惠部分），剩余将按此金额减少" /></Label>
              <Input type="number" min={0.01} step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">优惠金额<Hint text="减免 / 抵扣券金额（含在此次还款内）" /></Label>
              <Input type="number" min={0} step="0.01" value={repayForm.discount} onChange={(e) => setRepayForm({ ...repayForm, discount: e.target.value })} placeholder="0.00" />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">实际{repayTarget?.direction === 'borrow' ? '还款' : '收款'}（实付）<Hint text="实付 = 还款金额 − 优惠" /></Label>
              <div className="flex h-9 items-center justify-end rounded-md bg-muted px-3 text-lg font-extrabold text-success">
                {fmtMoney(actualOf(repayForm.amount, repayForm.discount))}
              </div>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Input value={repayForm.note} onChange={(e) => setRepayForm({ ...repayForm, note: e.target.value })} placeholder="如 微信转账 / 现金结清" /></div>
          </div>
          {repayTarget && (
            <p className="text-xs text-muted-foreground">
              本次清账 <span className="font-semibold text-success">{fmtMoney(Number(repayForm.amount) || 0)}</span>
              {' = 实付 '}
              <span className="font-semibold text-success">{fmtMoney(actualOf(repayForm.amount, repayForm.discount))}</span>
              {' + 优惠 '}
              <span className="font-semibold text-warning">{fmtMoney(Number(repayForm.discount) || 0)}</span>
              {' · 清账后剩余 '}
              <span className="font-semibold text-danger">{fmtMoney(Math.max(0, remaining(repayTarget) - (Number(repayForm.amount) || 0)))}</span>
            </p>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setRepayTarget(null)}>取消</Button>
            <Button onClick={submitRepay} disabled={saving}><Banknote className="size-4" /> 确认{repayTarget?.direction === 'borrow' ? '还款' : '收款'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 还款明细查看弹窗 */}
      <Dialog open={detailTarget !== null} onOpenChange={(o) => !o && setDetailTarget(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><ListTree className="size-4" /> 还款明细</DialogTitle>
            <DialogDescription>
              {detailTarget ? `${detailTarget.name} · ${directionMeta[detailTarget.direction]?.label}${detailTarget.counterparty ? `（${detailTarget.counterparty}）` : ''}` : ''}
            </DialogDescription>
          </DialogHeader>
          {detailTarget && (
            <div className="grid grid-cols-3 gap-2">
              <div className="rounded-lg bg-muted p-2 text-center">
                <div className="text-xs text-muted-foreground">额度</div>
                <div className="text-sm font-semibold">{fmtMoney(detailTarget.amount)}</div>
              </div>
              <div className="rounded-lg bg-muted p-2 text-center">
                <div className="text-xs text-muted-foreground">已还</div>
                <div className="text-sm font-semibold text-success">{fmtMoney(hasPaid(detailTarget))}</div>
              </div>
              <div className="rounded-lg bg-muted p-2 text-center">
                <div className="text-xs text-muted-foreground">剩余</div>
                <div className={`text-sm font-semibold ${remaining(detailTarget) > 0 ? 'text-danger' : 'text-success'}`}>{fmtMoney(remaining(detailTarget))}</div>
              </div>
            </div>
          )}
          {detailTarget && (
            <p className="text-xs text-muted-foreground">
              还款合计 <span className="font-semibold text-muted-foreground">{fmtMoney(payments.reduce((s, p) => s + (p.amount || 0), 0))}</span>
              {' · '}
              其中优惠合计 <span className="font-semibold text-warning">{fmtMoney(payments.reduce((s, p) => s + (p.discount ?? 0), 0))}</span>
              {' · '}
              实付合计 <span className="font-semibold text-success">{fmtMoney(payments.reduce((s, p) => s + ((p.amount || 0) - (p.discount ?? 0)), 0))}</span>
            </p>
          )}
          <div className="space-y-1.5">
            {payments.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">暂无还款明细</p>
            ) : (
              payments.map((p) => (
                <div key={p.id} className="flex items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="font-medium shrink-0">{p.repay_date}</span>
                    {p.note && <Tip label={p.note}><span className="truncate text-muted-foreground">· {p.note}</span></Tip>}
                  </div>
                  <div className="flex shrink-0 items-center gap-3">
                    <span className="text-muted-foreground">还款 {fmtMoney(p.amount || 0)}</span>
                    {(p.discount ?? 0) > 0 && (
                      <span className="text-warning">优惠 {fmtMoney(p.discount ?? 0)}</span>
                    )}
                    <span className="font-medium text-success">实付 {fmtMoney(p.actual ?? ((p.amount || 0) - (p.discount ?? 0)))}</span>
                    {detailTarget && (
                      <>
                        <Tip label="修改明细"><Button variant="ghost" size="icon" className="size-7" onClick={() => openEditPayment(p, detailTarget)}><Pencil className="size-4" /></Button></Tip>
                        <Tip label="删除明细并回滚剩余"><Button variant="ghost" size="icon" className="size-7 text-destructive" onClick={() => deletePayment(p, detailTarget)}><Trash2 className="size-4" /></Button></Tip>
                      </>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </DialogContent>
      </Dialog>

      {confirmDialog}

      {/* 修改还款明细弹窗 */}
      <Dialog open={editPaymentTarget !== null} onOpenChange={(o) => !o && setEditPaymentTarget(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>修改还款明细</DialogTitle>
            <DialogDescription>更新日期、金额或备注，剩余金额将自动重新计算</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>日期 *</Label><DatePicker value={editPaymentForm.repay_date} onChange={(v) => setEditPaymentForm({ ...editPaymentForm, repay_date: v })} /></div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">还款金额 *<Hint text="本次清账金额（含优惠部分），剩余将按此金额减少" /></Label>
              <Input type="number" min={0.01} step="0.01" value={editPaymentForm.amount} onChange={(e) => setEditPaymentForm({ ...editPaymentForm, amount: e.target.value })} />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">优惠金额<Hint text="减免 / 抵扣券金额（含在此次还款内）" /></Label>
              <Input type="number" min={0} step="0.01" value={editPaymentForm.discount} onChange={(e) => setEditPaymentForm({ ...editPaymentForm, discount: e.target.value })} placeholder="0.00" />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">实际还款（实付）<Hint text="实付 = 还款金额 − 优惠" /></Label>
              <div className="flex h-9 items-center justify-end rounded-md bg-muted px-3 text-lg font-extrabold text-success">
                {fmtMoney(actualOf(editPaymentForm.amount, editPaymentForm.discount))}
              </div>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Input value={editPaymentForm.note} onChange={(e) => setEditPaymentForm({ ...editPaymentForm, note: e.target.value })} placeholder="如 微信转账 / 现金结清" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditPaymentTarget(null)}>取消</Button>
            <Button onClick={submitEditPayment} disabled={saving}><Pencil className="size-4" /> 保存修改</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
