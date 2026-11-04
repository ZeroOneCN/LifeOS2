import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  Banknote,
  Calendar,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock,
  FileText,
  Layers,
  ListTree,
  Loader2,
  Pencil,
  Plus,
  ShieldAlert,
  Trash2,
  Wallet,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'
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
import { DatePicker } from '@/components/ui/date-picker'
import { MonthPicker } from '@/components/ui/month-picker'
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
import { Switch } from '@/components/ui/switch'
import { Hint, Tip } from '@/components/ui/tip'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { toast } from 'sonner'

import { fmt, remainingOf, round2 } from './shared'
import { StatCard } from './stat-card'

/* ---------------- 网贷借还 ---------------- */

type LoanPlatform = { id: number; name: string; bill_day?: number; due_day?: number; credit_limit?: number; grace_days?: number; grace_auto?: boolean; grace_hour?: number; penalty_rate?: number; note?: string }
type LoanPlatformStats = { total_remaining: number; platform_count: number; platforms: (LoanPlatform & { total_owed: number; total_paid: number; remaining: number; bill_count: number })[] }

type LoanBill = {
  id: number
  platform_id?: number
  bill_month: string
  due_date?: string
  amount: number
  interest?: number
  paid_amount: number
  status: 'pending' | 'partial' | 'cleared'
  grace_applied?: boolean
  note?: string
}
type LoanBillStats = {
  total: number; paid: number; remaining: number; total_interest?: number
  status: { pending: number; partial: number; cleared: number }
  by_month: { month: string; amount: number }[]
  upcoming: { id: number; platform_id?: number; bill_month: string; due_date?: string; amount: number; interest?: number; paid_amount: number; remaining: number; status: string; grace_applied?: boolean; overdue?: boolean }[]
}
type Repayment = { id: number; bill_id?: number; repay_date: string; amount: number; discount?: number; method?: string; note?: string }

const billStatusMeta: Record<string, { label: string; className: string }> = {
  pending: { label: '待还', className: 'bg-warning-muted text-warning-muted-foreground' },
  partial: { label: '部分已还', className: 'bg-info-muted text-info-muted-foreground' },
  cleared: { label: '已结清', className: 'bg-success-muted text-success-muted-foreground' },
}

export function LoanTab() {
  const realtimeTick = useRealtime(30_000)
  const [platforms, setPlatforms] = useState<LoanPlatform[]>([])
  const [platformStats, setPlatformStats] = useState<LoanPlatformStats | null>(null)
  const [bills, setBills] = useState<LoanBill[]>([])
  const [billStats, setBillStats] = useState<LoanBillStats | null>(null)
  const [loanMonth, setLoanMonth] = useState(() => { const n = new Date(); return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}` })
  const [repayments, setRepayments] = useState<Repayment[]>([])

  const [pfAddDialog, setPfAddDialog] = useState(false)
  const [newPf, setNewPf] = useState<Record<string, string>>({})
  const [pfEdit, setPfEdit] = useState<null | LoanPlatform>(null)
  const [pfEditForm, setPfEditForm] = useState<Record<string, string>>({})
  const [repStats, setRepStats] = useState<{ total_paid: number; total_discount: number; count: number; by_month: { month: string; amount: number }[] } | null>(null)
  const [billDialog, setBillDialog] = useState<null | { editing?: LoanBill }>(null)
  const [billForm, setBillForm] = useState<Record<string, string>>({})
  const [repayDialog, setRepayDialog] = useState<null | LoanBill>(null)
  const [repayForm, setRepayForm] = useState<Record<string, string>>({})
  const [repayViewDialog, setRepayViewDialog] = useState<number | null>(null)  // 查看还款记录的 bill_id
  const [repayEditDialog, setRepayEditDialog] = useState<Repayment | null>(null)
  const [repayEditForm, setRepayEditForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  // 容时服务按平台配置：到期后顺延天数、是否自动生效（免申请）、最终截止时刻（0 = 当天结束）
  const graceOf = (platformId?: number) => {
    const pf = platforms.find((p) => p.id === platformId)
    return { days: pf?.grace_days ?? 3, hour: pf?.grace_hour ?? 0, auto: !!pf?.grace_auto }
  }
  /**
   * 最终截止时刻：还款日 + 容时天数，精确到截止小时（0 表示当天结束）。
   * 例：邮储（4 天 / 17 点）还款日 2026-10-28 → 2026-11-01 17:00。
   */
  const graceDeadline = (platformId?: number, due?: string) => {
    if (!due) return null
    const { days, hour } = graceOf(platformId)
    const d = new Date(`${due}T00:00:00`)
    d.setDate(d.getDate() + days)
    if (hour > 0) d.setHours(hour, 0, 0, 0)
    else d.setHours(23, 59, 59, 999)
    return d
  }
  /** 最终还款日文案（含截止时刻），如「2026-11-01 17:00」；截止为当天结束时只显示日期。 */
  const graceDeadlineText = (platformId?: number, due?: string) => {
    const d = graceDeadline(platformId, due)
    if (!d) return ''
    const pad = (n: number) => String(n).padStart(2, '0')
    const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
    const { hour } = graceOf(platformId)
    return hour > 0 ? `${day} ${pad(hour)}:00` : day
  }
  /** 容时剩余时间数值文案：如「2 天 5 小时」，已到最终截止时刻返回「已超时」。 */
  const graceRemainValue = (platformId?: number, due?: string) => {
    const d = graceDeadline(platformId, due)
    if (!d) return ''
    const ms = d.getTime() - Date.now()
    if (ms <= 0) return '已超时'
    const totalHours = Math.floor(ms / 3_600_000)
    const days = Math.floor(totalHours / 24)
    const hours = totalHours % 24
    if (days > 0) return `${days} 天${hours > 0 ? ` ${hours} 小时` : ''}`
    if (totalHours > 0) return `${totalHours} 小时`
    return `${Math.max(1, Math.floor(ms / 60_000))} 分钟`
  }
  /** 平台违约金日费率（单位 %/天，0 表示该平台不计收违约金）。 */
  const penaltyRateOf = (platformId?: number) => platforms.find((p) => p.id === platformId)?.penalty_rate ?? 0
  /**
   * 预计违约金：剩余欠款 × 日费率(%) × 逾期天数。
   * 起算时间与逾期判定一致（超过最终还款日含容时的次日），仅用于预警展示，不写入账务金额。
   */
  const penaltyEstimate = (b: LoanBill) => {
    const rate = penaltyRateOf(b.platform_id)
    const deadline = graceDeadline(b.platform_id, b.due_date)
    if (!rate || !deadline) return { rate, days: 0, amount: 0 }
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const finalDay = new Date(deadline)
    finalDay.setHours(0, 0, 0, 0)
    const days = Math.max(0, Math.round((today.getTime() - finalDay.getTime()) / 86_400_000))
    if (days <= 0) return { rate, days: 0, amount: 0 }
    return { rate, days, amount: round2(remainingOf(b.amount, b.paid_amount) * (rate / 100) * days) }
  }
  // 逾期账单：已过「最终还款日（含容时）」的账单，用于站内重大提醒（弹窗 + 常驻横幅）
  const overdueBills = useMemo(() => {
    const now = Date.now()
    return bills
      .filter((b) => b.status !== 'cleared' && b.due_date && (graceDeadline(b.platform_id, b.due_date)?.getTime() ?? 0) < now)
      .sort((a, b) => (a.due_date || '').localeCompare(b.due_date || ''))
  }, [bills, platforms])
  // 容时窗口内的账单：已过原还款日、但尚未到最终截止时刻（最后一次机会，不判逾期）
  const graceBills = useMemo(() => {
    const now = Date.now()
    return bills
      .filter((b) => {
        if (b.status === 'cleared' || !b.due_date) return false
        const g = graceOf(b.platform_id)
        if (!(g.days > 0 && (g.auto || !!b.grace_applied))) return false
        const dueEnd = new Date(`${b.due_date}T23:59:59`).getTime()
        const deadline = graceDeadline(b.platform_id, b.due_date)?.getTime() ?? 0
        return now > dueEnd && now <= deadline
      })
      .sort((a, b) => (a.due_date || '').localeCompare(b.due_date || ''))
  }, [bills, platforms])
  const [overdueAlertOpen, setOverdueAlertOpen] = useState(false)
  const overdueAlertShown = useRef(false)
  const [graceAlertOpen, setGraceAlertOpen] = useState(false)
  const graceAlertShown = useRef(false)
  useEffect(() => {
    // 进入页面或出现异常账单时弹窗一次：逾期优先，其次容时；关闭后本次停留不再重复弹出
    if (overdueBills.length > 0 && !overdueAlertShown.current) {
      overdueAlertShown.current = true
      setOverdueAlertOpen(true)
    } else if (graceBills.length > 0 && !graceAlertShown.current) {
      graceAlertShown.current = true
      setGraceAlertOpen(true)
    }
  }, [overdueBills.length, graceBills.length])
  // 计算逾期天数（按本地日期比较，避免时区偏移导致差一天）
  const overdueDays = (d?: string) => {
    if (!d) return 0
    const n = new Date()
    const today = `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}-${String(n.getDate()).padStart(2, '0')}`
    const diff = Math.round((new Date(`${today}T00:00:00`).getTime() - new Date(`${d}T00:00:00`).getTime()) / 86400000)
    return diff > 0 ? diff : 0
  }

  const loadPlatforms = async () => {
    const res = await api.list<LoanPlatform>('/finance/loan-platforms', { page_size: 100 })
    setPlatforms(res.items)
    api.stats<LoanPlatformStats>('/finance/loan-platforms').then(setPlatformStats).catch(() => null)
  }
  const loadBills = async () => {
    // 数据量可能超过单页上限(100)，翻页拉取全量以便按账单月翻页时能访问到历史月份
    const all: LoanBill[] = []
    let page = 1
    let total = 0
    do {
      const res = await api.list<LoanBill>('/finance/loan-bills', { page, page_size: 100 })
      all.push(...res.items)
      total = res.total
      page += 1
    } while (all.length < total)
    // 固定排序：先按平台ID，再按月，避免同一月份内平台出现顺序跳动
    all.sort((a, b) => (a.platform_id ?? 0) - (b.platform_id ?? 0) || a.bill_month.localeCompare(b.bill_month))
    setBills(all)
    api.stats<LoanBillStats>('/finance/loan-bills').then(setBillStats).catch(() => null)
  }
  const loadRepayments = async (billId: number | null) => {
    if (!billId) { setRepayments([]); return }
    api.query<Repayment[]>(`/finance/repayments?bill_id=${billId}`).then(setRepayments).catch(() => setRepayments([]))
  }
  const loadRepStats = () => {
    api.query<{ total_paid: number; total_discount: number; count: number; by_month: { month: string; amount: number }[] }>('/finance/repayments/stats?days=3650').then(setRepStats).catch(() => setRepStats(null))
  }

  useEffect(() => {
    loadPlatforms()
    loadBills()
    loadRepStats()
  }, [realtimeTick])

  const refresh = async () => {
    await loadBills()
    await loadPlatforms()
    loadRepStats()
    if (repayViewDialog) await loadRepayments(repayViewDialog)
  }

  const platformName = (id?: number) => platforms.find((p) => p.id === id)?.name ?? '—'

  const shiftMonth = (ym: string, delta: number) => {
    const [y, m] = ym.split('-').map(Number)
    const dt = new Date(y, m - 1 + delta, 1)
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`
  }
  const monthBills = bills.filter((b) => b.bill_month.slice(0, 7) === loanMonth)
  const thisMonth = new Date().toISOString().slice(0, 7)
  const thisMonthBills = bills.filter((b) => b.bill_month.slice(0, 7) === thisMonth)
  const thisMonthPrincipal = thisMonthBills.reduce((s, b) => s + (b.amount - (b.interest || 0)), 0)
  const thisMonthInterest = thisMonthBills.reduce((s, b) => s + (b.interest || 0), 0)
  const thisMonthRemaining = Math.max(0, round2(thisMonthBills.reduce((s, b) => s + remainingOf(b.amount, b.paid_amount), 0)))
  const addPlatform = async () => {
    const name = newPf.name?.trim()
    if (!name) return
    try {
      await api.create('/finance/loan-platforms', {
        name, bill_day: newPf.bill_day ? Number(newPf.bill_day) : null,
        due_day: newPf.due_day ? Number(newPf.due_day) : null,
        credit_limit: newPf.credit_limit ? Number(newPf.credit_limit) : null,
        grace_days: newPf.grace_days !== undefined && newPf.grace_days !== '' ? Number(newPf.grace_days) : 3,
        grace_auto: newPf.grace_auto === '1',
        grace_hour: newPf.grace_hour ? Number(newPf.grace_hour) : 0,
        penalty_rate: newPf.penalty_rate !== undefined && newPf.penalty_rate !== '' ? Number(newPf.penalty_rate) : 0,
        note: newPf.note || null,
      })
      toast.success('平台已添加')
      setPfAddDialog(false)
    } catch (e) {
      toast.error('添加失败', { description: (e as Error).message })
    }
    setNewPf({})
    await loadPlatforms()
  }
  const openPfEdit = (p: LoanPlatform) => {
    setPfEditForm({ name: p.name, bill_day: p.bill_day != null ? String(p.bill_day) : '', due_day: p.due_day != null ? String(p.due_day) : '', credit_limit: p.credit_limit != null ? String(p.credit_limit) : '', grace_days: String(p.grace_days ?? 3), grace_auto: p.grace_auto ? '1' : '0', grace_hour: String(p.grace_hour ?? 0), penalty_rate: String(p.penalty_rate ?? 0) })
    setPfEdit(p)
  }
  const savePfEdit = async () => {
    if (!pfEdit) return
    try {
      await api.update('/finance/loan-platforms', pfEdit.id, {
        name: pfEditForm.name, bill_day: pfEditForm.bill_day ? Number(pfEditForm.bill_day) : null,
        due_day: pfEditForm.due_day ? Number(pfEditForm.due_day) : null,
        credit_limit: pfEditForm.credit_limit ? Number(pfEditForm.credit_limit) : null,
        grace_days: pfEditForm.grace_days !== undefined && pfEditForm.grace_days !== '' ? Number(pfEditForm.grace_days) : 3,
        grace_auto: pfEditForm.grace_auto === '1',
        grace_hour: pfEditForm.grace_hour ? Number(pfEditForm.grace_hour) : 0,
        penalty_rate: pfEditForm.penalty_rate !== undefined && pfEditForm.penalty_rate !== '' ? Number(pfEditForm.penalty_rate) : 0,
      })
      toast.success('平台已更新')
      setPfEdit(null)
    } catch (e) {
      toast.error('更新失败', { description: (e as Error).message })
    }
    await loadPlatforms()
  }
  const removePlatform = async (id: number) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/loan-platforms', id)
      await loadPlatforms()
      toast.success('平台已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  /**
   * 计算账单的最迟还款日。
   * 以账单月份（出账月）为基准取 due_day；若 due_day 早于 bill_day（如美团 25 出账 / 次月 3 还款），
   * 说明还款落在次月，需顺延一个月；日号超出目标月天数时取该月最后一天。
   * 例：美团 bill_day=25、due_day=3 → 2026-09 账单（9.25 出账）最迟 2026-10-03 还款。
   * @param platformId 平台 ID
   * @param billMonth 账单月份（出账月，YYYY-MM 或 YYYY-MM-DD）
   * @returns 最迟还款日（YYYY-MM-DD），无法计算时返回空串
   */
  const dueFor = (platformId: string, billMonth: string) => {
    const pf = platforms.find((p) => p.id === Number(platformId))
    const day = pf?.due_day
    if (!day || !billMonth) return ''
    const [y, m] = billMonth.split('-').map(Number)
    if (!y || !m) return ''
    // 还款日早于出账日 → 还款在次月（跨月还款，仅美团这类平台会出现）
    const crossMonth = pf?.bill_day != null && day < pf.bill_day
    const target = new Date(y, m - 1 + (crossMonth ? 1 : 0), 1)
    const ty = target.getFullYear()
    const tm = target.getMonth() + 1
    const last = new Date(ty, tm, 0).getDate()
    const dd = Math.min(day, last)
    return `${ty}-${String(tm).padStart(2, '0')}-${String(dd).padStart(2, '0')}`
  }
  const openBillCreate = () => {
    const pfId = platforms[0] ? String(platforms[0].id) : ''
    setBillForm({ platform_id: pfId, bill_month: `${loanMonth}-01`, due_date: dueFor(pfId, loanMonth), amount: '', interest: '0', paid_amount: '0', status: 'pending', grace_applied: '0', note: '' })
    setBillDialog({})
  }
  const saveBill = async () => {
    // 规范化 bill_month：确保为 YYYY-MM-DD 格式（MonthPicker 返回 YYYY-MM-01，但若只有 YYYY-MM 则补 -01）
    const billMonth = /^\d{4}-\d{2}$/.test(billForm.bill_month) ? `${billForm.bill_month}-01` : billForm.bill_month
    const payload = {
      platform_id: billForm.platform_id ? Number(billForm.platform_id) : null,
      bill_month: billMonth, due_date: billForm.due_date || null,
      amount: Number(billForm.amount), interest: billForm.interest ? Number(billForm.interest) : 0,
      paid_amount: Number(billForm.paid_amount || 0),
      status: billForm.status, grace_applied: billForm.grace_applied === '1', note: billForm.note || null,
    }
    setSaving(true)
    try {
      if (billDialog?.editing) { await api.update('/finance/loan-bills', billDialog.editing.id, payload); toast.success('账单已更新') }
      else { await api.create('/finance/loan-bills', payload); toast.success('账单已新增') }
      setBillDialog(null)
      await refresh()
    } catch (e) {
      toast.error('保存失败', { description: (e as Error).message })
    } finally {
      setSaving(false)
    }
  }
  const removeBill = async (b: LoanBill) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/loan-bills', b.id)
      await refresh()
      toast.success('账单已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openRepay = (b: LoanBill) => {
    const remaining = remainingOf(b.amount, b.paid_amount)
    setRepayForm({ repay_date: new Date().toISOString().slice(0, 10), amount: remaining > 0 ? remaining.toFixed(2) : '', discount: '', method: '', note: '' })
    setRepayDialog(b)
  }
  const actualPay = (): number => {
    const amt = Number(repayForm.amount) || 0
    const dsc = Number(repayForm.discount) || 0
    return Math.max(0, amt - dsc)
  }
  const submitRepay = async () => {
    if (!repayDialog) return
    const actual = actualPay()
    if (actual <= 0) {
      toast.error('实付金额必须大于 0')
      return
    }
    const payload = {
      bill_id: repayDialog.id, repay_date: repayForm.repay_date,
      amount: actual, discount: repayForm.discount ? Number(repayForm.discount) : 0,
      method: repayForm.method || null, note: repayForm.note || null,
    }
    setSaving(true)
    try {
      await api.create('/finance/repayments', payload)
      setRepayDialog(null)
      await refresh()
      toast.success('还款记录已添加')
    } catch (e) {
      toast.error('保存失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const removeRepay = async (r: Repayment) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/repayments', r.id)
      await refresh()
      toast.success('还款记录已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const openEditRepay = (r: Repayment) => {
    setRepayEditForm({ repay_date: r.repay_date, amount: String(r.amount), discount: String(r.discount ?? 0), method: r.method ?? '', note: r.note ?? '' })
    setRepayEditDialog(r)
  }
  const submitEditRepay = async () => {
    if (!repayEditDialog) return
    const amt = Number(repayEditForm.amount)
    if (amt <= 0) { toast.error('金额必须大于 0'); return }
    const payload = {
      bill_id: repayEditDialog.bill_id!,
      repay_date: repayEditForm.repay_date,
      amount: amt,
      discount: Number(repayEditForm.discount) || 0,
      method: repayEditForm.method || null,
      note: repayEditForm.note || null,
    }
    setSaving(true)
    try {
      await api.update('/finance/repayments', repayEditDialog.id, payload)
      setRepayEditDialog(null)
      await refresh()
      toast.success('还款记录已修改')
    } catch (e) {
      toast.error('保存失败', { description: e instanceof Error ? e.message : '请稍后重试' })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {/* 容时倒计时横幅：已过原还款日但仍在容时窗口内，强调最低还款与不可再次延期 */}
      {graceBills.length > 0 && (
        <div className="flex flex-wrap items-center gap-3 rounded-xl border-2 border-warning bg-warning-muted px-4 py-2.5 bg-warning-muted">
          <Clock className="size-5 shrink-0 animate-pulse text-warning" />
          <span className="text-lg font-extrabold tracking-wide text-warning-muted-foreground">容时最后机会</span>
          <span className="text-sm font-medium text-warning-muted-foreground">
            共 <span className="font-extrabold">{graceBills.length}</span> 笔账单已过原还款日，请至少还够最低还款额，容时不会再次延期
          </span>
          <Button
            size="sm"
            className="ml-auto bg-warning font-bold text-white hover:bg-warning"
            onClick={() => setGraceAlertOpen(true)}
          >
            查看容时明细
          </Button>
        </div>
      )}
      {/* 逾期常驻横幅：进入网贷页即可看到，点击可再次打开重大提醒弹窗 */}
      {overdueBills.length > 0 && (
        <div className="flex flex-col gap-3 rounded-xl border-2 border-danger bg-danger-muted px-4 py-3 dark:bg-danger-muted">
          <div className="flex flex-wrap items-center gap-3">
            <AlertTriangle className="size-6 shrink-0 animate-pulse text-danger" />
            <span className="text-xl font-extrabold tracking-wide text-danger-muted-foreground">账单逾期提醒</span>
            <span className="text-sm font-medium text-danger-muted-foreground">
              共 <span className="text-lg font-extrabold text-warning">{overdueBills.length}</span> 笔账单已逾期，请尽快还款
            </span>
            <Button size="sm" variant="destructive" className="ml-auto font-bold" onClick={() => setOverdueAlertOpen(true)}>
              查看逾期明细
            </Button>
          </div>
          {/* 容时规则：各平台天数/截止时刻不同（如邮储 4 天至第 4 天 17:00 且自动生效） */}
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-danger bg-danger-muted px-3 py-2 border-danger/40 bg-danger-muted">
            <ShieldAlert className="size-5 shrink-0 text-danger" />
            <span className="text-base font-extrabold text-danger">
              已超过最终还款日，将上报征信
            </span>
            <span className="text-sm font-normal text-muted-foreground">
              容时规则按平台配置（如邮储 4 天至 17:00、其余平台 3 天）· 以每笔账单的「最终还款日」为准
            </span>
          </div>
        </div>
      )}
      {platformStats && (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <StatCard icon={Calendar} label="当月待还" value={fmt(thisMonthRemaining)} hint={`${thisMonth} · 本金 ${fmt(thisMonthPrincipal)} ＋ 利息 ${fmt(thisMonthInterest)}`} className="text-danger" />
          <StatCard icon={Wallet} label="累计待还" value={fmt(platformStats.total_remaining)} className="text-danger" />
          <StatCard icon={Wallet} label="累计欠款" value={fmt(billStats?.total ?? 0)} hint={`已还 ${fmt(billStats?.paid ?? 0)}`} className="text-warning" />
          <StatCard icon={Wallet} label="利息总额" value={fmt(billStats?.total_interest ?? 0)} hint="全部账单利息合计" className="text-success" />
          <StatCard icon={Banknote} label="优惠合计" value={fmt(repStats?.total_discount ?? 0)} hint="还款优惠/抵扣" className="text-decor-indigo" />
          <StatCard icon={Layers} label="借款平台" value={`${platformStats.platform_count} 个`} hint={`还款 ${repStats?.count ?? 0} 笔`} />
          <StatCard icon={Banknote} label="待还账单" value={`${(billStats?.status.pending ?? 0) + (billStats?.status.partial ?? 0)} 笔`} hint={`${billStats?.by_month[0]?.month ?? ''} 到期数据`} className="text-decor-indigo" />
          <StatCard icon={FileText} label="本月账单数" value={`${thisMonthBills.length} 笔`} hint={`${thisMonth} 账单`} />
          <StatCard icon={CheckCircle2} label="已结清" value={`${billStats?.status.cleared ?? 0} 笔`} hint="全部已结清账单" className="text-success" />
        </section>
      )}

      {/* 借款平台 */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
          <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">借款平台</CardTitle>
          <CardHeaderActions>
            <Button size="sm" variant="outline" onClick={() => { setNewPf({}); setPfAddDialog(true); }}><Plus /> 新增平台</Button>
          </CardHeaderActions>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {platformStats?.platforms.map((p) => (
            <div key={p.id} className="rounded-lg border p-4">
              <div className="flex items-center justify-between gap-2">
                <span className="truncate text-[15px] font-semibold">{p.name}</span>
                <div className="flex shrink-0 gap-0.5">
                  <Tip label="编辑平台"><Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => openPfEdit(p)}><Pencil className="size-3.5" /></Button></Tip>
                  <Tip label="删除平台"><Button variant="ghost" size="icon" className="h-6 w-6 text-destructive" onClick={() => removePlatform(p.id)}><Trash2 className="size-3.5" /></Button></Tip>
                </div>
              </div>
              {/* 基础信息：标签与数值分列对齐，字号 13px 并加大行距，避免挤成一行 */}
              <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-[13px] leading-5">
                <div className="flex items-baseline justify-between gap-1">
                  <span className="text-muted-foreground">账单日</span>
                  <span className="font-medium tabular-nums">{p.bill_day ?? '—'}</span>
                </div>
                <div className="flex items-baseline justify-between gap-1">
                  <span className="text-muted-foreground">还款日</span>
                  <span className="font-medium tabular-nums">{p.due_day ?? '—'}</span>
                </div>
                <div className="flex items-baseline justify-between gap-1">
                  <span className="text-muted-foreground">额度</span>
                  <span className="font-medium tabular-nums">{p.credit_limit != null ? fmt(p.credit_limit) : '—'}</span>
                </div>
                <div className="flex items-baseline justify-between gap-1">
                  <span className="text-muted-foreground">账单</span>
                  <span className="font-medium tabular-nums">{p.bill_count} 笔</span>
                </div>
              </div>
              {/* 平台规则：容时 / 违约金，独立浅底块与基础信息分层 */}
              <div className="mt-3 space-y-1.5 rounded-md bg-muted/50 px-3 py-2 text-[13px] leading-5">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-muted-foreground">容时</span>
                  <span className="text-right font-medium">
                    {p.grace_days ?? 3} 天{p.grace_auto ? ' · 自动' : ''}{p.grace_hour ? ` · 至 ${String(p.grace_hour).padStart(2, '0')}:00` : ''}
                  </span>
                </div>
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-muted-foreground">违约金</span>
                  <span className="font-medium">{p.penalty_rate ? `${p.penalty_rate}%/天` : '不计收'}</span>
                </div>
              </div>
              {/* 欠款：主数字放大加粗，标签弱化 */}
              <div className="mt-3 flex items-end justify-between gap-2 border-t pt-3">
                <div>
                  <p className="text-xs text-muted-foreground">累计欠款</p>
                  <p className="mt-1 text-lg font-bold leading-none tabular-nums">{fmt(p.total_owed)}</p>
                </div>
                <div className="text-right">
                  <p className="text-xs text-muted-foreground">待还</p>
                  <p className={`mt-1 text-lg font-bold leading-none tabular-nums ${p.remaining > 0 ? 'text-danger' : 'text-success'}`}>{fmt(p.remaining)}</p>
                </div>
              </div>
            </div>
          ))}
          {platformStats && platformStats.platforms.length === 0 && (
            <p className="col-span-full py-6 text-center text-sm text-muted-foreground">暂无借款平台</p>
          )}
        </CardContent>
      </Card>

      {/* 网贷账单 */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
          <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">网贷账单</CardTitle>
          <CardHeaderActions>
            <Tip label="上一月"><Button variant="ghost" size="icon" onClick={() => setLoanMonth(shiftMonth(loanMonth, -1))}><ChevronLeft /></Button></Tip>
            <MonthPicker value={`${loanMonth}-01`} onChange={(v) => setLoanMonth(v.slice(0, 7))} className="h-8 w-[140px]" />
            <Tip label="下一月"><Button variant="ghost" size="icon" onClick={() => setLoanMonth(shiftMonth(loanMonth, 1))}><ChevronRight /></Button></Tip>
            <Button size="sm" variant="outline" onClick={() => { const n = new Date(); setLoanMonth(`${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`) }}>当月</Button>
            <Button onClick={openBillCreate} className="ml-1"><Plus /> 新增账单</Button>
          </CardHeaderActions>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>平台</TableHead><TableHead>账单月份</TableHead><TableHead>到期日</TableHead>
                <TableHead className="whitespace-nowrap">欠款 <span className="mx-1 text-muted-foreground/40">|</span> 利息</TableHead><TableHead className="whitespace-nowrap">已还 <span className="mx-1 text-muted-foreground/40">|</span> 剩余</TableHead><TableHead>状态</TableHead><TableHead>操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {monthBills.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="h-16 text-center text-muted-foreground">{bills.length === 0 ? '暂无账单' : `「${loanMonth}」无账单`}</TableCell></TableRow>
              ) : monthBills.map((b) => {
                const remaining = remainingOf(b.amount, b.paid_amount)
                const interest = b.interest ?? 0
                const grace = graceOf(b.platform_id)
                // 容时生效：平台自动生效（如邮储，免申请）或该笔账单已勾选申请
                const graceOn = grace.days > 0 && (grace.auto || !!b.grace_applied)
                return (
                  <TableRow key={b.id}>
                    <TableCell className="font-medium">{platformName(b.platform_id)}</TableCell>
                    <TableCell>{b.bill_month.slice(0, 7)}</TableCell>
                    <TableCell className="whitespace-nowrap text-muted-foreground">
                      {b.due_date ?? '—'}
                      {graceOn && (
                        <Tip label={`${grace.auto ? '自动容时' : '已申请容时'} ${grace.days} 天 · 最终还款日 ${graceDeadlineText(b.platform_id, b.due_date)}`}>
                          <Badge variant="outline" className="ml-1.5 border-decor-indigo/40 text-decor-indigo">{grace.auto ? `自动容时 ${grace.days} 天` : `容时 +${grace.days}`}</Badge>
                        </Tip>
                      )}
                    </TableCell>
                    <TableCell className="whitespace-nowrap tabular-nums">
                      <span className="font-medium">{fmt(b.amount)}</span>
                      {interest > 0 && (
                        <>
                          <span className="mx-1.5 text-muted-foreground/40">|</span>
                          <span className="text-warning">{fmt(interest)}</span>
                        </>
                      )}
                    </TableCell>
                    <TableCell className="whitespace-nowrap tabular-nums">
                      <span className="font-medium">{fmt(b.paid_amount)}</span>
                      <span className="mx-1.5 text-muted-foreground/40">|</span>
                      <span className={remaining > 0 ? 'text-danger' : 'text-success'}>{fmt(remaining)}</span>
                    </TableCell>
                    <TableCell><Badge className={billStatusMeta[b.status]?.className}>{billStatusMeta[b.status]?.label ?? b.status}</Badge></TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1">
                        <Tip label="查看还款记录"><Button variant="ghost" size="icon" onClick={() => { loadRepayments(b.id); setRepayViewDialog(b.id) }}><ListTree className="size-3.5" /></Button></Tip>
                        {/* 无剩余欠款时不显示还款按钮，但保留等宽占位，避免各列图标纵向错位 */}
                        {remaining > 0 ? (
                          <Tip label="还款"><Button variant="ghost" size="icon" onClick={() => openRepay(b)}><Banknote className="size-3.5" /></Button></Tip>
                        ) : (
                          <Button variant="ghost" size="icon" className="invisible" aria-hidden tabIndex={-1}><Banknote className="size-3.5" /></Button>
                        )}
                        <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setBillForm({ platform_id: b.platform_id ? String(b.platform_id) : '', bill_month: b.bill_month, due_date: b.due_date ?? '', amount: String(b.amount), interest: String(b.interest ?? 0), paid_amount: String(b.paid_amount), status: b.status, grace_applied: b.grace_applied ? '1' : '0', note: b.note ?? '' }); setBillDialog({ editing: b }) }}><Pencil /></Button></Tip>
                        <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeBill(b)}><Trash2 /></Button></Tip>
                      </div>
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* 还款记录 */}
      {(billStats?.upcoming ?? []).length > 0 && (
        <Card className="border-warning/40 bg-warning-muted">
          <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-warning-muted-foreground">近期待还（30 天内）</CardTitle></CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            {billStats?.upcoming.map((u) => (
              <div key={u.id} className={`flex flex-wrap items-center justify-between rounded-md px-3 py-1.5 ${u.overdue ? 'bg-danger-muted border border-danger/40' : 'bg-white/70 dark:bg-white/5'}`}>
                <span>{platformName(u.platform_id)} · {u.due_date} <Badge variant="outline">{billStatusMeta[u.status]?.label}</Badge>
                  {(() => {
                    const g = graceOf(u.platform_id)
                    const on = g.days > 0 && (g.auto || !!u.grace_applied)
                    if (!on) return null
                    return (
                      <Tip label={`最终还款日 ${graceDeadlineText(u.platform_id, u.due_date)}`}>
                        <Badge variant="outline" className="ml-1 border-decor-indigo/40 text-decor-indigo">{g.auto ? `自动容时 ${g.days} 天` : `容时 +${g.days}`}</Badge>
                      </Tip>
                    )
                  })()}
                </span>
                <span className="text-muted-foreground">
                  {u.overdue ? <span className="text-danger font-semibold">已逾期 · </span> : ''}
                  到期 {u.due_date ?? '—'} · 剩余 <span className="font-medium text-danger-muted-foreground">{fmt(u.remaining)}</span>
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* 还款记录查看弹窗 */}
      <Dialog open={repayViewDialog !== null} onOpenChange={(o) => !o && setRepayViewDialog(null)}>
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>还款记录</DialogTitle>
            <DialogDescription>
              {repayViewDialog ? `${platformName(bills.find((b) => b.id === repayViewDialog)?.platform_id)} · ${bills.find((b) => b.id === repayViewDialog)?.bill_month ?? ''}` : ''}
            </DialogDescription>
          </DialogHeader>
          {/* 记录较多时内部滚动，避免弹窗超出屏幕；表头固定不被滚走 */}
          <div className="max-h-[60vh] overflow-y-auto rounded-md border">
            <Table>
              <TableHeader className="sticky top-0 z-10 bg-background">
                <TableRow>
                  <TableHead>还款日期</TableHead><TableHead className="text-right">实付</TableHead><TableHead className="text-right">优惠</TableHead><TableHead>方式</TableHead><TableHead>备注</TableHead><TableHead className="w-20 text-right">操作</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {repayments.length === 0 ? (
                  <TableRow><TableCell colSpan={6} className="h-16 text-center text-muted-foreground">该账单暂无还款记录</TableCell></TableRow>
                ) : repayments.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell>{r.repay_date}</TableCell>
                    <TableCell className="text-right font-medium">{fmt(r.amount)}</TableCell>
                    <TableCell className="text-right text-success">{r.discount && r.discount > 0 ? `-${fmt(r.discount)}` : '—'}</TableCell>
                    <TableCell>{r.method ?? '—'}</TableCell>
                    <TableCell className="text-muted-foreground">{r.note ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Tip label="修改"><Button variant="ghost" size="icon" onClick={() => openEditRepay(r)}><Pencil className="size-3.5" /></Button></Tip>
                        <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeRepay(r)}><Trash2 className="size-3.5" /></Button></Tip>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </DialogContent>
      </Dialog>

      {/* 还款记录编辑弹窗 */}
      <Dialog open={repayEditDialog !== null} onOpenChange={(o) => !o && setRepayEditDialog(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>修改还款记录</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="space-y-2"><Label>还款日期</Label><Input type="date" value={repayEditForm.repay_date ?? ''} onChange={(e) => setRepayEditForm({ ...repayEditForm, repay_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>实付金额</Label><Input type="number" min={0} step="0.01" value={repayEditForm.amount ?? ''} onChange={(e) => setRepayEditForm({ ...repayEditForm, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>优惠</Label><Input type="number" min={0} step="0.01" value={repayEditForm.discount ?? ''} onChange={(e) => setRepayEditForm({ ...repayEditForm, discount: e.target.value })} /></div>
            <div className="space-y-2"><Label>还款方式</Label><Input value={repayEditForm.method ?? ''} onChange={(e) => setRepayEditForm({ ...repayEditForm, method: e.target.value })} placeholder="如：支付宝、微信" /></div>
            <div className="space-y-2"><Label>备注</Label><Input value={repayEditForm.note ?? ''} onChange={(e) => setRepayEditForm({ ...repayEditForm, note: e.target.value })} /></div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setRepayEditDialog(null)}>取消</Button>
              <Button onClick={submitEditRepay} disabled={saving}>{saving ? <><Loader2 className="mr-1 size-4 animate-spin" />保存中</> : '保存修改'}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* 新增平台弹窗 */}
      <Dialog open={pfAddDialog} onOpenChange={setPfAddDialog}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>新增借款平台</DialogTitle><DialogDescription>添加借款平台并设置账单日、还款日与额度。</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <div className="space-y-2"><Label>平台名称 <span className="text-destructive">*</span></Label><Input value={newPf.name ?? ''} onChange={(e) => setNewPf({ ...newPf, name: e.target.value })} placeholder="平台名称" /></div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2"><Label>账单日(1-31)</Label><Input type="number" min={1} max={31} value={newPf.bill_day ?? ''} onChange={(e) => setNewPf({ ...newPf, bill_day: e.target.value })} placeholder="如 15" /></div>
              <div className="space-y-2"><Label>还款日(1-31)</Label><Input type="number" min={1} max={31} value={newPf.due_day ?? ''} onChange={(e) => setNewPf({ ...newPf, due_day: e.target.value })} placeholder="如 25" /></div>
            </div>
            <div className="space-y-2"><Label>额度</Label><Input type="number" min={0} step="0.01" value={newPf.credit_limit ?? ''} onChange={(e) => setNewPf({ ...newPf, credit_limit: e.target.value })} placeholder="可选" /></div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label className="flex items-center gap-1">容时天数<Hint text="最终还款日可顺延的天数（0 表示不提供容时）。邮储为 4 天。" /></Label>
                <Input type="number" min={0} max={15} value={newPf.grace_days ?? '3'} onChange={(e) => setNewPf({ ...newPf, grace_days: e.target.value })} placeholder="默认 3" />
              </div>
              <div className="space-y-2">
                <Label className="flex items-center gap-1">截止时刻<Hint text="顺延后当天的最晚截止时刻（0-23），0 表示当天 23:59；邮储为 17 点。" /></Label>
                <Input type="number" min={0} max={23} value={newPf.grace_hour ?? '0'} onChange={(e) => setNewPf({ ...newPf, grace_hour: e.target.value })} placeholder="0 = 当天结束" />
              </div>
            </div>
            <div className="flex items-center justify-between rounded-md border px-3 py-2">
              <span className="flex items-center gap-1 text-sm">容时自动生效<Hint text="勾选后无需逐笔申请，到期自动顺延（如邮储）；不勾选则需在每笔账单上手动申请。" /></span>
              <Switch checked={newPf.grace_auto === '1'} onCheckedChange={(v) => setNewPf({ ...newPf, grace_auto: v ? '1' : '0' })} />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">违约金日费率（%/天）<Hint text="超过最终还款日后，按「剩余欠款 × 日费率 × 逾期天数」估算违约金，仅作预警展示、不改账务。0 表示不计收。" /></Label>
              <Input type="number" min={0} max={5} step="0.01" value={newPf.penalty_rate ?? ''} onChange={(e) => setNewPf({ ...newPf, penalty_rate: e.target.value })} placeholder="如 0.05" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPfAddDialog(false)}>取消</Button>
            <Button onClick={addPlatform} disabled={saving}>{saving && <Loader2 className="animate-spin" />}确认添加</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 账单新增/编辑弹窗 */}
      <Dialog open={billDialog !== null} onOpenChange={(o) => !o && setBillDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>{billDialog?.editing ? '编辑账单' : '新增账单'}</DialogTitle><DialogDescription>填写应交欠款总额，若有差异可单列利息用于展示。</DialogDescription></DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>平台 <span className="text-destructive">*</span></Label>
              <Select value={billForm.platform_id} onValueChange={(v) => setBillForm({ ...billForm, platform_id: v, due_date: dueFor(v, billForm.bill_month) })}>
                <SelectTrigger><SelectValue placeholder="选择平台" /></SelectTrigger>
                <SelectContent>{platforms.map((p) => <SelectItem key={p.id} value={String(p.id)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>账单月份 <span className="text-destructive">*</span></Label><MonthPicker value={billForm.bill_month} onChange={(v) => setBillForm({ ...billForm, bill_month: v, due_date: dueFor(billForm.platform_id, v) })} /></div>
            <div className="space-y-2"><Label>到期日 <span className="text-muted-foreground">(按平台还款日自动算)</span></Label><DatePicker value={billForm.due_date} onChange={(v) => setBillForm({ ...billForm, due_date: v })} /></div>
            <div className="space-y-2"><Label>应付欠款(含利息) <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={billForm.amount} onChange={(e) => setBillForm({ ...billForm, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>其中利息</Label><Input type="number" min={0} step="0.01" value={billForm.interest} onChange={(e) => setBillForm({ ...billForm, interest: e.target.value })} placeholder="无则为 0" /></div>
            <div className="space-y-2"><Label>状态</Label>
              <Select value={billForm.status} onValueChange={(v) => setBillForm({ ...billForm, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="pending">待还</SelectItem><SelectItem value="partial">部分已还</SelectItem><SelectItem value="cleared">已结清</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="col-span-2 flex items-center justify-between rounded-md border border-border px-3 py-2">
              <Label htmlFor="grace-applied" className="flex cursor-pointer items-center gap-1">
                已申请容时服务<Hint text="容时服务固定 3 天，需按账单周期单独申请。勾选表示本笔已申请，最终还款日 = 还款日 + 3 天；系统逾期宽限期仍统一按 3 天计算" />
              </Label>
              <Switch id="grace-applied" checked={billForm.grace_applied === '1'} onCheckedChange={(v) => setBillForm({ ...billForm, grace_applied: v ? '1' : '0' })} />
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={billForm.note} onChange={(e) => setBillForm({ ...billForm, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBillDialog(null)}>取消</Button>
            <Button onClick={saveBill} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 还款弹窗 */}
      <Dialog open={repayDialog !== null} onOpenChange={(o) => !o && setRepayDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{repayDialog && repayDialog.amount - repayDialog.paid_amount > 0.001 && repayForm.amount ? (Number(repayForm.amount) >= repayDialog.amount - repayDialog.paid_amount - 0.001 ? '一次结清' : '部分还款') : '还款'}</DialogTitle>
            <DialogDescription>
              {repayDialog ? `${platformName(repayDialog.platform_id)} · ${repayDialog.bill_month} · 剩余 ${fmt(remainingOf(repayDialog.amount, repayDialog.paid_amount))}` : ''}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>还款日期 <span className="text-destructive">*</span></Label><DatePicker value={repayForm.repay_date} onChange={(v) => setRepayForm({ ...repayForm, repay_date: v })} /></div>
            <div className="space-y-2">
              <Label>应还金额 <span className="text-destructive">*</span></Label>
              <Input type="number" min={0.01} step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} placeholder="含优惠的欠款部分" />
            </div>
            <div className="space-y-2"><Label>优惠(券/抵扣)</Label><Input type="number" min={0} step="0.01" value={repayForm.discount} onChange={(e) => setRepayForm({ ...repayForm, discount: e.target.value })} placeholder="0" /></div>
            <div className="space-y-2"><Label>还款方式</Label><Input value={repayForm.method} onChange={(e) => setRepayForm({ ...repayForm, method: e.target.value })} placeholder="银行卡/支付宝等" /></div>
            <div className="col-span-2 space-y-1">
              <Label>实际支付（= 应还 - 优惠）</Label>
              <div className="rounded-lg border px-3 py-2 text-sm font-medium">
                {fmt(actualPay())}
                {(Number(repayForm.discount) || 0) > 0 && (
                  <span className="ml-2 text-xs text-success">优惠抵减 {fmt(Number(repayForm.discount))}</span>
                )}
              </div>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={repayForm.note} onChange={(e) => setRepayForm({ ...repayForm, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRepayDialog(null)}>取消</Button>
            <Button onClick={submitRepay} disabled={saving}>{saving && <Loader2 className="animate-spin" />}确认还款</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 平台编辑弹窗 */}
      <Dialog open={pfEdit !== null} onOpenChange={(o) => !o && setPfEdit(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader><DialogTitle>编辑借款平台</DialogTitle><DialogDescription>修改平台名称、账单日与还款日。</DialogDescription></DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2"><Label>平台名称</Label><Input value={pfEditForm.name} onChange={(e) => setPfEditForm({ ...pfEditForm, name: e.target.value })} /></div>
            <div className="space-y-2"><Label>账单日(1-31)</Label><Input type="number" min={1} max={31} value={pfEditForm.bill_day} onChange={(e) => setPfEditForm({ ...pfEditForm, bill_day: e.target.value })} /></div>
            <div className="space-y-2"><Label>还款日(1-31)</Label><Input type="number" min={1} max={31} value={pfEditForm.due_day} onChange={(e) => setPfEditForm({ ...pfEditForm, due_day: e.target.value })} /></div>
            <div className="col-span-2 space-y-2"><Label>额度</Label><Input type="number" min={0} step="0.01" value={pfEditForm.credit_limit} onChange={(e) => setPfEditForm({ ...pfEditForm, credit_limit: e.target.value })} /></div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">容时天数<Hint text="最终还款日可顺延的天数（0 表示不提供容时）。邮储为 4 天。" /></Label>
              <Input type="number" min={0} max={15} value={pfEditForm.grace_days} onChange={(e) => setPfEditForm({ ...pfEditForm, grace_days: e.target.value })} />
            </div>
            <div className="space-y-2">
              <Label className="flex items-center gap-1">截止时刻<Hint text="顺延后当天的最晚截止时刻（0-23），0 表示当天 23:59；邮储为 17 点。" /></Label>
              <Input type="number" min={0} max={23} value={pfEditForm.grace_hour} onChange={(e) => setPfEditForm({ ...pfEditForm, grace_hour: e.target.value })} />
            </div>
            <div className="col-span-2 flex items-center justify-between rounded-md border px-3 py-2">
              <span className="flex items-center gap-1 text-sm">容时自动生效<Hint text="勾选后无需逐笔申请，到期自动顺延（如邮储）；不勾选则需在每笔账单上手动申请。" /></span>
              <Switch checked={pfEditForm.grace_auto === '1'} onCheckedChange={(v) => setPfEditForm({ ...pfEditForm, grace_auto: v ? '1' : '0' })} />
            </div>
            <div className="col-span-2 space-y-2">
              <Label className="flex items-center gap-1">违约金日费率（%/天）<Hint text="超过最终还款日后，按「剩余欠款 × 日费率 × 逾期天数」估算违约金，仅作预警展示、不改账务。0 表示不计收。" /></Label>
              <Input type="number" min={0} max={5} step="0.01" value={pfEditForm.penalty_rate} onChange={(e) => setPfEditForm({ ...pfEditForm, penalty_rate: e.target.value })} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPfEdit(null)}>取消</Button>
            <Button onClick={savePfEdit} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 容时最后机会弹窗：琥珀色警示（区别于逾期的红色警报），强调最低还款且不可再次延期 */}
      <Dialog open={graceAlertOpen} onOpenChange={setGraceAlertOpen}>
        <DialogContent className="sm:max-w-lg" showCloseButton={false}>
          <DialogHeader className="space-y-1">
            <DialogTitle className="flex items-center gap-2 text-xl font-extrabold text-warning">
              <Clock className="size-6 animate-pulse" /> 容时最后机会
            </DialogTitle>
            <DialogDescription className="text-sm font-medium text-warning-muted-foreground">
              以下 {graceBills.length} 笔账单已过原还款日，仍在容时保护期内。
            </DialogDescription>
          </DialogHeader>

          {/* 核心警告：最低还款 + 不可再次延期 */}
          <div className="rounded-lg border-2 border-warning bg-warning-muted p-4 border-warning/40 bg-warning-muted">
            <p className="flex flex-wrap items-center gap-2">
              <ShieldAlert className="size-5 shrink-0 text-warning" />
              <span className="text-base font-extrabold text-foreground">
                请至少还够<span className="text-warning-muted-foreground">最低还款额</span>
              </span>
              <span className="rounded-md bg-warning px-1.5 py-0.5 text-xs font-bold text-white">不会再次延期</span>
            </p>
            <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
              容时只有这一次，不叠加、不可二次顺延；还够最低还款额可暂不视为逾期，剩余欠款仍需尽快结清，
              超过最终截止时刻将上报征信。容时期间不计违约金，逾期后按平台日费率为你估算。
            </p>
          </div>

          <div className="max-h-80 space-y-3 overflow-y-auto pr-1">
            {graceBills.map((b) => (
              <div key={b.id} className="rounded-xl border-2 border-warning/80 bg-gradient-to-br from-warning-muted/90 to-background p-4 border-warning/40 from-warning-muted">
                {/* 头部：平台 + 账单月份 + 容时标记 */}
                <div className="flex items-center gap-2">
                  <span className="truncate text-sm font-bold text-foreground">{platformName(b.platform_id)}</span>
                  <span className="shrink-0 text-xs font-medium text-muted-foreground">{b.bill_month.slice(0, 7)}</span>
                  <span className="ml-auto shrink-0 rounded-full bg-warning px-2 py-0.5 text-[11px] font-bold tracking-wide text-white">容时中</span>
                </div>
                {/* 两个核心数据：剩余时间（强调色）/ 待还金额（大粗体） */}
                <div className="mt-3 grid grid-cols-2 gap-4">
                  <div className="min-w-0">
                    <p className="text-[11px] font-bold tracking-widest text-warning-muted-foreground/70">剩余时间</p>
                    <p className="mt-1 text-xl font-extrabold leading-none tabular-nums text-warning sm:text-2xl text-warning">
                      {graceRemainValue(b.platform_id, b.due_date)}
                    </p>
                  </div>
                  <div className="min-w-0 border-l border-warning/70 pl-4 border-warning/30">
                    <p className="text-[11px] font-bold tracking-widest text-muted-foreground">待还金额</p>
                    <p className="mt-1 text-xl font-extrabold leading-none tabular-nums text-foreground sm:text-2xl">
                      {fmt(remainingOf(b.amount, b.paid_amount))}
                    </p>
                  </div>
                </div>
                {/* 时间轴：原还款日 → 最终还款日 */}
                <div className="mt-3 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 border-t border-warning/60 pt-2.5 text-xs border-warning/25">
                  <span className="text-muted-foreground">原还款日 {b.due_date}</span>
                  <span className="font-bold text-warning-muted-foreground">
                    最终 {graceDeadlineText(b.platform_id, b.due_date)} · 超过即上报征信
                  </span>
                </div>
              </div>
            ))}
          </div>

          <DialogFooter>
            <Button
              className="h-11 w-full bg-warning text-base font-bold text-white hover:bg-warning"
              onClick={() => setGraceAlertOpen(false)}
            >
              我知道了，尽快还款
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 逾期重大提醒弹窗：大字 + 强调色，仅通过「我已知晓」关闭 */}
      <Dialog open={overdueAlertOpen} onOpenChange={setOverdueAlertOpen}>
        <DialogContent className="sm:max-w-xl" showCloseButton={false}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-2xl font-extrabold text-danger">
              <AlertTriangle className="size-7 animate-pulse" /> 账单逾期警报
            </DialogTitle>
            <DialogDescription className="text-base text-danger">
              以下账单已超过最终还款日（含容时），请立即处理，避免影响征信。
            </DialogDescription>
          </DialogHeader>
          {/* 容时规则：各平台天数/截止时刻不同，已超时的账单将上报征信 */}
          <div className="rounded-lg border-2 border-danger bg-danger-muted px-4 py-3 border-danger/40 bg-danger-muted">
            <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-lg">
              <ShieldAlert className="size-5 shrink-0 text-danger" />
              <span className="font-bold text-foreground">已超过最终还款日</span>
              <span className="font-extrabold text-danger">将上报征信</span>
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              容时天数与截止时刻按平台配置（如邮储 4 天、至第 4 天 17:00 且自动生效；其余平台 3 天、需申请），每笔账单以其「最终还款日」为准。
              <span className="font-bold text-danger">容时已用完，不存在再次延期。</span>
            </p>
          </div>
          <div className="max-h-80 space-y-2 overflow-y-auto pr-1">
            {overdueBills.map((b) => (
              <div key={b.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border-2 border-danger bg-muted/50 px-4 py-3">
                <div className="min-w-0">
                  <p className="flex flex-wrap items-center gap-2 text-lg font-bold text-foreground">
                    {platformName(b.platform_id)} · {b.bill_month.slice(0, 7)}
                    {(() => {
                      const g = graceOf(b.platform_id)
                      if (!(g.days > 0 && (g.auto || !!b.grace_applied))) return null
                      return (
                        <span className="rounded-md border border-decor-indigo/50 px-2 py-0.5 text-sm font-semibold text-decor-indigo">
                          {g.auto ? `自动容时 ${g.days} 天` : '已申请容时'}
                        </span>
                      )
                    })()}
                    <span className="rounded-md bg-danger px-2 py-0.5 text-sm font-extrabold text-white">已超容时 · 将上报征信</span>
                  </p>
                  <p className="text-sm font-medium text-muted-foreground">
                    还款日 {b.due_date} · 最终还款日 <span className="font-bold text-foreground">{graceDeadlineText(b.platform_id, b.due_date)}</span> · 已逾期 <span className="text-xl font-extrabold text-warning">{overdueDays(b.due_date)}</span> 天
                  </p>
                  {(() => {
                    const pe = penaltyEstimate(b)
                    if (!pe.rate) return <p className="mt-0.5 text-xs text-muted-foreground">该平台未设置违约金</p>
                    return (
                      <p className="mt-0.5 text-sm font-semibold text-danger">
                        预计违约金 <span className="text-base font-extrabold">{fmt(pe.amount)}</span>
                        <span className="ml-1 text-xs font-normal text-muted-foreground">（日费率 {pe.rate}% × {pe.days} 天，仅供参考）</span>
                      </p>
                    )
                  })()}
                </div>
                <div className="shrink-0 text-right">
                  <p className="text-2xl font-extrabold text-warning">{fmt(remainingOf(b.amount, b.paid_amount))}</p>
                  <p className="text-xs font-medium text-muted-foreground">待还金额</p>
                </div>
              </div>
            ))}
          </div>
          <DialogFooter>
            <Button variant="destructive" className="w-full text-base font-bold" onClick={() => setOverdueAlertOpen(false)}>我已知晓</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}
