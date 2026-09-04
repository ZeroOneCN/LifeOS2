import { useEffect, useMemo, useState } from 'react'
import {
  Banknote,
  Building,
  ChevronLeft,
  ChevronRight,
  Eye,
  Home,
  Layers,
  ListTree,
  Loader2,
  Pencil,
  Plus,
  Repeat,
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
import { api } from '@/lib/api'
import { toast } from 'sonner'

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

type TabKey = 'housing' | 'subscription' | 'loan'

function StatCard({ icon: Icon, label, value, hint, className }: { icon: typeof Wallet; label: string; value: string; hint?: string; className?: string }) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
        <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}

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

function HousingTab() {
  const [houses, setHouses] = useState<Housing[]>([])
  const [stats, setStats] = useState<HousingStats | null>(null)
  const [utilities, setUtilities] = useState<Utility[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Housing }>(null)
  const [uDialog, setUDialog] = useState<null | { editing?: Utility }>(null)
  const [uGroup, setUGroup] = useState<null | { housing_id?: number; bill_month: string; ids: number[] }>(null)
  const [viewH, setViewH] = useState<null | Housing>(null)
  const [housePage, setHousePage] = useState(1)
  const [houseTablePage, setHouseTablePage] = useState(1)
  const [utilityPage, setUtilityPage] = useState(1)
  const [form, setForm] = useState<Record<string, string>>({})
  const [channels, setChannels] = useState<RentChannel[]>([])
  const [channelDialog, setChannelDialog] = useState(false)
  const [newChannel, setNewChannel] = useState('')
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
    api.query<HousingStats>('/finance/housing/stats').then(setStats).catch(() => setStats(null))
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

  // 住房信息表格前端分页
  const HOUSE_TABLE_PAGE_SIZE = 8
  const houseTableTotalPages = Math.max(1, Math.ceil(houses.length / HOUSE_TABLE_PAGE_SIZE))
  const pagedTableHouses = houses.slice((houseTablePage - 1) * HOUSE_TABLE_PAGE_SIZE, houseTablePage * HOUSE_TABLE_PAGE_SIZE)

  useEffect(() => {
    loadHouses().then((list) => { if (list.length) list.forEach((h) => loadTermsForHouse(h.id)) })
    loadStats()
    loadChannels()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useEffect(() => {
    loadUtilities()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    if (housePage > houseTotalPages) setHousePage(houseTotalPages)
    if (housePage < 1) setHousePage(1)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [houseTotalPages])

  useEffect(() => {
    if (houseTablePage > houseTableTotalPages) setHouseTablePage(houseTableTotalPages)
    if (houseTablePage < 1) setHouseTablePage(1)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [houseTableTotalPages])

  const houseName = (id?: number) => { const h = houses.find((x) => x.id === id); return h ? h.name : '—' }
  const houseShort = (id?: number) => { const h = houses.find((x) => x.id === id); return h ? (h.short_name || h.name) : '—' }

  // 住房居住天数与总成本（不含押金）口径：居住天数=入住~退租（含退租日）
  const hDays = (h: Housing): number => {
    if (!h.move_in_date) return 0
    const a = new Date(h.move_in_date).getTime()
    const b = h.move_out_date ? new Date(h.move_out_date).getTime() : Date.now()
    if (b < a) return 0
    return Math.floor((b - a) / 86400000) + 1
  }

  // 住房统一成本口径：已发生成本=已交期次+已缴水电+杂费；平均单日=已发生成本/居住天数；折算月租=单日×30
  const houseDays = (h: Housing): number => hDays(h)
  // 服务费已含在付款期次金额里不再计入；中介费为单另费用、保洁/洗衣一并计入成本
  const houseFees = (h: Housing): number => (h.agent_fee || 0) + (h.clean_fee || 0) + (h.laundry_fee || 0)
  const houseTermsPaid = (h: Housing): number => (termsByHouse[h.id] ?? []).filter((t) => t.paid).reduce((s, t) => s + t.amount, 0)
  const houseUtilsPaid = (h: Housing): number => utilities.filter((u) => u.housing_id === h.id && u.paid).reduce((s, u) => s + u.amount, 0)
  const houseIncurred = (h: Housing): number => houseTermsPaid(h) + houseUtilsPaid(h) + houseFees(h)
  const houseDaily = (h: Housing): number => {
    const d = houseDays(h)
    return d ? houseIncurred(h) / d : 0
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
          {(stats?.houses.length ?? 0) > 0 && (() => {
            const days = stats.houses.reduce((s, h) => s + houseDays(h), 0)
            const incurred = stats.houses.reduce((s, h) => s + houseIncurred(h), 0)
            const avgDaily = days ? incurred / days : 0
            return (
              <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
                <StatCard icon={Home} label="住房数" value={`${stats.houses.length} 套`} hint={stats.month} className="text-indigo-500" />
                <StatCard icon={Building} label="总居住天数" value={`${days} 天`} className="text-blue-500" />
                <StatCard icon={Wallet} label="已发生成本(不含押金)" value={fmt(incurred)} hint="已交期次+已缴水电+杂费" className="text-amber-500" />
                <StatCard icon={Wallet} label="平均单日成本" value={fmt(avgDaily)} hint={`${days} 天均摊`} className="text-red-500" />
                <StatCard icon={Wallet} label="折算月租" value={fmt(avgDaily * 30)} hint="单日成本 × 30" className="text-emerald-500" />
              </section>
            )
          })()}
          {sortedHouses.length > 0 && (
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">住房清单 · 折算单日成本</CardTitle>
                <div className="flex items-center gap-1 text-xs text-muted-foreground">
                  <span>{sortedHouses.length} 套 · 第 {housePage}/{houseTotalPages} 页</span>
                  <Button variant="ghost" size="icon" className="h-6 w-6" disabled={housePage <= 1} onClick={() => setHousePage(housePage - 1)}><ChevronLeft className="size-4" /></Button>
                  <Button variant="ghost" size="icon" className="h-6 w-6" disabled={housePage >= houseTotalPages} onClick={() => setHousePage(housePage + 1)}><ChevronRight className="size-4" /></Button>
                </div>
              </CardHeader>
              <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {pagedHouses.map((h) => {
                const tPaid = houseTermsPaid(h)
                const uPaid = houseUtilsPaid(h)
                const fees = houseFees(h)
                const incurred = houseIncurred(h)
                const days = houseDays(h)
                const daily = days ? incurred / days : 0
                const termLabel = h.rent_term === 'quarterly' ? '按季付' : h.rent_term === 'one_time' ? '一次性' : '按月付'
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

                    {/* 主视觉：单日成本 */}
                    <div className="mt-3 rounded-lg bg-gradient-to-br from-indigo-50 to-violet-50 p-3">
                      <div className="flex items-baseline justify-between">
                        <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">平均单日成本</p>
                        <p className="text-[11px] font-medium text-violet-500">{termLabel} · {days} 天</p>
                      </div>
                      <p className="mt-1 text-2xl font-bold leading-none text-red-600">
                        {daily > 0 ? fmt(daily) : '—'}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">
                        折算月租 <span className="font-semibold text-foreground">{daily > 0 ? fmt(daily * 30) : '—'}</span>
                      </p>
                    </div>

                    {/* 已发生成本汇总 */}
                    <div className="mt-3 flex items-center justify-between border-b pb-2">
                      <span className="text-muted-foreground">已发生成本</span>
                      <span className="text-lg font-semibold text-amber-600">{fmt(incurred)}</span>
                    </div>

                    {/* 构成明细 */}
                    <div className="mt-2 space-y-1">
                      <div className="flex items-center justify-between">
                        <span className="text-xs text-muted-foreground">租金（已交期次）</span>
                        <span className="text-sm font-medium">{tPaid > 0 ? fmt(tPaid) : '—'}</span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span className="text-xs text-muted-foreground">水电燃气（已缴）</span>
                        <span className="text-sm font-medium">{uPaid > 0 ? fmt(uPaid) : '—'}</span>
                      </div>
                      {fees > 0 && (
                        <div className="flex items-center justify-between">
                          <span className="text-xs text-muted-foreground">杂费</span>
                          <span className="text-sm font-medium">{fmt(fees)}</span>
                        </div>
                      )}
                    </div>
                  </div>
                )
              })}
              </CardContent>
            </Card>
          )}
        </>
      )}

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">住房信息</CardTitle>
          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={() => { setNewChannel(''); setChannelDialog(true) }}><Layers className="size-4" /> 渠道设置</Button>
            <Button size="sm" onClick={openCreate}><Plus /> 新增住房</Button>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>名称</TableHead><TableHead>小区名</TableHead><TableHead>朝向</TableHead><TableHead>渠道</TableHead><TableHead>入住/退租</TableHead>
                <TableHead className="text-right">已发生成本</TableHead><TableHead className="text-right">居住天数</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {houses.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="h-16 text-center text-muted-foreground">暂无住房信息</TableCell></TableRow>
              ) : pagedTableHouses.map((h) => {
                const inD = h.move_in_date ? new Date(h.move_in_date) : null
                const outD = h.move_out_date ? new Date(h.move_out_date) : (inD ? new Date() : null)
                const days = inD && outD && outD >= inD ? Math.floor((outD.getTime() - inD.getTime()) / 86400000) + 1 : 0
                const incurredCost = houseIncurred(h)
                return (
                <TableRow key={h.id}>
                  <TableCell className="font-medium">{h.name}</TableCell>
                  <TableCell className="text-muted-foreground">{h.short_name ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{h.orientation ?? '—'}</TableCell>
                  <TableCell>{h.channel ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{h.move_in_date}{h.move_out_date ? ` ~ ${h.move_out_date}` : '（在住）'}</TableCell>
                  <TableCell className="text-right font-medium">{incurredCost > 0 ? fmt(incurredCost) : '—'}</TableCell>
                  <TableCell className="text-right text-muted-foreground">{days > 0 ? `${days} 天` : '—'}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" title="查看详情" onClick={() => setViewH(h)}><Eye /></Button>
                      <Button variant="ghost" size="icon" onClick={() => openEdit(h)}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeHousing(h)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
                )
              })}
            </TableBody>
          </Table>
          {houses.length > HOUSE_TABLE_PAGE_SIZE && (
            <div className="border-t p-3">
              <PaginationBar page={houseTablePage} totalPages={houseTableTotalPages} total={houses.length} onPageChange={setHouseTablePage} />
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">水电气账单</CardTitle>
          <Button size="sm" onClick={openUCreate}><Plus /> 新增账单</Button>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>账单月</TableHead><TableHead>住房</TableHead><TableHead>电费</TableHead><TableHead>水费</TableHead><TableHead>燃气费</TableHead><TableHead>其他</TableHead><TableHead className="text-right">合计</TableHead><TableHead>状态</TableHead><TableHead className="w-16 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {utilityGroups.length === 0 ? (
                <TableRow><TableCell colSpan={9} className="h-16 text-center text-muted-foreground">暂无账单记录</TableCell></TableRow>
              ) : pagedUtilityGroups.map((g) => (
                <TableRow key={g.key}>
                  <TableCell>{g.bill_month.slice(0, 7)}</TableCell>
                  <TableCell className="max-w-[140px] truncate text-muted-foreground" title={houseName(g.housing_id)}>{houseShort(g.housing_id)}</TableCell>
                  <TableCell>{g.byType['电费'] ? fmt(g.byType['电费']) : '—'}</TableCell>
                  <TableCell>{g.byType['水费'] ? fmt(g.byType['水费']) : '—'}</TableCell>
                  <TableCell>{g.byType['燃气费'] ? fmt(g.byType['燃气费']) : '—'}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {Object.entries(g.byType)
                      .filter(([f]) => !['电费','水费','燃气费'].includes(f))
                      .map(([f, v]) => `${f} ${fmt(v)}`).join('，') || '—'}
                  </TableCell>
                  <TableCell className="text-right font-medium">{fmt(g.total)}</TableCell>
                  <TableCell>{g.paid ? <Badge className="bg-green-100 text-green-700">已缴</Badge> : <Badge className="bg-amber-100 text-amber-700">待缴</Badge>}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" title="明细/编辑" onClick={() => setUGroup({ housing_id: g.housing_id, bill_month: g.bill_month, ids: g.ids })}><ListTree /></Button>
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
                          <span className={`text-xs ${t.paid ? 'text-green-600' : 'text-muted-foreground'}`}>{t.paid ? '已交' : '未交'}</span>
                          <Switch checked={t.paid} onCheckedChange={() => toggleTermPaid(t)} />
                          <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" title="删除" onClick={() => deleteTerm(t)}><Trash2 className="size-4" /></Button>
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
                              {u.paid ? <Badge className="bg-green-100 text-green-700">已缴</Badge> : <Badge className="bg-amber-100 text-amber-700">待缴</Badge>}
                            </div>
                          </div>
                          <div className="flex shrink-0 items-center gap-1">
                            <Button variant="ghost" size="icon" className="h-7 w-7" title="编辑" onClick={() => openUEdit(u)}><Pencil /></Button>
                            <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" title="删除" onClick={() => removeUtility(u)}><Trash2 /></Button>
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
            const incurred = houseIncurred(viewH)
            const daily = houseDaily(viewH)
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
              ['已发生成本(不含押金)', incurred > 0 ? fmt(incurred) : '—'],
              ['平均单日成本', daily > 0 ? fmt(daily) : '—'],
              ['折算月租(单日×30)', daily > 0 ? fmt(daily * 30) : '—'],
            ]
            return (
              <>
                <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                  {rows.map(([k, v]) => (
                    <div key={k} className="flex justify-between gap-2 border-b py-1">
                      <dt className="text-muted-foreground">{k}</dt>
                      <dd className="truncate text-right font-medium" title={v}>{v}</dd>
                    </div>
                  ))}
                </dl>
                <div className="mt-3">
                  <div className="mb-1.5 text-sm font-medium">成本概览</div>
                  <dl className="gap-x-4 gap-y-1 text-sm">
                    {costRows.map(([k, v]) => (
                      <div key={k} className="flex justify-between gap-2 border-b py-1">
                        <dt className="text-muted-foreground">{k}</dt>
                        <dd className="truncate text-right font-medium" title={v}>{v}</dd>
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
                          <div className="min-w-0 truncate" title={`${u.bill_month.slice(0, 7)} · ${u.fee_type} · ${fmt(u.amount)}`}>
                            <span className="font-medium">{u.bill_month.slice(0, 7)} · {u.fee_type}</span>
                            <span className="ml-2 text-muted-foreground">{fmt(u.amount)}</span>
                          </div>
                          {u.paid ? <Badge className="shrink-0 bg-green-100 text-green-700">已缴</Badge> : <Badge className="shrink-0 bg-amber-100 text-amber-700">待缴</Badge>}
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
                              {t.paid ? <Badge className="bg-green-100 text-green-700">已交</Badge> : <Badge className="bg-amber-100 text-amber-700">未交</Badge>}
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
                    {u.paid ? <Badge className="ml-2 bg-green-100 text-green-700">已缴</Badge> : <Badge className="ml-2 bg-amber-100 text-amber-700">待缴</Badge>}
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    <Button variant="ghost" size="icon" title="编辑" onClick={() => openUEdit(u)}><Pencil /></Button>
                    <Button variant="ghost" size="icon" className="text-destructive" title="删除" onClick={() => removeUtility(u)}><Trash2 /></Button>
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
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>租房渠道设置</DialogTitle>
            <DialogDescription>管理租房渠道，用于新增/编辑住房时下拉选择。</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="flex gap-2">
              <Input value={newChannel} onChange={(e) => setNewChannel(e.target.value)} placeholder="输入渠道名称" onKeyDown={(e) => e.key === 'Enter' && addChannel()} />
              <Button onClick={addChannel}><Plus /> 添加</Button>
            </div>
            <div className="space-y-1.5">
              {channels.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <span>{c.name}</span>
                  <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeChannel(c)}><Trash2 /></Button>
                </div>
              ))}
              {channels.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">暂无渠道</p>}
            </div>
          </div>
          <DialogFooter>
            <Button onClick={() => setChannelDialog(false)}>关闭</Button>
          </DialogFooter>
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

/* ---------------- 服务订阅 ---------------- */

const cycleMeta: Record<string, string> = { month: '月付', quarter: '季付', year: '年付' }

/** 开通时长：start → end（缺省算至今），返回如 1年3个月 / 28天 */
function durationLabel(start?: string, end?: string): string {
  const s = start ? new Date(start) : null
  if (!s || isNaN(s.getTime())) return '—'
  const e = end ? new Date(end) : new Date()
  if (isNaN(e.getTime()) || e < s) return '—'
  const months = (e.getFullYear() - s.getFullYear()) * 12 + (e.getMonth() - s.getMonth())
  const days = Math.floor((e.getTime() - s.getTime()) / 86400000) % 30
  if (months >= 12) return `${Math.floor(months / 12)}年${months % 12 ? `${months % 12}个月` : ''}`
  if (months > 0) return days > 0 ? `${months}个月${days}天` : `${months}个月`
  const totalDays = Math.floor((e.getTime() - s.getTime()) / 86400000)
  return `${totalDays}天`
}
const subStatusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '生效中', className: 'bg-green-100 text-green-700' },
  expired: { label: '已过期', className: 'bg-red-100 text-red-700' },
  cancelled: { label: '已取消', className: 'bg-gray-100 text-gray-600' },
}

type Subscription = {
  id: number
  name: string
  plan_name?: string
  category: string
  billing_cycle: 'month' | 'quarter' | 'year'
  amount: number
  start_date: string
  end_date?: string
  auto_renew?: boolean
  remind_days: number
  status: 'active' | 'expired' | 'cancelled'
  note?: string
}
type SubStats = {
  total_active: number
  active_count: number
  total_count: number
  by_category: { category: string; amount: number }[]
  upcoming: { id: number; name: string; category: string; amount: number; next_renewal: string; remind_days: number }[]
}
type SubCategory = { id: number; name: string }

function SubscriptionTab() {
  const [items, setItems] = useState<Subscription[]>([])
  const [stats, setStats] = useState<SubStats | null>(null)
  const [categories, setCategories] = useState<SubCategory[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Subscription }>(null)
  const [catDialog, setCatDialog] = useState(false)
  const [newCategory, setNewCategory] = useState('')
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Subscription>('/finance/subscriptions', { page_size: 100 })
    setItems(res.items)
    api.stats<SubStats>('/finance/subscriptions').then(setStats).catch(() => setStats(null))
  }
  const loadCategories = async () => {
    api.list<SubCategory>('/finance/subscription-categories', { page_size: 100 }).then((res) => setCategories(res.items)).catch(() => setCategories([]))
  }
  useEffect(() => { load(); loadCategories() }, [])

  const addCategory = async () => {
    const name = newCategory.trim()
    if (!name) return
    try {
      await api.create<SubCategory>('/finance/subscription-categories', { name })
      setNewCategory('')
      await loadCategories()
      toast.success('订阅分类已添加')
    } catch (e) {
      toast.error('添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const removeCategory = async (c: SubCategory) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/subscription-categories', c.id)
      await loadCategories()
      toast.success('订阅分类已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openCreate = () => {
    setForm({ name: '', plan_name: '', category: categories[0]?.name ?? '会员', billing_cycle: 'month', amount: '', start_date: new Date().toISOString().slice(0, 10), end_date: '', auto_renew: 'false', remind_days: '30', status: 'active', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      name: form.name, plan_name: form.plan_name || null, category: form.category, billing_cycle: form.billing_cycle,
      amount: Number(form.amount), start_date: form.start_date, end_date: form.end_date || null,
      auto_renew: form.auto_renew === 'true', remind_days: Number(form.remind_days),
      status: form.status, note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/subscriptions', dialog.editing.id, payload)
      else await api.create('/finance/subscriptions', payload)
      setDialog(null)
      await load()
      toast.success(dialog?.editing ? '订阅已更新' : '订阅已添加')
    } catch (e) {
      toast.error(dialog?.editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const remove = async (s: Subscription) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/subscriptions', s.id)
      await load()
      toast.success('订阅已删除')
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
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Repeat} label="每月订阅支出" value={fmt(stats.total_active)} hint={`${stats.active_count} 项生效中`} className="text-indigo-500" />
            <StatCard icon={Wallet} label="总订阅数" value={`${stats.total_count} 项`} hint={`${stats.active_count} 项生效`} />
            <StatCard icon={Layers} label="订阅分类" value={`${stats.by_category.length} 类`} hint={stats.by_category[0] ? `最多 ${stats.by_category[0].category}` : '暂无分类'} />
            <StatCard icon={Repeat} label="即将续费" value={`${stats.upcoming.length} 项`} hint={stats.upcoming[0] ? `最近 ${stats.upcoming[0].next_renewal}` : '近期无续费'} className="text-amber-500" />
          </section>
          {stats.by_category.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium">按分类订阅支出</CardTitle></CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {stats.by_category.map((c) => (
                    <Badge key={c.category} variant="outline">{c.category}：{fmt(c.amount)}</Badge>
                  ))}
                </div>
              </CardContent>
            </Card>
          )}
          {stats.upcoming.length > 0 && (
            <Card className="border-amber-200 bg-amber-50">
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-amber-700">即将续费提醒</CardTitle></CardHeader>
              <CardContent className="space-y-1.5 text-sm">
                {stats.upcoming.map((u) => (
                  <div key={u.id} className="flex flex-wrap items-center justify-between rounded-md bg-white/70 px-3 py-1.5">
                    <span>{u.name} <Badge variant="outline">{u.category}</Badge></span>
                    <span className="text-muted-foreground">续费 {u.next_renewal} · {fmt(u.amount)}</span>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
        </>
      )}

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">服务订阅</CardTitle>
          <div className="flex items-center gap-2">
            <Button size="sm" variant="outline" onClick={() => { setNewCategory(''); setCatDialog(true) }}><Layers className="size-4" /> 分类设置</Button>
            <Button onClick={openCreate}><Plus /> 新增订阅</Button>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>名称</TableHead><TableHead>方案名称</TableHead><TableHead>分类</TableHead><TableHead>开通时间</TableHead><TableHead>到期时间</TableHead><TableHead>开通时长</TableHead>
                <TableHead className="text-right">周期金额</TableHead><TableHead>计费周期</TableHead><TableHead>自动续费</TableHead><TableHead>当前状态</TableHead><TableHead>备注</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.length === 0 ? (
                <TableRow><TableCell colSpan={12} className="h-16 text-center text-muted-foreground">暂无订阅，点击"新增订阅"添加</TableCell></TableRow>
              ) : items.map((s) => {
                const dur = durationLabel(s.start_date, s.end_date)
                return (
                <TableRow key={s.id}>
                  <TableCell className="font-medium">{s.name}</TableCell>
                  <TableCell className="text-muted-foreground">{s.plan_name ?? '—'}</TableCell>
                  <TableCell>{s.category}</TableCell>
                  <TableCell className="text-muted-foreground">{s.start_date}</TableCell>
                  <TableCell className="text-muted-foreground">{s.end_date ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{dur}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(s.amount)}</TableCell>
                  <TableCell>{cycleMeta[s.billing_cycle] ?? s.billing_cycle}</TableCell>
                  <TableCell>{s.auto_renew ? <Badge className="bg-green-100 text-green-700">是</Badge> : <Badge variant="outline">否</Badge>}</TableCell>
                  <TableCell><Badge className={subStatusMeta[s.status]?.className}>{subStatusMeta[s.status]?.label ?? s.status}</Badge></TableCell>
                  <TableCell className="max-w-[160px] truncate text-muted-foreground" title={s.note ?? ''}>{s.note ?? '—'}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => { setForm({ name: s.name, plan_name: s.plan_name ?? '', category: s.category, billing_cycle: s.billing_cycle, amount: String(s.amount), start_date: s.start_date, end_date: s.end_date ?? '', auto_renew: s.auto_renew ? 'true' : 'false', remind_days: String(s.remind_days), status: s.status, note: s.note ?? '' }); setDialog({ editing: s }) }}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(s)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
                )
              })}
            </TableBody>
          </Table>
          </div>
        </CardContent>
      </Card>

      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑订阅' : '新增订阅'}</DialogTitle>
            <DialogDescription>记录会员、服务器等周期性付费服务。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>订阅名称 <span className="text-destructive">*</span></Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="如 视频会员 / 云服务器" /></div>
            <div className="space-y-2"><Label>方案名称</Label><Input value={form.plan_name} onChange={(e) => setForm({ ...form, plan_name: e.target.value })} placeholder="如 黄金会员 / 2C4G 套餐" /></div>
            <div className="space-y-2"><Label>分类 <span className="text-destructive">*</span></Label>
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {categories.length ? categories.map((c) => <SelectItem key={c.id} value={c.name}>{c.name}</SelectItem>) : <SelectItem value="其他">其他</SelectItem>}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>计费周期</Label>
              <Select value={form.billing_cycle} onValueChange={(v) => setForm({ ...form, billing_cycle: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="month">按月</SelectItem><SelectItem value="quarter">按季</SelectItem><SelectItem value="year">按年</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>每期金额 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>开通时间 <span className="text-destructive">*</span></Label><DatePicker value={form.start_date} onChange={(v) => setForm({ ...form, start_date: v })} /></div>
            <div className="space-y-2"><Label>到期时间</Label><DatePicker value={form.end_date} onChange={(v) => setForm({ ...form, end_date: v })} /></div>
            <div className="space-y-2"><Label>自动续费</Label>
              <Select value={form.auto_renew} onValueChange={(v) => setForm({ ...form, auto_renew: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="false">否</SelectItem><SelectItem value="true">是</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>过期前提醒(天)</Label><Input type="number" min={0} value={form.remind_days} onChange={(e) => setForm({ ...form, remind_days: e.target.value })} /></div>
            <div className="space-y-2"><Label>状态</Label>
              <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="active">生效中</SelectItem><SelectItem value="expired">已过期</SelectItem><SelectItem value="cancelled">已取消</SelectItem></SelectContent>
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

      {/* 分类管理弹窗 */}
      <Dialog open={catDialog} onOpenChange={setCatDialog}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>订阅分类设置</DialogTitle>
            <DialogDescription>管理服务订阅的分类，用于下拉选择。</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="flex gap-2">
              <Input value={newCategory} onChange={(e) => setNewCategory(e.target.value)} placeholder="输入分类名称" onKeyDown={(e) => e.key === 'Enter' && addCategory()} />
              <Button onClick={addCategory}><Plus /> 添加</Button>
            </div>
            <div className="space-y-1.5">
              {categories.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <span>{c.name}</span>
                  <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeCategory(c)}><Trash2 /></Button>
                </div>
              ))}
              {categories.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">暂无分类</p>}
            </div>
          </div>
          <DialogFooter>
            <Button onClick={() => setCatDialog(false)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 网贷借还 ---------------- */

type LoanPlatform = { id: number; name: string; bill_day?: number; due_day?: number; credit_limit?: number; note?: string }
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
  note?: string
}
type LoanBillStats = {
  total: number; paid: number; remaining: number; total_interest?: number
  status: { pending: number; partial: number; cleared: number }
  by_month: { month: string; amount: number }[]
  upcoming: { id: number; platform_id?: number; bill_month: string; due_date?: string; amount: number; interest?: number; paid_amount: number; remaining: number; status: string }[]
}
type Repayment = { id: number; bill_id?: number; repay_date: string; amount: number; discount?: number; method?: string; note?: string }

const billStatusMeta: Record<string, { label: string; className: string }> = {
  pending: { label: '待还', className: 'bg-amber-100 text-amber-700' },
  partial: { label: '部分已还', className: 'bg-blue-100 text-blue-700' },
  cleared: { label: '已结清', className: 'bg-green-100 text-green-700' },
}

function LoanTab() {
  const [platforms, setPlatforms] = useState<LoanPlatform[]>([])
  const [platformStats, setPlatformStats] = useState<LoanPlatformStats | null>(null)
  const [bills, setBills] = useState<LoanBill[]>([])
  const [billStats, setBillStats] = useState<LoanBillStats | null>(null)
  const [loanMonth, setLoanMonth] = useState(() => { const n = new Date(); return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}` })
  const [repayments, setRepayments] = useState<Repayment[]>([])
  const [selectedBill, setSelectedBill] = useState<number | null>(null)

  const [pfDialog, setPfDialog] = useState(false)
  const [newPf, setNewPf] = useState<Record<string, string>>({})
  const [pfEdit, setPfEdit] = useState<null | LoanPlatform>(null)
  const [pfEditForm, setPfEditForm] = useState<Record<string, string>>({})
  const [repStats, setRepStats] = useState<{ total_paid: number; total_discount: number; count: number; by_month: { month: string; amount: number }[] } | null>(null)
  const [billDialog, setBillDialog] = useState<null | { editing?: LoanBill }>(null)
  const [billForm, setBillForm] = useState<Record<string, string>>({})
  const [repayDialog, setRepayDialog] = useState<null | LoanBill>(null)
  const [repayForm, setRepayForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

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
  }, [])
  useEffect(() => {
    loadRepayments(selectedBill)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedBill])

  const refresh = async () => {
    await loadBills()
    await loadPlatforms()
    loadRepStats()
    if (selectedBill) await loadRepayments(selectedBill)
  }

  const platformName = (id?: number) => platforms.find((p) => p.id === id)?.name ?? '—'

  const shiftMonth = (ym: string, delta: number) => {
    const [y, m] = ym.split('-').map(Number)
    const dt = new Date(y, m - 1 + delta, 1)
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`
  }
  const monthBills = bills.filter((b) => b.bill_month.slice(0, 7) === loanMonth)
  const addPlatform = async () => {
    const name = newPf.name?.trim()
    if (!name) return
    try {
      await api.create('/finance/loan-platforms', {
        name, bill_day: newPf.bill_day ? Number(newPf.bill_day) : null,
        due_day: newPf.due_day ? Number(newPf.due_day) : null,
        credit_limit: newPf.credit_limit ? Number(newPf.credit_limit) : null,
        note: newPf.note || null,
      })
      toast.success('平台已添加')
    } catch (e) {
      toast.error('添加失败', { description: (e as Error).message })
    }
    setNewPf({})
    await loadPlatforms()
  }
  const openPfEdit = (p: LoanPlatform) => {
    setPfEditForm({ name: p.name, bill_day: p.bill_day != null ? String(p.bill_day) : '', due_day: p.due_day != null ? String(p.due_day) : '', credit_limit: p.credit_limit != null ? String(p.credit_limit) : '' })
    setPfEdit(p)
  }
  const savePfEdit = async () => {
    if (!pfEdit) return
    try {
      await api.update('/finance/loan-platforms', pfEdit.id, {
        name: pfEditForm.name, bill_day: pfEditForm.bill_day ? Number(pfEditForm.bill_day) : null,
        due_day: pfEditForm.due_day ? Number(pfEditForm.due_day) : null,
        credit_limit: pfEditForm.credit_limit ? Number(pfEditForm.credit_limit) : null,
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

  const dueFor = (platformId: string, billMonth: string) => {
    const pf = platforms.find((p) => p.id === Number(platformId))
    const day = pf?.due_day
    if (!day || !billMonth) return ''
    const [y, m] = billMonth.split('-').map(Number)
    if (!y || !m) return ''
    const last = new Date(y, m, 0).getDate()
    const dd = Math.min(day, last)
    return `${y}-${String(m).padStart(2, '0')}-${String(dd).padStart(2, '0')}`
  }
  const openBillCreate = () => {
    const pfId = platforms[0] ? String(platforms[0].id) : ''
    setBillForm({ platform_id: pfId, bill_month: loanMonth, due_date: dueFor(pfId, loanMonth), amount: '', interest: '0', paid_amount: '0', status: 'pending', note: '' })
    setBillDialog({})
  }
  const saveBill = async () => {
    const payload = {
      platform_id: billForm.platform_id ? Number(billForm.platform_id) : null,
      bill_month: billForm.bill_month, due_date: billForm.due_date || null,
      amount: Number(billForm.amount), interest: billForm.interest ? Number(billForm.interest) : 0,
      paid_amount: Number(billForm.paid_amount || 0),
      status: billForm.status, note: billForm.note || null,
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
      if (selectedBill === b.id) setSelectedBill(null)
      await refresh()
      toast.success('账单已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openRepay = (b: LoanBill) => {
    const remaining = b.amount - b.paid_amount
    setRepayForm({ repay_date: new Date().toISOString().slice(0, 10), amount: remaining > 0 ? String(remaining) : '', discount: '', method: '', note: '' })
    setRepayDialog(b)
  }
  const submitRepay = async () => {
    if (!repayDialog) return
    const payload = {
      bill_id: repayDialog.id, repay_date: repayForm.repay_date,
      amount: Number(repayForm.amount), discount: repayForm.discount ? Number(repayForm.discount) : 0,
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

  return (
    <div className="flex flex-col gap-4">
      {platformStats && (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <StatCard icon={Wallet} label="累计待还" value={fmt(platformStats.total_remaining)} className="text-red-500" />
          <StatCard icon={Wallet} label="累计欠款" value={fmt(billStats?.total ?? 0)} hint={`已还 ${fmt(billStats?.paid ?? 0)}`} className="text-amber-500" />
          <StatCard icon={Wallet} label="利息总额" value={fmt(billStats?.total_interest ?? 0)} hint="全部账单利息合计" className="text-green-600" />
          <StatCard icon={Banknote} label="优惠合计" value={fmt(repStats?.total_discount ?? 0)} hint="还款优惠/抵扣" className="text-indigo-500" />
          <StatCard icon={Layers} label="借款平台" value={`${platformStats.platform_count} 个`} hint={`还款 ${repStats?.count ?? 0} 笔`} />
          <StatCard icon={Banknote} label="待还账单" value={`${(billStats?.status.pending ?? 0) + (billStats?.status.partial ?? 0)} 笔`} hint={`${billStats?.by_month[0]?.month ?? ''} 到期数据`} className="text-indigo-500" />
        </section>
      )}

      {/* 借款平台 */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">借款平台</CardTitle>
          <Button size="sm" variant="outline" onClick={() => setPfDialog(true)}><Plus /> 管理平台</Button>
        </CardHeader>
        <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          {platformStats?.platforms.map((p) => (
            <div key={p.id} className="rounded-lg border p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="font-medium">{p.name}</span>
                <div className="flex items-center gap-1">
                  <Badge variant="outline">额度 {p.credit_limit != null ? fmt(p.credit_limit) : '—'}</Badge>
                  <Button variant="ghost" size="icon" className="h-6 w-6" title="编辑平台" onClick={() => openPfEdit(p)}><Pencil className="size-3.5" /></Button>
                </div>
              </div>
              <div className="mt-1 text-xs text-muted-foreground">
                账单日 {p.bill_day ?? '—'} · 还款日 {p.due_day ?? '—'} · {p.bill_count} 笔账单
              </div>
              <div className="mt-2 flex justify-between">
                <span>累计欠款 <b>{fmt(p.total_owed)}</b></span>
                <span className={p.remaining > 0 ? 'text-red-600' : 'text-green-600'}>待还 {fmt(p.remaining)}</span>
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
        <CardHeader className="flex flex-wrap items-center justify-between gap-2 space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">网贷账单（含利息）</CardTitle>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="icon" title="上一月" onClick={() => setLoanMonth(shiftMonth(loanMonth, -1))}><ChevronLeft /></Button>
            <span className="min-w-[72px] text-center text-sm font-medium">{loanMonth}</span>
            <Button variant="ghost" size="icon" title="下一月" onClick={() => setLoanMonth(shiftMonth(loanMonth, 1))}><ChevronRight /></Button>
            <Button size="sm" variant="outline" onClick={() => { const n = new Date(); setLoanMonth(`${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`) }}>当月</Button>
            <Button onClick={openBillCreate} className="ml-1"><Plus /> 新增账单</Button>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>平台</TableHead><TableHead>账单月份</TableHead><TableHead>到期日</TableHead>
                <TableHead className="text-right">欠款/利息</TableHead><TableHead className="text-right">已还/剩余</TableHead><TableHead>状态</TableHead><TableHead className="text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {monthBills.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="h-16 text-center text-muted-foreground">{bills.length === 0 ? '暂无账单' : `「${loanMonth}」无账单`}</TableCell></TableRow>
              ) : monthBills.map((b) => {
                const remaining = b.amount - b.paid_amount
                const interest = b.interest ?? 0
                return (
                  <TableRow key={b.id} className={selectedBill === b.id ? 'bg-blue-50/60' : ''}>
                    <TableCell onClick={() => setSelectedBill(selectedBill === b.id ? null : b.id)} className="cursor-pointer font-medium">{platformName(b.platform_id)}</TableCell>
                    <TableCell>{b.bill_month.slice(0, 7)}</TableCell>
                    <TableCell className="text-muted-foreground">{b.due_date ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      <div>{fmt(b.amount)}</div>
                      {interest > 0 && <div className="text-xs text-amber-600">利息 {fmt(interest)}</div>}
                    </TableCell>
                    <TableCell className={`text-right ${remaining > 0 ? '' : ''}`}>
                      <div>{fmt(b.paid_amount)}</div>
                      <div className={`text-xs ${remaining > 0 ? 'text-red-600' : 'text-green-600'}`}>剩余 {fmt(remaining)}</div>
                    </TableCell>
                    <TableCell><Badge className={billStatusMeta[b.status]?.className}>{billStatusMeta[b.status]?.label ?? b.status}</Badge></TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        {remaining > 0 && (
                          <Button size="sm" onClick={() => openRepay(b)} className="h-7 gap-1 px-2 text-xs"><Banknote className="size-3.5" />还款</Button>
                        )}
                        <Button variant="ghost" size="icon" onClick={() => { setBillForm({ platform_id: b.platform_id ? String(b.platform_id) : '', bill_month: b.bill_month, due_date: b.due_date ?? '', amount: String(b.amount), interest: String(b.interest ?? 0), paid_amount: String(b.paid_amount), status: b.status, note: b.note ?? '' }); setBillDialog({ editing: b }) }}><Pencil /></Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeBill(b)}><Trash2 /></Button>
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
        <Card className="border-amber-200 bg-amber-50">
          <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-amber-700">近期待还（30 天内）</CardTitle></CardHeader>
          <CardContent className="space-y-1.5 text-sm">
            {billStats?.upcoming.map((u) => (
              <div key={u.id} className="flex flex-wrap items-center justify-between rounded-md bg-white/70 px-3 py-1.5">
                <span>{platformName(u.platform_id)} · {u.bill_month} <Badge variant="outline">{billStatusMeta[u.status]?.label}</Badge></span>
                <span className="text-muted-foreground">到期 {u.due_date ?? '—'} · 剩余 <span className="font-medium text-red-700">{fmt(u.remaining)}</span></span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-lg font-medium">还款记录</CardTitle>
          <p className="text-sm text-muted-foreground">
            {selectedBill ? `当前查看：${platformName(bills.find((b) => b.id === selectedBill)?.platform_id)} · ${bills.find((b) => b.id === selectedBill)?.bill_month ?? ''}` : '点击账单行的平台名称查看该账单的还款记录'}
          </p>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>还款日期</TableHead><TableHead className="text-right">实付</TableHead><TableHead className="text-right">优惠</TableHead><TableHead>方式</TableHead><TableHead>备注</TableHead>
                {selectedBill && <TableHead className="w-16 text-right">操作</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {!selectedBill ? (
                <TableRow><TableCell colSpan={5} className="h-16 text-center text-muted-foreground">请选择账单查看还款记录</TableCell></TableRow>
              ) : repayments.length === 0 ? (
                <TableRow><TableCell colSpan={5} className="h-16 text-center text-muted-foreground">该账单暂无还款记录</TableCell></TableRow>
              ) : repayments.map((r) => (
                <TableRow key={r.id}>
                  <TableCell>{r.repay_date}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(r.amount)}</TableCell>
                  <TableCell className="text-right text-green-600">{r.discount && r.discount > 0 ? `-${fmt(r.discount)}` : '—'}</TableCell>
                  <TableCell>{r.method ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{r.note ?? '—'}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeRepay(r)}><Trash2 /></Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* 平台管理弹窗 */}
      <Dialog open={pfDialog} onOpenChange={setPfDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>借款平台管理</DialogTitle><DialogDescription>添加借款平台并设置账单日、还款日与额度。</DialogDescription></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2">
              <Input value={newPf.name ?? ''} onChange={(e) => setNewPf({ ...newPf, name: e.target.value })} placeholder="平台名称" />
              <Input value={newPf.bill_day ?? ''} onChange={(e) => setNewPf({ ...newPf, bill_day: e.target.value })} placeholder="账单日(1-31)" />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Input value={newPf.due_day ?? ''} onChange={(e) => setNewPf({ ...newPf, due_day: e.target.value })} placeholder="还款日(1-31)" />
              <Input value={newPf.credit_limit ?? ''} onChange={(e) => setNewPf({ ...newPf, credit_limit: e.target.value })} placeholder="额度" />
            </div>
            <Button className="w-full" onClick={addPlatform}><Plus /> 添加平台</Button>
            <div className="space-y-1.5">
              {platforms.map((p) => (
                <div key={p.id} className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm">
                  <span>{p.name} {p.bill_day ? `· 账单日${p.bill_day}` : ''} {p.due_day ? `· 还款日${p.due_day}` : ''}</span>
                  <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removePlatform(p.id)}><Trash2 /></Button>
                </div>
              ))}
            </div>
          </div>
          <DialogFooter><Button onClick={() => setPfDialog(false)}>关闭</Button></DialogFooter>
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
              {repayDialog ? `${platformName(repayDialog.platform_id)} · ${repayDialog.bill_month} · 剩余 ${fmt(repayDialog.amount - repayDialog.paid_amount)}` : ''}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>还款日期 <span className="text-destructive">*</span></Label><DatePicker value={repayForm.repay_date} onChange={(v) => setRepayForm({ ...repayForm, repay_date: v })} /></div>
            <div className="space-y-2"><Label>应还金额 <span className="text-destructive">*</span></Label><Input type="number" min={0.01} step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} placeholder="含优惠的欠款部分" /></div>
            <div className="space-y-2"><Label>优惠(券/抵扣)</Label><Input type="number" min={0} step="0.01" value={repayForm.discount} onChange={(e) => setRepayForm({ ...repayForm, discount: e.target.value })} placeholder="0" /></div>
            <div className="space-y-2"><Label>还款方式</Label><Input value={repayForm.method} onChange={(e) => setRepayForm({ ...repayForm, method: e.target.value })} placeholder="银行卡/支付宝等" /></div>
            <div className="col-span-2 space-y-1">
              <Label>实付支出（= 应还 - 优惠）</Label>
              <div className="rounded-lg border px-3 py-2 text-sm font-medium">
                {fmt(Math.max(0, (Number(repayForm.amount) || 0) - (Number(repayForm.discount) || 0)))}
                {(Number(repayForm.discount) || 0) > 0 && (
                  <span className="ml-2 text-xs text-green-600">优惠抵减 {fmt(Number(repayForm.discount))}</span>
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
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPfEdit(null)}>取消</Button>
            <Button onClick={savePfEdit} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 页面 ---------------- */

export function BillsPage() {
  const [tab, setTab] = useState<TabKey>('loan')
  const tabs: { key: TabKey; label: string; icon: typeof Home }[] = [
    { key: 'loan', label: '网贷借还', icon: Banknote },
    { key: 'housing', label: '房租水电', icon: Home },
    { key: 'subscription', label: '服务订阅', icon: Repeat },
  ]

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">账单管理</h1>
        <p className="text-sm text-muted-foreground">集中管理住房水电、服务订阅与网贷还款。</p>
      </section>

      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {tabs.map((t) => (
          <Button
            key={t.key}
            variant={tab === t.key ? 'default' : 'ghost'}
            className="flex-1"
            onClick={() => setTab(t.key)}
          >
            <t.icon className="size-4" /> {t.label}
          </Button>
        ))}
      </div>

      {tab === 'loan' && <LoanTab />}
      {tab === 'housing' && <HousingTab />}
      {tab === 'subscription' && <SubscriptionTab />}
    </div>
  )
}