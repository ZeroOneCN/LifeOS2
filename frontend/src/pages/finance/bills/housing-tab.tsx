import { useEffect, useMemo, useState } from 'react'
import {
  Building,
  ChevronLeft,
  ChevronRight,
  Home,
  Layers,
  ListTree,
  Loader2,
  Pencil,
  Plus,
  Trash2,
  Wallet,
} from 'lucide-react'

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
import { Tip } from '@/components/ui/tip'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { toast } from 'sonner'

import { fmt } from './shared'
import { StatCard } from './stat-card'

/* ---------------- 房租水电 ---------------- */

type Housing = {
  id: number
  name: string
  short_name?: string
  channel?: string
  orientation?: string
  move_in_date: string
  move_out_date?: string
  rent_term: 'monthly' | 'quarterly' | 'one_time'
  actual_monthly_rent: number
  deposit?: number
  deposit_refunded?: number
  deposit_refund_channel?: string
  agent_fee?: number
  clean_fee?: number
  service_fee?: number
  laundry_fee?: number
  note?: string
}

type HousingStat = Housing & { overlap_days: number; single_day_cost: number; monthly_contribution: number }
type HousingStats = {
  month: string
  combined_monthly_rent: number
  total_deposit: number
  total_fees: number
  house_count: number
  houses: HousingStat[]
}

type Utility = {
  id: number
  housing_id?: number
  bill_month: string
  fee_type: string
  amount: number
  due_date?: string
  paid: boolean
  note?: string
}

type RentChannel = { id: number; name: string }
type RentTerm = { id: number; housing_id?: number; term_no: number; amount: number; due_date?: string; paid: boolean }

const feeTypes = ['水费', '电费', '燃气费', '宽带', '物业', '其他']

export function HousingTab() {
  const realtimeTick = useRealtime(30_000)
  const [houses, setHouses] = useState<Housing[]>([])
  const [stats, setStats] = useState<HousingStats | null>(null)
  const [utilities, setUtilities] = useState<Utility[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Housing }>(null)
  const [uDialog, setUDialog] = useState<null | { editing?: Utility }>(null)
  const [uGroup, setUGroup] = useState<null | { housing_id?: number; bill_month: string; ids: number[] }>(null)
  const [viewH, setViewH] = useState<null | Housing>(null)
  const [housePage, setHousePage] = useState(1)
  const [utilityPage, setUtilityPage] = useState(1)
  const [form, setForm] = useState<Record<string, string>>({})
  const [channels, setChannels] = useState<RentChannel[]>([])
  const [channelDialog, setChannelDialog] = useState(false)
  const [newChannel, setNewChannel] = useState('')
  const [channelEdit, setChannelEdit] = useState<RentChannel | null>(null)
  const [channelEditForm, setChannelEditForm] = useState('')
  const [termsByHouse, setTermsByHouse] = useState<Record<number, RentTerm[]>>({})
  const [termDialog, setTermDialog] = useState<null | { housing_id: number }>(null)
  const [termForm, setTermForm] = useState<{ amount: string; due_date: string; paid: boolean }>({ amount: '', due_date: new Date().toISOString().slice(0, 10), paid: true })
  const [saving, setSaving] = useState(false)
  const [utilityForm, setUtilityForm] = useState<Record<string, string>>({})
  const [dialogTab, setDialogTab] = useState<'basic' | 'terms' | 'utility' | 'deposit'>('basic')
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const loadHouses = async () => {
    const res = await api.list<Housing>('/finance/housing', { page_size: 100 })
    setHouses(res.items)
    return res.items
  }
  const loadStats = async () => {
    try { setStats(await api.query<HousingStats>('/finance/housing/stats')) }
    catch { setStats(null) }
  }
  const loadUtilities = async () => {
    const res = await api.list<Utility>('/finance/utilities', { page_size: 100 })
    setUtilities(res.items)
  }
  const loadChannels = async () => {
    api.list<RentChannel>('/finance/rent-channels', { page_size: 100 }).then((res) => setChannels(res.items)).catch(() => setChannels([]))
  }
  const loadTermsForHouse = async (id: number) => {
    try {
      const items = await api.query<RentTerm[]>('/finance/rent-terms?housing_id=' + id)
      setTermsByHouse((prev) => ({ ...prev, [id]: items }))
    } catch {
      // 忽略期次加载失败
    }
  }
  const addChannel = async () => {
    const name = newChannel.trim()
    if (!name) return
    try {
      await api.create('/finance/rent-channels', { name })
      setNewChannel('')
      await loadChannels()
      toast.success('租房渠道已添加')
    } catch (e) {
      toast.error('添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const removeChannel = async (c: RentChannel) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/rent-channels', c.id)
      await loadChannels()
      toast.success('租房渠道已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const saveChannelEdit = async () => {
    const name = channelEditForm.trim()
    if (!name || !channelEdit) return
    try {
      await api.update('/finance/rent-channels', channelEdit.id, { name })
      setChannelEdit(null)
      setChannelEditForm('')
      await loadChannels()
      toast.success('租房渠道已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const toggleTermPaid = async (term: RentTerm) => {
    try {
      await api.put(`/finance/rent-terms/${term.id}?paid=${!term.paid}`, {})
      setTermsByHouse((prev) => ({
        ...prev,
        [term.housing_id ?? 0]: (prev[term.housing_id ?? 0] ?? []).map((t) => (t.id === term.id ? { ...t, paid: !t.paid } : t)),
      }))
      toast.success('付款期次已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const patchTerm = (id: number, housingId: number, patch: Partial<RentTerm>) => {
    setTermsByHouse((prev) => ({
      ...prev,
      [housingId]: (prev[housingId] ?? []).map((t) => (t.id === id ? { ...t, ...patch } : t)),
    }))
  }
  const updateTermAmount = async (t: RentTerm, amount: number) => {
    try {
      await api.put(`/finance/rent-terms/${t.id}?amount=${amount}`, {})
      patchTerm(t.id, t.housing_id ?? 0, { amount })
      toast.success('金额已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const updateTermDueDate = async (t: RentTerm, due_date: string) => {
    try {
      await api.put(`/finance/rent-terms/${t.id}?due_date=${due_date}`, {})
      patchTerm(t.id, t.housing_id ?? 0, { due_date })
      toast.success('到期日已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const deleteTerm = async (t: RentTerm) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/rent-terms', t.id)
      setTermsByHouse((prev) => ({ ...prev, [t.housing_id ?? 0]: (prev[t.housing_id ?? 0] ?? []).filter((x) => x.id !== t.id) }))
      toast.success('期次已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const addTerm = async () => {
    if (!termDialog) return
    const amount = Number(termForm.amount)
    if (!amount || amount <= 0) {
      toast.error('请输入有效金额')
      return
    }
    try {
      const t = await api.create<RentTerm>('/finance/rent-terms', {
        housing_id: termDialog.housing_id,
        amount,
        due_date: termForm.due_date || null,
        paid: termForm.paid,
      })
      setTermsByHouse((prev) => ({
        ...prev,
        [termDialog.housing_id]: [...(prev[termDialog.housing_id] ?? []), t].sort((a, b) => a.term_no - b.term_no),
      }))
      setTermDialog(null)
      toast.success('期次已新增')
    } catch (e) {
      toast.error('新增失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  // 水电气账单按「住房 + 账单月」聚合成一行（电/水/气/合计）
  const utilityGroups = useMemo(() => {
    const map: Record<string, { key: string; housing_id?: number; bill_month: string; byType: Record<string, number>; due_date?: string; paid: boolean; ids: number[]; total: number }> = {}
    for (const u of utilities) {
      const k = `${u.housing_id ?? '-'}|${u.bill_month}`
      if (!map[k]) map[k] = { key: k, housing_id: u.housing_id, bill_month: u.bill_month, byType: {}, ids: [], total: 0, due_date: u.due_date, paid: u.paid }
      const g = map[k]
      g.byType[u.fee_type] = (g.byType[u.fee_type] || 0) + u.amount
      g.total += u.amount
      g.ids.push(u.id)
      if (u.due_date) g.due_date = u.due_date
      if (u.paid) g.paid = true
    }
    return Object.values(map).sort((a, b) => b.bill_month.localeCompare(a.bill_month))
  }, [utilities])
  // 水电气账单分页（最新在前）
  const UTIL_PAGE_SIZE = 10
  const utilTotalPages = Math.max(1, Math.ceil(utilityGroups.length / UTIL_PAGE_SIZE))
  const pagedUtilityGroups = utilityGroups.slice((utilityPage - 1) * UTIL_PAGE_SIZE, utilityPage * UTIL_PAGE_SIZE)

  // 住房清单卡片：按入住时间（最新在前）排序 + 每页 6 条分页
  const HOUSING_PAGE_SIZE = 6
  const sortedHouses = useMemo(() => {
    const list = [...(stats?.houses ?? [])]
    list.sort((a, b) => (b.move_in_date || '').localeCompare(a.move_in_date || ''))
    return list
  }, [stats])
  const houseTotalPages = Math.max(1, Math.ceil(sortedHouses.length / HOUSING_PAGE_SIZE))
  const pagedHouses = sortedHouses.slice((housePage - 1) * HOUSING_PAGE_SIZE, housePage * HOUSING_PAGE_SIZE)

  useEffect(() => {
    loadHouses().then((list) => { if (list.length) list.forEach((h) => loadTermsForHouse(h.id)) })
    loadStats()
    loadChannels()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [realtimeTick])
  useEffect(() => {
    loadUtilities()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [realtimeTick])

  useEffect(() => {
    if (housePage > houseTotalPages) setHousePage(houseTotalPages)
    if (housePage < 1) setHousePage(1)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [houseTotalPages])

  const houseName = (id?: number) => { const h = houses.find((x) => x.id === id); return h ? h.name : '—' }
  const houseShort = (id?: number) => { const h = houses.find((x) => x.id === id); return h ? (h.short_name || h.name) : '—' }

  // ========== 算法统一为「当月口径」（与后端 /finance/housing/stats 一致）==========
  // 整段居住周期天数（含首尾）：入住~退租
  const hDays = (h: Housing): number => {
    if (!h.move_in_date) return 0
    const a = new Date(h.move_in_date).getTime()
    const b = h.move_out_date ? new Date(h.move_out_date).getTime() : Date.now()
    if (b < a) return 0
    return Math.floor((b - a) / 86400000) + 1
  }
  // 居住天数 = 整段居住周期天数（用于住房清单展示）
  const houseDays = (h: Housing): number => hDays(h)
  // 当月居住天数 = 与 stats.month 同月区间内的居住天数
  const houseDaysInMonth = (h: Housing, mStart: Date, mEnd: Date): number => {
    if (!h.move_in_date) return 0
    const start = new Date(h.move_in_date) > mStart ? new Date(h.move_in_date) : mStart
    const outDate = h.move_out_date ? new Date(h.move_out_date) : new Date()
    const end = outDate < mEnd ? outDate : mEnd
    if (end < start) return 0
    return Math.floor((end.getTime() - start.getTime()) / 86400000) + 1
  }
  // 杂费（中介/保洁/洗衣；服务费已含在付款期次中）
  const houseFees = (h: Housing): number => (h.agent_fee || 0) + (h.clean_fee || 0) + (h.laundry_fee || 0)
  // 当月已交期次（按到期日落在当月且 paid 算）
  const houseTermsPaidInMonth = (h: Housing, mPrefix: string): number =>
    (termsByHouse[h.id] ?? []).filter((t) => t.paid && t.due_date && t.due_date.startsWith(mPrefix)).reduce((s, t) => s + t.amount, 0)
  // 当月已缴水电（按账单月）
  const houseUtilsPaidInMonth = (h: Housing, mPrefix: string): number =>
    utilities.filter((u) => u.housing_id === h.id && u.paid && u.bill_month.startsWith(mPrefix)).reduce((s, u) => s + u.amount, 0)
  // 当月已发生成本 = 当月已交期次 + 当月已缴水电 + 当月分摊杂费
  // 注：杂费仅一次性支出，按"是否在本月之前入住"判断全计入入住当月；这里为简化直接平均到所有月份
  const houseIncurredInMonth = (h: Housing, mPrefix: string): number => {
    return houseTermsPaidInMonth(h, mPrefix) + houseUtilsPaidInMonth(h, mPrefix)
  }

  const openCreate = () => {
    setForm({ name: '', short_name: '', channel: '', orientation: '', move_in_date: '', move_out_date: '', rent_term: 'monthly', actual_monthly_rent: '', deposit: '', deposit_refunded: '', deposit_refund_channel: '', agent_fee: '', clean_fee: '', service_fee: '', laundry_fee: '', note: '' })
    setDialogTab('basic')
    setDialog({})
  }
  const openEdit = (h: Housing) => {
    setForm({
      name: h.name, short_name: h.short_name ?? '', channel: h.channel ?? '', orientation: h.orientation ?? '',
      move_in_date: h.move_in_date, move_out_date: h.move_out_date ?? '',
      rent_term: h.rent_term, actual_monthly_rent: String(h.actual_monthly_rent),
      deposit: h.deposit != null ? String(h.deposit) : '', deposit_refunded: h.deposit_refunded != null ? String(h.deposit_refunded) : '', deposit_refund_channel: h.deposit_refund_channel ?? '',
      agent_fee: h.agent_fee != null ? String(h.agent_fee) : '', clean_fee: h.clean_fee != null ? String(h.clean_fee) : '',
      service_fee: h.service_fee != null ? String(h.service_fee) : '', laundry_fee: h.laundry_fee != null ? String(h.laundry_fee) : '', note: h.note ?? '',
    })
    setDialogTab('basic')
    setDialog({ editing: h })
  }
  const saveHousing = async () => {
    const num = (v?: string) => {
      if (v == null || v.trim() === '') return 0
      const n = Number(v)
      return Number.isFinite(n) ? n : 0
    }
    if (!form.name?.trim() || !form.move_in_date) {
      toast.error('保存失败', { description: '房屋名称与入住日期为必填项' })
      return
    }
    const payload = {
      name: form.name, short_name: form.short_name || null, channel: form.channel || null, orientation: form.orientation || null,
      move_in_date: form.move_in_date, move_out_date: form.move_out_date || null,
      rent_term: form.rent_term, actual_monthly_rent: num(form.actual_monthly_rent),
      deposit: num(form.deposit), deposit_refunded: num(form.deposit_refunded), deposit_refund_channel: form.deposit_refund_channel || null,
      agent_fee: num(form.agent_fee), clean_fee: num(form.clean_fee),
      service_fee: num(form.service_fee), laundry_fee: num(form.laundry_fee), note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/housing', dialog.editing.id, payload)
      else await api.create('/finance/housing', payload)
      setDialog(null)
      await loadHouses()
      await loadStats()
      toast.success(dialog?.editing ? '住房信息已更新' : '住房信息已添加')
    } catch (e) {
      toast.error(dialog?.editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const removeHousing = async (h: Housing) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/housing', h.id)
      await loadHouses()
      await loadStats()
      toast.success('住房信息已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openUCreate = () => {
    setUtilityForm({ housing_id: dialog?.editing ? String(dialog.editing.id) : '', bill_month: '', fee_type: '电费', amount: '', due_date: '', paid: 'true', note: '' })
    setUDialog({})
  }
  const openUEdit = (u: Utility) => {
    setUtilityForm({ housing_id: u.housing_id ? String(u.housing_id) : '', bill_month: u.bill_month, fee_type: u.fee_type, amount: String(u.amount), due_date: u.due_date ?? '', paid: u.paid ? 'true' : 'false', note: u.note ?? '' })
    setUDialog({ editing: u })
  }
  const saveUtility = async () => {
    const editingU = uDialog?.editing
    const amt = Number(utilityForm.amount)
    if (!utilityForm.bill_month) { toast.error('请选择账单月份'); return }
    if (!utilityForm.fee_type) { toast.error('请选择费用类型'); return }
    if (utilityForm.amount === '' || Number.isNaN(amt)) { toast.error('请填写金额'); return }
    const payload = {
      housing_id: utilityForm.housing_id ? Number(utilityForm.housing_id) : null,
      bill_month: utilityForm.bill_month, fee_type: utilityForm.fee_type, amount: amt,
      due_date: utilityForm.due_date || null, paid: utilityForm.paid === 'true', note: utilityForm.note || null,
    }
    setSaving(true)
    try {
      if (editingU) await api.update('/finance/utilities', editingU.id, payload)
      else await api.create('/finance/utilities', payload)
      setUDialog(null)
      await loadUtilities()
      toast.success(editingU ? '缴费记录已更新' : '缴费记录已添加')
    } catch (e) {
      toast.error(editingU ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const removeUtility = async (u: Utility) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/utilities', u.id)
      await loadUtilities()
      toast.success('缴费记录已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {stats && (
        <>
          {(() => {
            // 整段历史口径：与住房卡片主信息保持一致
            const totalDays = stats.houses.reduce((s, h) => s + houseDays(h), 0)
            // 整段总花费 = 全部已交期次 + 全部已缴水电 + 全部杂费
            const totalSpent = stats.houses.reduce((s, h) => {
              const tPaid = (termsByHouse[h.id] ?? []).filter((t) => t.paid).reduce((a, t) => a + t.amount, 0)
              const uPaid = utilities.filter((u) => u.housing_id === h.id && u.paid).reduce((a, u) => a + u.amount, 0)
              return s + tPaid + uPaid + houseFees(h)
            }, 0)
            const avgDaily = totalDays ? totalSpent / totalDays : 0
            const occupiedCount = stats.houses.filter((h) => !h.move_out_date).length
            return (
              <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <StatCard icon={Home} label="在住房数" value={`${occupiedCount} / ${stats.houses.length} 套`} hint={`累计居住 ${totalDays} 天`} className="text-indigo-500" />
                <StatCard icon={Wallet} label="总花费" value={fmt(totalSpent)} hint="已交期次+已缴水电+杂费" className="text-success" />
                <StatCard icon={Building} label="组合月租" value={fmt(stats.combined_monthly_rent)} hint="当月折算" className="text-info" />
                <StatCard icon={Wallet} label="平均单日成本" value={fmt(avgDaily)} hint={avgDaily > 0 ? `折算月租 ${fmt(avgDaily * 30)}` : '尚无数据'} className="text-danger" />
              </section>
            )
          })()}
          {sortedHouses.length > 0 && (
            <Card>
              <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
                <CardTitle className="text-sm font-medium min-w-0 max-w-[55%] truncate">住房清单</CardTitle>
                <CardHeaderActions className="text-xs text-muted-foreground">
                  <span>{sortedHouses.length} 套 · 第 {housePage}/{houseTotalPages} 页</span>
                  <Tip label="上一页"><Button variant="ghost" size="icon" className="h-6 w-6" disabled={housePage <= 1} onClick={() => setHousePage(housePage - 1)}><ChevronLeft className="size-4" /></Button></Tip>
                  <Tip label="下一页"><Button variant="ghost" size="icon" className="h-6 w-6" disabled={housePage >= houseTotalPages} onClick={() => setHousePage(housePage + 1)}><ChevronRight className="size-4" /></Button></Tip>
                </CardHeaderActions>
              </CardHeader>
              <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {pagedHouses.map((h) => {
                const days = houseDays(h)
                const termLabel = h.rent_term === 'quarterly' ? '按季付' : h.rent_term === 'one_time' ? '一次性' : '按月付'
                // 整段已发生成本 = 全部已交期次 + 全部已缴水电 + 杂费
                const allTermsPaid = (termsByHouse[h.id] ?? []).filter((t) => t.paid).reduce((s, t) => s + t.amount, 0)
                const allUtilsPaid = utilities.filter((u) => u.housing_id === h.id && u.paid).reduce((s, u) => s + u.amount, 0)
                const totalSpent = allTermsPaid + allUtilsPaid + houseFees(h)
                // 平均单日成本
                const daily = days && totalSpent > 0 ? totalSpent / days : 0
                return (
                  <div key={h.id} className="flex flex-col rounded-xl border bg-card p-4 text-sm transition-shadow hover:shadow-md">
                    {/* 头部：名称 + 状态 */}
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <div className="truncate font-semibold text-foreground">{h.short_name || h.name}</div>
                        <div className="truncate text-xs text-muted-foreground">{h.name}</div>
                      </div>
                      <Badge variant={h.move_out_date ? 'secondary' : 'default'} className="shrink-0">
                        {h.move_out_date ? '已退租' : '在住'}
                      </Badge>
                    </div>

                    {/* 主信息：整段总花费（大字） + 月租/居住周期（小字） */}
                    <div className="mt-3">
                      <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">总花费</p>
                      <p className="mt-1 text-2xl font-bold leading-none text-success">
                        {totalSpent > 0 ? fmt(totalSpent) : '—'}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">
                        月租 {fmt(h.actual_monthly_rent || 0)} · {termLabel} · {days} 天
                      </p>
                    </div>

                    {/* 平均单日成本 */}
                    <div className="mt-2 flex items-center justify-between rounded-md bg-info-muted px-2 py-1.5">
                      <span className="text-xs text-info-muted-foreground">平均单日</span>
                      <span className="text-sm font-semibold text-info-muted-foreground">{daily > 0 ? fmt(daily) : '—'}</span>
                    </div>

                    {/* 操作按钮 */}
                    <div className="mt-3 flex items-center justify-end gap-1">
                      <Button size="sm" variant="outline" className="h-7 px-2 text-xs" onClick={() => setViewH(h)}>查看明细</Button>
                      <Tip label="编辑"><Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => openEdit(h)}><Pencil className="size-3.5" /></Button></Tip>
                      <Tip label="删除"><Button size="icon" variant="ghost" className="h-7 w-7 text-destructive" onClick={() => removeHousing(h)}><Trash2 className="size-3.5" /></Button></Tip>
                    </div>
                  </div>
                )
              })}
              </CardContent>
            </Card>
          )}
        </>
      )}

      <div className="flex items-center justify-end gap-2">
        <Button size="sm" variant="outline" onClick={() => { setNewChannel(''); setChannelDialog(true) }}><Layers className="size-4" /> 渠道设置</Button>
        <Button size="sm" onClick={openCreate}><Plus /> 新增住房</Button>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
          <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">水电气账单</CardTitle>
          <CardHeaderActions>
            <Button size="sm" onClick={openUCreate}><Plus /> 新增账单</Button>
          </CardHeaderActions>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>账单月</TableHead><TableHead>住房</TableHead><TableHead>电费</TableHead><TableHead>水费</TableHead><TableHead>燃气费</TableHead><TableHead className="text-right">合计</TableHead><TableHead>状态</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {utilityGroups.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="h-16 text-center text-muted-foreground">暂无账单记录</TableCell></TableRow>
              ) : pagedUtilityGroups.map((g) => (
                <TableRow key={g.key}>
                  <TableCell>{g.bill_month.slice(0, 7)}</TableCell>
                  <Tip label={houseName(g.housing_id)}><TableCell className="max-w-[140px] truncate text-muted-foreground">{houseShort(g.housing_id)}</TableCell></Tip>
                  <TableCell>{g.byType['电费'] ? fmt(g.byType['电费']) : '—'}</TableCell>
                  <TableCell>{g.byType['水费'] ? fmt(g.byType['水费']) : '—'}</TableCell>
                  <TableCell>{g.byType['燃气费'] ? fmt(g.byType['燃气费']) : '—'}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(g.total)}</TableCell>
                  <TableCell>{g.paid ? <Badge className="bg-success-muted text-success-muted-foreground">已缴</Badge> : <Badge className="bg-warning-muted text-warning-muted-foreground">待缴</Badge>}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Tip label="明细/编辑"><Button variant="ghost" size="icon" onClick={() => setUGroup({ housing_id: g.housing_id, bill_month: g.bill_month, ids: g.ids })}><ListTree /></Button></Tip>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          {utilityGroups.length > UTIL_PAGE_SIZE && (
            <div className="border-t p-3">
              <PaginationBar page={utilityPage} totalPages={utilTotalPages} total={utilityGroups.length} onPageChange={setUtilityPage} />
            </div>
          )}
        </CardContent>
      </Card>

      {/* 住房弹窗 */}
      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑住房' : '新增住房'}</DialogTitle>
            <DialogDescription>记录租房渠道、押金、杂费与租期；期次与水电在各自子页即时维护。</DialogDescription>
          </DialogHeader>
          <div className="flex gap-1 rounded-lg bg-muted p-1">
            <Button size="sm" variant={dialogTab === 'basic' ? 'default' : 'ghost'} className="flex-1" onClick={() => setDialogTab('basic')}>基础信息</Button>
            <Button size="sm" variant={dialogTab === 'deposit' ? 'default' : 'ghost'} className="flex-1" onClick={() => setDialogTab('deposit')}>押金</Button>
            {dialog?.editing && (
              <>
                <Button size="sm" variant={dialogTab === 'terms' ? 'default' : 'ghost'} className="flex-1" onClick={() => setDialogTab('terms')}>付款期次</Button>
                <Button size="sm" variant={dialogTab === 'utility' ? 'default' : 'ghost'} className="flex-1" onClick={() => setDialogTab('utility')}>水电燃气</Button>
              </>
            )}
          </div>
          <div className="grid grid-cols-2 gap-4">
            {dialogTab === 'basic' && (
              <>
                <div className="space-y-2"><Label>房屋名称 <span className="text-destructive">*</span></Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="如 XX小区X栋X室" /></div>
                <div className="space-y-2"><Label>小区名（缩写）</Label><Input value={form.short_name} onChange={(e) => setForm({ ...form, short_name: e.target.value })} placeholder="如 珠江新城 / 三里屯" /></div>
                <div className="space-y-2"><Label>租房渠道</Label>
                  <Select value={form.channel} onValueChange={(v) => setForm({ ...form, channel: v })}>
                    <SelectTrigger><SelectValue placeholder="选择渠道" /></SelectTrigger>
                    <SelectContent>
                      {channels.length ? channels.map((c) => <SelectItem key={c.id} value={c.name}>{c.name}</SelectItem>) : <SelectItem value="其他">其他</SelectItem>}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2"><Label>房屋朝向</Label><Input value={form.orientation} onChange={(e) => setForm({ ...form, orientation: e.target.value })} placeholder="如 朝南 / 朝东" /></div>
                <div className="space-y-2"><Label>入住时间 <span className="text-destructive">*</span></Label><DatePicker value={form.move_in_date} onChange={(v) => setForm({ ...form, move_in_date: v })} /></div>
                <div className="col-span-2 space-y-2"><Label>退租时间</Label>
                  <Select value={form.move_out_date ? 'out' : 'in'} onValueChange={(v) => { if (v === 'in') setForm({ ...form, move_out_date: '' }); else setForm({ ...form, move_out_date: form.move_out_date || new Date().toISOString().slice(0, 10) }) }}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent><SelectItem value="in">在住（未退）</SelectItem><SelectItem value="out">已退租</SelectItem></SelectContent>
                  </Select>
                  {form.move_out_date && <DatePicker value={form.move_out_date} onChange={(v) => setForm({ ...form, move_out_date: v })} />}
                  {!form.move_out_date && <p className="text-xs text-muted-foreground">在住中，无需填写退租日期</p>}
                </div>
                <div className="space-y-2"><Label>缴纳方式</Label>
                  <Select value={form.rent_term} onValueChange={(v) => setForm({ ...form, rent_term: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent><SelectItem value="monthly">按月付</SelectItem><SelectItem value="quarterly">按季付</SelectItem><SelectItem value="one_time">一次性</SelectItem></SelectContent>
                  </Select>
                </div>
                <div className="space-y-2"><Label>实际月租 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.actual_monthly_rent} onChange={(e) => setForm({ ...form, actual_monthly_rent: e.target.value })} /></div>
                <div className="space-y-2"><Label>中介费</Label><Input type="number" min={0} step="0.01" value={form.agent_fee} onChange={(e) => setForm({ ...form, agent_fee: e.target.value })} /></div>
                <div className="space-y-2"><Label>保洁费</Label><Input type="number" min={0} step="0.01" value={form.clean_fee} onChange={(e) => setForm({ ...form, clean_fee: e.target.value })} /></div>
                <div className="space-y-2"><Label>服务费</Label><Input type="number" min={0} step="0.01" value={form.service_fee} onChange={(e) => setForm({ ...form, service_fee: e.target.value })} /></div>
                <div className="space-y-2"><Label>洗衣费</Label><Input type="number" min={0} step="0.01" value={form.laundry_fee} onChange={(e) => setForm({ ...form, laundry_fee: e.target.value })} /></div>
                <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
              </>
            )}
            {dialogTab === 'deposit' && (
              <>
                <div className="space-y-2"><Label>押金</Label><Input type="number" min={0} step="0.01" value={form.deposit} onChange={(e) => setForm({ ...form, deposit: e.target.value })} /></div>
                <div className="space-y-2"><Label>已退押金</Label><Input type="number" min={0} step="0.01" value={form.deposit_refunded} onChange={(e) => setForm({ ...form, deposit_refunded: e.target.value })} placeholder="退租已退/已扣，默认0" /></div>
                <div className="col-span-2 space-y-2"><Label>押金退还渠道</Label><Input value={form.deposit_refund_channel} onChange={(e) => setForm({ ...form, deposit_refund_channel: e.target.value })} placeholder="如 微信 / 银行 / 抵扣 / 扣押" /></div>
              </>
            )}
            {dialog?.editing && dialogTab === 'terms' && (() => {
              const editingId = dialog!.editing!.id
              const terms = termsByHouse[editingId] ?? []
              const paidCount = terms.filter((t) => t.paid).length
              const paidSum = terms.filter((t) => t.paid).reduce((s, t) => s + t.amount, 0)
              return (
                <div className="col-span-2 rounded-lg border p-3">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="text-sm font-medium">付款期次</span>
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs text-muted-foreground">已交 {paidCount}/{terms.length} 期 · 已交 {fmt(paidSum)}</span>
                      <Button size="sm" onClick={() => { setTermForm({ amount: '', due_date: new Date().toISOString().slice(0, 10), paid: true }); setTermDialog({ housing_id: editingId }) }}>新增期次</Button>
                    </div>
                  </div>
                  <div className="space-y-1.5">
                    {terms.length === 0 ? (
                      <p className="py-4 text-center text-sm text-muted-foreground">暂未录期次，点「新增期次」手动添加</p>
                    ) : terms.map((t) => (
                      <div key={t.id} className="flex items-center justify-between gap-2 rounded-md border px-2 py-1.5 text-sm">
                        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">
                          <span className="font-medium whitespace-nowrap">第 {t.term_no} 期</span>
                          <Input
                            type="number" min={0} step="0.01" defaultValue={t.amount}
                            className="h-7 w-24 text-right"
                            onBlur={(e) => { const v = Number(e.target.value); if (v !== t.amount) updateTermAmount(t, v) }}
                          />
                          <DatePicker value={t.due_date} onChange={(v) => updateTermDueDate(t, v)} className="h-7 w-32" />
                        </div>
                        <div className="flex shrink-0 items-center gap-2">
                          <span className={`text-xs ${t.paid ? 'text-success' : 'text-muted-foreground'}`}>{t.paid ? '已交' : '未交'}</span>
                          <Switch checked={t.paid} onCheckedChange={() => toggleTermPaid(t)} />
                          <Tip label="删除"><Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => deleteTerm(t)}><Trash2 className="size-4" /></Button></Tip>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )
            })()}
            {dialog?.editing && dialogTab === 'utility' && (() => {
              const editingId = dialog!.editing!.id
              const utils = utilities.filter((u) => u.housing_id === editingId)
                .slice().sort((a, b) => a.bill_month.localeCompare(b.bill_month))
              return (
                <div className="col-span-2 rounded-lg border p-3">
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-sm font-medium">水电燃气</span>
                    <Button size="sm" onClick={() => openUCreate()}><Plus /> 新增账单</Button>
                  </div>
                  {utils.length === 0 ? (
                    <p className="py-4 text-center text-sm text-muted-foreground">暂无账单记录，点「新增账单」添加</p>
                  ) : (
                    <div className="grid gap-2 sm:grid-cols-2">
                      {utils.map((u) => (
                        <div key={u.id} className="flex items-center justify-between gap-2 rounded-md border px-2 py-1.5 text-sm">
                          <div className="min-w-0">
                            <div className="truncate font-medium">{u.bill_month.slice(0, 7)} · {u.fee_type}</div>
                            <div className="mt-0.5 flex items-center gap-1.5">
                              <span className="font-medium">{fmt(u.amount)}</span>
                              {u.paid ? <Badge className="bg-success-muted text-success-muted-foreground">已缴</Badge> : <Badge className="bg-warning-muted text-warning-muted-foreground">待缴</Badge>}
                            </div>
                          </div>
                          <div className="flex shrink-0 items-center gap-1">
                            <Tip label="编辑"><Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => openUEdit(u)}><Pencil /></Button></Tip>
                            <Tip label="删除"><Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => removeUtility(u)}><Trash2 /></Button></Tip>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )
            })()}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>取消</Button>
            <Button onClick={saveHousing} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 住房查看弹窗 */}
      <Dialog open={viewH !== null} onOpenChange={(o) => !o && setViewH(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{viewH?.name}</DialogTitle>
            <DialogDescription>住房详细信息（含水电账单统计，只读）。</DialogDescription>
          </DialogHeader>
          {viewH && (() => {
            const inD = viewH.move_in_date ? new Date(viewH.move_in_date) : null
            const outD = viewH.move_out_date ? new Date(viewH.move_out_date) : (inD ? new Date() : null)
            const days = inD && outD && outD >= inD ? Math.floor((outD.getTime() - inD.getTime()) / 86400000) + 1 : 0
            const months = Math.max(1, Math.ceil(days / 30))
            const rent = viewH.actual_monthly_rent || 0
            const myUtils = utilities.filter((u) => u.housing_id === viewH.id)
              .slice().sort((a, b) => a.bill_month.localeCompare(b.bill_month))
            const utilTotal = myUtils.reduce((s, u) => s + u.amount, 0)
            const utilPaid = myUtils.filter((u) => u.paid).reduce((s, u) => s + u.amount, 0)
            // 整段历史已发生成本（仅供详情弹窗参考；卡片用当月口径）
            const allTermsPaid = (termsByHouse[viewH.id] ?? []).filter((t) => t.paid).reduce((s, t) => s + t.amount, 0)
            const allUtilsPaid = utilPaid
            const allFees = houseFees(viewH)
            const incurred = allTermsPaid + allUtilsPaid + allFees
            const daily = days ? incurred / days : 0
            const mPrefix = (stats?.month ?? new Date().toISOString().slice(0, 7)).slice(0, 7)
            const [yy, mm] = mPrefix.split('-').map(Number)
            const mStart = new Date(yy, (mm || 1) - 1, 1)
            const mEnd = new Date(yy, (mm || 1), 0)
            const daysInMonth = houseDaysInMonth(viewH, mStart, mEnd)
            const incurredMonth = houseIncurredInMonth(viewH, mPrefix)
            const rows: [string, string][] = [
              ['小区名', viewH.short_name || '—'],
              ['租房渠道', viewH.channel || '—'],
              ['房屋朝向', viewH.orientation || '—'],
              ['入住时间', viewH.move_in_date],
              ['退租时间', viewH.move_out_date || '—'],
              ['缴纳方式', viewH.rent_term === 'quarterly' ? '按季付' : viewH.rent_term === 'one_time' ? '一次性' : '按月付'],
              ['实际月租', fmt(rent)],
              ['押金', viewH.deposit ? fmt(viewH.deposit) : '—'],
              ['已退押金', viewH.deposit_refunded ? fmt(viewH.deposit_refunded) : '—'],
              ['未退押金', viewH.deposit ? fmt(Math.max(0, (viewH.deposit || 0) - (viewH.deposit_refunded || 0))) : '—'],
              ['退还渠道', viewH.deposit_refund_channel || '—'],
              ['中介费', viewH.agent_fee ? fmt(viewH.agent_fee) : '—'],
              ['保洁费', viewH.clean_fee ? fmt(viewH.clean_fee) : '—'],
              ['服务费', viewH.service_fee ? fmt(viewH.service_fee) : '—'],
              ['洗衣费', viewH.laundry_fee ? fmt(viewH.laundry_fee) : '—'],
              ['居住月数', `${months} 个月（${days} 天）`],
            ]
            const costRows: [string, string][] = [
              ['当月已发生成本', incurredMonth > 0 ? fmt(incurredMonth) : '—'],
              [`当月居住天数`, daysInMonth > 0 ? `${daysInMonth} 天` : '—'],
              ['整段已发生成本(含杂费)', incurred > 0 ? fmt(incurred) : '—'],
              ['整段平均单日成本', daily > 0 ? fmt(daily) : '—'],
              ['折算月租(单日×30)', daily > 0 ? fmt(daily * 30) : '—'],
            ]
            return (
              <>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                  {rows.map(([k, v]) => (
                    <div key={k} className="flex justify-between gap-2 border-b py-1">
                      <dt className="text-muted-foreground">{k}</dt>
                      <Tip label={v}><dd className="truncate text-right font-medium">{v}</dd></Tip>
                    </div>
                  ))}
                </dl>
                <div className="mt-3">
                  <div className="mb-1.5 text-sm font-medium">成本概览</div>
                  <dl className="gap-x-4 gap-y-1 text-sm">
                    {costRows.map(([k, v]) => (
                      <div key={k} className="flex justify-between gap-2 border-b py-1">
                        <dt className="text-muted-foreground">{k}</dt>
                        <Tip label={v}><dd className="truncate text-right font-medium">{v}</dd></Tip>
                      </div>
                    ))}
                  </dl>
                </div>
                {myUtils.length > 0 && (
                  <div className="mt-3">
                    <div className="mb-1.5 flex items-center justify-between">
                      <span className="text-sm font-medium">水电账单明细</span>
                      <span className="text-xs text-muted-foreground">已缴 {fmt(utilPaid)} / 待缴 {fmt(utilTotal - utilPaid)}</span>
                    </div>
                    <div className="grid gap-1.5 sm:grid-cols-2">
                      {myUtils.map((u) => (
                        <div key={u.id} className="flex items-center justify-between gap-2 rounded-lg border px-3 py-1.5 text-sm">
                          <Tip label={`${u.bill_month.slice(0, 7)} · ${u.fee_type} · ${fmt(u.amount)}`}><div className="min-w-0 truncate">
                            <span className="font-medium">{u.bill_month.slice(0, 7)} · {u.fee_type}</span>
                            <span className="ml-2 text-muted-foreground">{fmt(u.amount)}</span>
                          </div></Tip>
                          {u.paid ? <Badge className="shrink-0 bg-success-muted text-success-muted-foreground">已缴</Badge> : <Badge className="shrink-0 bg-warning-muted text-warning-muted-foreground">待缴</Badge>}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {(() => {
                  const terms = termsByHouse[viewH.id] ?? []
                  const paidCount = terms.filter((t) => t.paid).length
                  const paidSum = terms.filter((t) => t.paid).reduce((s, t) => s + t.amount, 0)
                  return (
                    <div className="mt-3">
                      <div className="mb-1.5 flex items-center justify-between">
                        <span className="text-sm font-medium">付款期次</span>
                        {terms.length > 0 && (
                          <span className="text-xs text-muted-foreground">已交 {paidCount}/{terms.length} 期 · 已交 {fmt(paidSum)}</span>
                        )}
                      </div>
                      <div className="space-y-1.5">
                        {terms.length === 0 ? (
                          <p className="py-3 text-center text-sm text-muted-foreground">暂无付款期次</p>
                        ) : terms.map((t) => (
                          <div key={t.id} className="flex items-center justify-between rounded-lg border px-3 py-1.5 text-sm">
                            <span className="font-medium whitespace-nowrap">第 {t.term_no} 期</span>
                            <div className="flex shrink-0 flex-wrap items-center justify-end gap-x-2 text-muted-foreground">
                              <span>{fmt(t.amount)}</span>
                              {t.due_date ? <span>到期 {t.due_date}</span> : null}
                              {t.paid ? <Badge className="bg-success-muted text-success-muted-foreground">已交</Badge> : <Badge className="bg-warning-muted text-warning-muted-foreground">未交</Badge>}
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )
                })()}
              </>
            )
          })()}
          <DialogFooter>
            {viewH && <Button variant="outline" onClick={() => { openEdit(viewH); setViewH(null) }}>编辑住房</Button>}
            <Button onClick={() => setViewH(null)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 账单弹窗 */}
      <Dialog open={uDialog !== null} onOpenChange={(o) => !o && setUDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{uDialog?.editing ? '编辑账单' : '新增账单'}</DialogTitle>
            <DialogDescription>记录水、电、燃气等费用。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>账单月份 <span className="text-destructive">*</span></Label><MonthPicker value={utilityForm.bill_month} onChange={(v) => setUtilityForm({ ...utilityForm, bill_month: v })} /></div>
            <div className="space-y-2"><Label>关联住房</Label>
              <Select value={utilityForm.housing_id} onValueChange={(v) => setUtilityForm({ ...utilityForm, housing_id: v })}>
                <SelectTrigger className="max-w-full truncate"><SelectValue placeholder="选择住房" /></SelectTrigger>
                <SelectContent>
                    <SelectItem value="">不关联</SelectItem>
                    {houses.map((h) => <SelectItem key={h.id} value={String(h.id)} className="text-xs truncate">{h.name}</SelectItem>)}
                  </SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>类型 <span className="text-destructive">*</span></Label>
              <Select value={utilityForm.fee_type} onValueChange={(v) => setUtilityForm({ ...utilityForm, fee_type: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{feeTypes.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>金额 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={utilityForm.amount} onChange={(e) => setUtilityForm({ ...utilityForm, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>到期日</Label><DatePicker value={utilityForm.due_date} onChange={(v) => setUtilityForm({ ...utilityForm, due_date: v })} /></div>
            <div className="space-y-2"><Label>状态</Label>
              <Select value={utilityForm.paid} onValueChange={(v) => setUtilityForm({ ...utilityForm, paid: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="false">待缴</SelectItem><SelectItem value="true">已缴</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={utilityForm.note} onChange={(e) => setUtilityForm({ ...utilityForm, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUDialog(null)}>取消</Button>
            <Button onClick={saveUtility} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 水电气账单明细弹窗（支持单条修改/删除，避免数据错误） */}
      <Dialog open={uGroup !== null} onOpenChange={(o) => !o && setUGroup(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>账单明细 · {uGroup?.bill_month.slice(0, 7)}</DialogTitle>
            <DialogDescription>{uGroup?.housing_id ? houseName(uGroup.housing_id) : '未关联住房'} 的当月水电账单，可逐条修改或删除。</DialogDescription>
          </DialogHeader>
          {uGroup && (
            <div className="space-y-1.5">
              {utilities.filter((u) => uGroup.ids.includes(u.id)).map((u) => (
                <div key={u.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <div className="min-w-0">
                    <span className="font-medium">{u.fee_type}</span>
                    <span className="ml-2 text-muted-foreground">{fmt(u.amount)}</span>
                    {u.due_date && <span className="ml-2 text-xs text-muted-foreground">到期 {u.due_date}</span>}
                    {u.paid ? <Badge className="ml-2 bg-success-muted text-success-muted-foreground">已缴</Badge> : <Badge className="ml-2 bg-warning-muted text-warning-muted-foreground">待缴</Badge>}
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => openUEdit(u)}><Pencil /></Button></Tip>
                    <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeUtility(u)}><Trash2 /></Button></Tip>
                  </div>
                </div>
              ))}
              {utilities.filter((u) => uGroup.ids.includes(u.id)).length === 0 && (
                <p className="py-4 text-center text-sm text-muted-foreground">该组暂无账单明细</p>
              )}
            </div>
          )}
          <DialogFooter>
            <Button onClick={() => setUGroup(null)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 租房渠道设置弹窗 */}
      <Dialog open={channelDialog} onOpenChange={setChannelDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>租房渠道设置</DialogTitle>
            <DialogDescription>管理租房渠道，用于新增/编辑住房时下拉选择。</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="flex gap-2">
              <Input value={newChannel} onChange={(e) => setNewChannel(e.target.value)} placeholder="输入渠道名称" onKeyDown={(e) => e.key === 'Enter' && addChannel()} />
              <Button onClick={addChannel}><Plus /> 添加</Button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {channels.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <span className="min-w-0 truncate">{c.name}</span>
                  <div className="flex shrink-0 gap-1">
                    <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setChannelEdit(c); setChannelEditForm(c.name); }}><Pencil className="size-3.5" /></Button></Tip>
                    <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeChannel(c)}><Trash2 className="size-3.5" /></Button></Tip>
                  </div>
                </div>
              ))}
              {channels.length === 0 && <div className="col-span-2 py-4 text-center text-sm text-muted-foreground">暂无渠道</div>}
            </div>
          </div>
          <DialogFooter>
            <Button onClick={() => setChannelDialog(false)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 渠道编辑弹窗 */}
      <Dialog open={channelEdit !== null} onOpenChange={(o) => !o && setChannelEdit(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>编辑租房渠道</DialogTitle>
            <DialogDescription>修改渠道名称。</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>渠道名称</Label>
              <Input value={channelEditForm} onChange={(e) => setChannelEditForm(e.target.value)} />
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setChannelEdit(null)}>取消</Button>
              <Button onClick={saveChannelEdit}>保存</Button>
            </DialogFooter>
          </div>
        </DialogContent>
      </Dialog>

      {/* 新增付款期次弹窗 */}
      <Dialog open={termDialog !== null} onOpenChange={(o) => !o && setTermDialog(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>新增付款期次</DialogTitle>
            <DialogDescription>手动录入一期租金，可按天折算金额提交，期次号自动递增。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>金额 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={termForm.amount} onChange={(e) => setTermForm({ ...termForm, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>到期日</Label><DatePicker value={termForm.due_date} onChange={(v) => setTermForm({ ...termForm, due_date: v })} /></div>
            <div className="col-span-2 space-y-2"><Label>是否已交</Label>
              <div className="flex items-center gap-2 pt-1">
                <Switch checked={termForm.paid} onCheckedChange={(v) => setTermForm({ ...termForm, paid: v })} />
                <span className="text-sm text-muted-foreground">{termForm.paid ? '已交' : '未交'}</span>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setTermDialog(null)}>取消</Button>
            <Button onClick={addTerm}>确认新增</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}
