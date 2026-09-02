import { useEffect, useState } from 'react'
import {
  Banknote,
  Building,
  Home,
  Layers,
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
import { api } from '@/lib/api'

const fmt = (n: number) => `¥${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
const PAGE_SIZE = 50

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
  rent_term: 'monthly' | 'quarterly'
  actual_monthly_rent: number
  deposit?: number
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

const feeTypes = ['水费', '电费', '燃气费', '宽带', '物业', '其他']

function HousingTab() {
  const [houses, setHouses] = useState<Housing[]>([])
  const [stats, setStats] = useState<HousingStats | null>(null)
  const [utilities, setUtilities] = useState<Utility[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Housing }>(null)
  const [uDialog, setUDialog] = useState<null | { editing?: Utility }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
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
    const res = await api.list<Utility>('/finance/utilities', { page_size: PAGE_SIZE })
    setUtilities(res.items)
  }

  useEffect(() => {
    loadHouses()
    loadStats()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  useEffect(() => {
    loadUtilities()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const houseName = (id?: number) => { const h = houses.find((x) => x.id === id); return h ? (h.short_name || h.name) : '—' }

  const openCreate = () => {
    setForm({ name: '', short_name: '', channel: '', orientation: '', move_in_date: '', move_out_date: '', rent_term: 'monthly', actual_monthly_rent: '', deposit: '', agent_fee: '', clean_fee: '', service_fee: '', laundry_fee: '', note: '' })
    setDialog({})
  }
  const openEdit = (h: Housing) => {
    setForm({
      name: h.name, short_name: h.short_name ?? '', channel: h.channel ?? '', orientation: h.orientation ?? '',
      move_in_date: h.move_in_date, move_out_date: h.move_out_date ?? '',
      rent_term: h.rent_term, actual_monthly_rent: String(h.actual_monthly_rent),
      deposit: h.deposit != null ? String(h.deposit) : '', agent_fee: h.agent_fee != null ? String(h.agent_fee) : '',
      clean_fee: h.clean_fee != null ? String(h.clean_fee) : '', service_fee: h.service_fee != null ? String(h.service_fee) : '',
      laundry_fee: h.laundry_fee != null ? String(h.laundry_fee) : '', note: h.note ?? '',
    })
    setDialog({ editing: h })
  }
  const saveHousing = async () => {
    const payload = {
      name: form.name, short_name: form.short_name || null, channel: form.channel || null, orientation: form.orientation || null,
      move_in_date: form.move_in_date, move_out_date: form.move_out_date || null,
      rent_term: form.rent_term, actual_monthly_rent: Number(form.actual_monthly_rent),
      deposit: form.deposit ? Number(form.deposit) : 0, agent_fee: form.agent_fee ? Number(form.agent_fee) : 0,
      clean_fee: form.clean_fee ? Number(form.clean_fee) : 0, service_fee: form.service_fee ? Number(form.service_fee) : 0,
      laundry_fee: form.laundry_fee ? Number(form.laundry_fee) : 0, note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/housing', dialog.editing.id, payload)
      else await api.create('/finance/housing', payload)
      setDialog(null)
      await loadHouses()
      await loadStats()
    } finally {
      setSaving(false)
    }
  }
  const removeHousing = async (h: Housing) => {
    if (!(await confirm())) return
    await api.remove('/finance/housing', h.id)
    await loadHouses()
    await loadStats()
  }

  const openUCreate = () => {
    setForm({ housing_id: '', bill_month: '', fee_type: '电费', amount: '', due_date: '', paid: 'false', note: '' })
    setUDialog({})
  }
  const saveUtility = async () => {
    const editingU = uDialog?.editing
    const payload = {
      housing_id: form.housing_id ? Number(form.housing_id) : null,
      bill_month: form.bill_month, fee_type: form.fee_type, amount: Number(form.amount),
      due_date: form.due_date || null, paid: form.paid === 'true', note: form.note || null,
    }
    setSaving(true)
    try {
      if (editingU) await api.update('/finance/utilities', editingU.id, payload)
      else await api.create('/finance/utilities', payload)
      setUDialog(null)
      await loadUtilities()
    } finally {
      setSaving(false)
    }
  }
  const removeUtility = async (u: Utility) => {
    if (!(await confirm())) return
    await api.remove('/finance/utilities', u.id)
    await loadUtilities()
  }

  return (
    <div className="flex flex-col gap-4">
      {stats && (
        <>
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard icon={Home} label="组合月租" value={fmt(stats.combined_monthly_rent)} hint={`${stats.month} · ${stats.house_count} 套`} className="text-indigo-500" />
            <StatCard icon={Building} label="押金合计" value={fmt(stats.total_deposit)} className="text-blue-500" />
            <StatCard icon={Wallet} label="杂费合计" value={fmt(stats.total_fees)} hint="中介/保洁/服务/洗衣" className="text-amber-500" />
            <StatCard icon={Wallet} label="全部月租之和" value={fmt(stats.houses.reduce((s, h) => s + h.actual_monthly_rent, 0))} hint={`${stats.houses.length} 套在租`} className="text-emerald-500" />
          </section>
          {stats.houses.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium">住房清单 · 折算单日成本</CardTitle></CardHeader>
              <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {stats.houses.map((h) => (
                  <div key={h.id} className="rounded-lg border p-3 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="font-medium">{h.short_name || h.name}</span>
                      <Badge variant="outline">{h.rent_term === 'quarterly' ? '按季付' : '按月付'}</Badge>
                    </div>
                    <div className="mt-0.5 truncate text-xs text-muted-foreground">{h.name}</div>
                    <div className="mt-1 text-muted-foreground">
                      {h.channel ? `${h.channel} · ` : ''}入住 {h.move_in_date}
                      {h.move_out_date ? ` · 退租 ${h.move_out_date}` : ''}
                      {h.orientation ? ` · ${h.orientation}` : ''}
                    </div>
                    <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
                      <span>月租 <b>{fmt(h.actual_monthly_rent)}</b></span>
                      <span>单日 <b>{fmt(h.single_day_cost)}</b></span>
                      <span>月计 <b>{fmt(h.monthly_contribution)}</b></span>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
        </>
      )}

      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">住房信息</CardTitle>
          <Button size="sm" onClick={openCreate}><Plus /> 新增住房</Button>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>名称</TableHead><TableHead>小区名</TableHead><TableHead>渠道</TableHead><TableHead>入住/退租</TableHead>
                <TableHead>月租</TableHead><TableHead>押金</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {houses.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="h-16 text-center text-muted-foreground">暂无住房信息</TableCell></TableRow>
              ) : houses.map((h) => (
                <TableRow key={h.id}>
                  <TableCell className="font-medium">{h.name}</TableCell>
                  <TableCell className="text-muted-foreground">{h.short_name ?? '—'}</TableCell>
                  <TableCell>{h.channel ?? '—'}</TableCell>
                  <TableCell className="text-muted-foreground">{h.move_in_date}{h.move_out_date ? ` ~ ${h.move_out_date}` : ''}</TableCell>
                  <TableCell>{fmt(h.actual_monthly_rent)}</TableCell>
                  <TableCell>{h.deposit ? fmt(h.deposit) : '—'}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => openEdit(h)}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeHousing(h)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
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
                <TableHead>月份</TableHead><TableHead>住房</TableHead><TableHead>类型</TableHead>
                <TableHead className="text-right">金额</TableHead><TableHead>到期日</TableHead><TableHead>状态</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {utilities.length === 0 ? (
                <TableRow><TableCell colSpan={7} className="h-16 text-center text-muted-foreground">暂无账单记录</TableCell></TableRow>
              ) : utilities.map((u) => (
                <TableRow key={u.id}>
                  <TableCell>{u.bill_month}</TableCell>
                  <TableCell>{houseName(u.housing_id)}</TableCell>
                  <TableCell>{u.fee_type}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(u.amount)}</TableCell>
                  <TableCell className="text-muted-foreground">{u.due_date ?? '—'}</TableCell>
                  <TableCell>{u.paid ? <Badge className="bg-green-100 text-green-700">已缴</Badge> : <Badge className="bg-amber-100 text-amber-700">待缴</Badge>}</TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => { setForm({ housing_id: u.housing_id ? String(u.housing_id) : '', bill_month: u.bill_month, fee_type: u.fee_type, amount: String(u.amount), due_date: u.due_date ?? '', paid: u.paid ? 'true' : 'false', note: u.note ?? '' }); setUDialog({ editing: u }) }}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeUtility(u)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* 住房弹窗 */}
      <Dialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{dialog?.editing ? '编辑住房' : '新增住房'}</DialogTitle>
            <DialogDescription>记录租房渠道、押金、杂费与租期，用于组合月租分析。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>房屋名称 <span className="text-destructive">*</span></Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="如 XX小区X栋X室" /></div>
            <div className="space-y-2"><Label>小区名（缩写）</Label><Input value={form.short_name} onChange={(e) => setForm({ ...form, short_name: e.target.value })} placeholder="如 珠江新城 / 三里屯" /></div>
            <div className="space-y-2"><Label>租房渠道</Label><Input value={form.channel} onChange={(e) => setForm({ ...form, channel: e.target.value })} placeholder="贝壳/自如/中介" /></div>
            <div className="space-y-2"><Label>入住时间 <span className="text-destructive">*</span></Label><Input type="date" value={form.move_in_date} onChange={(e) => setForm({ ...form, move_in_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>退租时间</Label><Input type="date" value={form.move_out_date} onChange={(e) => setForm({ ...form, move_out_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>房屋朝向</Label><Input value={form.orientation} onChange={(e) => setForm({ ...form, orientation: e.target.value })} /></div>
            <div className="space-y-2"><Label>缴纳方式</Label>
              <Select value={form.rent_term} onValueChange={(v) => setForm({ ...form, rent_term: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="monthly">按月付</SelectItem><SelectItem value="quarterly">按季付</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>实际月租 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.actual_monthly_rent} onChange={(e) => setForm({ ...form, actual_monthly_rent: e.target.value })} /></div>
            <div className="space-y-2"><Label>押金</Label><Input type="number" min={0} step="0.01" value={form.deposit} onChange={(e) => setForm({ ...form, deposit: e.target.value })} /></div>
            <div className="space-y-2"><Label>中介费</Label><Input type="number" min={0} step="0.01" value={form.agent_fee} onChange={(e) => setForm({ ...form, agent_fee: e.target.value })} /></div>
            <div className="space-y-2"><Label>保洁费</Label><Input type="number" min={0} step="0.01" value={form.clean_fee} onChange={(e) => setForm({ ...form, clean_fee: e.target.value })} /></div>
            <div className="space-y-2"><Label>服务费</Label><Input type="number" min={0} step="0.01" value={form.service_fee} onChange={(e) => setForm({ ...form, service_fee: e.target.value })} /></div>
            <div className="space-y-2"><Label>洗衣费</Label><Input type="number" min={0} step="0.01" value={form.laundry_fee} onChange={(e) => setForm({ ...form, laundry_fee: e.target.value })} /></div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialog(null)}>取消</Button>
            <Button onClick={saveHousing} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
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
            <div className="space-y-2"><Label>账单月份 <span className="text-destructive">*</span></Label><Input type="date" value={form.bill_month} onChange={(e) => setForm({ ...form, bill_month: e.target.value })} /></div>
            <div className="space-y-2"><Label>关联住房</Label>
              <Select value={form.housing_id} onValueChange={(v) => setForm({ ...form, housing_id: v })}>
                <SelectTrigger><SelectValue placeholder="选择住房" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="">不关联</SelectItem>
                  {houses.map((h) => <SelectItem key={h.id} value={String(h.id)}>{h.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>类型 <span className="text-destructive">*</span></Label>
              <Select value={form.fee_type} onValueChange={(v) => setForm({ ...form, fee_type: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{feeTypes.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>金额 <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>到期日</Label><Input type="date" value={form.due_date} onChange={(e) => setForm({ ...form, due_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>状态</Label>
              <Select value={form.paid} onValueChange={(v) => setForm({ ...form, paid: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="false">待缴</SelectItem><SelectItem value="true">已缴</SelectItem></SelectContent>
              </Select>
            </div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUDialog(null)}>取消</Button>
            <Button onClick={saveUtility} disabled={saving}>{saving && <Loader2 className="animate-spin" />}保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}

/* ---------------- 服务订阅 ---------------- */

const cycleMeta: Record<string, string> = { month: '月付', quarter: '季付', year: '年付' }
const subStatusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '生效中', className: 'bg-green-100 text-green-700' },
  expired: { label: '已过期', className: 'bg-red-100 text-red-700' },
  cancelled: { label: '已取消', className: 'bg-gray-100 text-gray-600' },
}

type Subscription = {
  id: number
  name: string
  category: string
  billing_cycle: 'month' | 'quarter' | 'year'
  amount: number
  start_date: string
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

function SubscriptionTab() {
  const [items, setItems] = useState<Subscription[]>([])
  const [stats, setStats] = useState<SubStats | null>(null)
  const [dialog, setDialog] = useState<null | { editing?: Subscription }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Subscription>('/finance/subscriptions', { page_size: 100 })
    setItems(res.items)
    api.stats<SubStats>('/finance/subscriptions').then(setStats).catch(() => setStats(null))
  }
  useEffect(() => { load() }, [])

  const openCreate = () => {
    setForm({ name: '', category: '会员', billing_cycle: 'month', amount: '', start_date: new Date().toISOString().slice(0, 10), remind_days: '30', status: 'active', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      name: form.name, category: form.category, billing_cycle: form.billing_cycle,
      amount: Number(form.amount), start_date: form.start_date, remind_days: Number(form.remind_days),
      status: form.status, note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/subscriptions', dialog.editing.id, payload)
      else await api.create('/finance/subscriptions', payload)
      setDialog(null)
      await load()
    } finally {
      setSaving(false)
    }
  }
  const remove = async (s: Subscription) => {
    if (!(await confirm())) return
    await api.remove('/finance/subscriptions', s.id)
    await load()
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
          <Button onClick={openCreate}><Plus /> 新增订阅</Button>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>名称</TableHead><TableHead>分类</TableHead><TableHead>计费周期</TableHead>
                <TableHead className="text-right">金额</TableHead><TableHead>起始时间</TableHead><TableHead>提前提醒</TableHead><TableHead>状态</TableHead><TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="h-16 text-center text-muted-foreground">暂无订阅，点击"新增订阅"添加</TableCell></TableRow>
              ) : items.map((s) => (
                <TableRow key={s.id}>
                  <TableCell className="font-medium">{s.name}</TableCell>
                  <TableCell>{s.category}</TableCell>
                  <TableCell>{cycleMeta[s.billing_cycle] ?? s.billing_cycle}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(s.amount)}</TableCell>
                  <TableCell className="text-muted-foreground">{s.start_date}</TableCell>
                  <TableCell>提前 {s.remind_days} 天</TableCell>
                  <TableCell><Badge className={subStatusMeta[s.status]?.className}>{subStatusMeta[s.status]?.label ?? s.status}</Badge></TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button variant="ghost" size="icon" onClick={() => { setForm({ name: s.name, category: s.category, billing_cycle: s.billing_cycle, amount: String(s.amount), start_date: s.start_date, remind_days: String(s.remind_days), status: s.status, note: s.note ?? '' }); setDialog({ editing: s }) }}><Pencil /></Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(s)}><Trash2 /></Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
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
            <div className="space-y-2"><Label>分类 <span className="text-destructive">*</span></Label>
              <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {['会员', '服务器', '软件', '域名', '内容', '其他'].map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
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
            <div className="space-y-2"><Label>起始时间 <span className="text-destructive">*</span></Label><Input type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} /></div>
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
  paid_amount: number
  status: 'pending' | 'partial' | 'cleared'
  note?: string
}
type LoanBillStats = {
  total: number; paid: number; remaining: number
  status: { pending: number; partial: number; cleared: number }
  by_month: { month: string; amount: number }[]
  upcoming: { id: number; platform_id?: number; bill_month: string; due_date?: string; amount: number; paid_amount: number; remaining: number; status: string }[]
}
type Repayment = { id: number; bill_id?: number; repay_date: string; amount: number; method?: string; note?: string }

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
  const [repayments, setRepayments] = useState<Repayment[]>([])
  const [selectedBill, setSelectedBill] = useState<number | null>(null)

  const [pfDialog, setPfDialog] = useState(false)
  const [newPf, setNewPf] = useState<Record<string, string>>({})
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
    const res = await api.list<LoanBill>('/finance/loan-bills', { page_size: 100 })
    setBills(res.items)
    api.stats<LoanBillStats>('/finance/loan-bills').then(setBillStats).catch(() => null)
  }
  const loadRepayments = async (billId: number | null) => {
    if (!billId) { setRepayments([]); return }
    api.query<Repayment[]>(`/finance/repayments?bill_id=${billId}`).then(setRepayments).catch(() => setRepayments([]))
  }

  useEffect(() => {
    loadPlatforms()
    loadBills()
  }, [])
  useEffect(() => {
    loadRepayments(selectedBill)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedBill])

  const refresh = async () => {
    await loadBills()
    await loadPlatforms()
    if (selectedBill) await loadRepayments(selectedBill)
  }

  const platformName = (id?: number) => platforms.find((p) => p.id === id)?.name ?? '—'
  const addPlatform = async () => {
    const name = newPf.name?.trim()
    if (!name) return
    await api.create('/finance/loan-platforms', {
      name, bill_day: newPf.bill_day ? Number(newPf.bill_day) : null,
      due_day: newPf.due_day ? Number(newPf.due_day) : null,
      credit_limit: newPf.credit_limit ? Number(newPf.credit_limit) : null,
      note: newPf.note || null,
    })
    setNewPf({})
    await loadPlatforms()
  }
  const removePlatform = async (id: number) => {
    if (!(await confirm())) return
    await api.remove('/finance/loan-platforms', id)
    await loadPlatforms()
  }

  const openBillCreate = () => {
    setBillForm({ platform_id: platforms[0] ? String(platforms[0].id) : '', bill_month: new Date().toISOString().slice(0, 10), due_date: '', amount: '', paid_amount: '0', status: 'pending', note: '' })
    setBillDialog({})
  }
  const saveBill = async () => {
    const payload = {
      platform_id: billForm.platform_id ? Number(billForm.platform_id) : null,
      bill_month: billForm.bill_month, due_date: billForm.due_date || null,
      amount: Number(billForm.amount), paid_amount: Number(billForm.paid_amount || 0),
      status: billForm.status, note: billForm.note || null,
    }
    setSaving(true)
    try {
      if (billDialog?.editing) await api.update('/finance/loan-bills', billDialog.editing.id, payload)
      else await api.create('/finance/loan-bills', payload)
      setBillDialog(null)
      await refresh()
    } finally {
      setSaving(false)
    }
  }
  const removeBill = async (b: LoanBill) => {
    if (!(await confirm())) return
    await api.remove('/finance/loan-bills', b.id)
    if (selectedBill === b.id) setSelectedBill(null)
    await refresh()
  }

  const openRepay = (b: LoanBill) => {
    const remaining = b.amount - b.paid_amount
    setRepayForm({ repay_date: new Date().toISOString().slice(0, 10), amount: remaining > 0 ? String(remaining) : '', method: '', note: '' })
    setRepayDialog(b)
  }
  const submitRepay = async () => {
    if (!repayDialog) return
    const payload = {
      bill_id: repayDialog.id, repay_date: repayForm.repay_date,
      amount: Number(repayForm.amount), method: repayForm.method || null, note: repayForm.note || null,
    }
    setSaving(true)
    try {
      await api.create('/finance/repayments', payload)
      setRepayDialog(null)
      await refresh()
    } catch (e) {
      window.alert((e as Error).message)
    } finally {
      setSaving(false)
    }
  }
  const removeRepay = async (r: Repayment) => {
    if (!(await confirm())) return
    await api.remove('/finance/repayments', r.id)
    await refresh()
  }

  return (
    <div className="flex flex-col gap-4">
      {platformStats && (
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard icon={Wallet} label="累计待还" value={fmt(platformStats.total_remaining)} className="text-red-500" />
          <StatCard icon={Wallet} label="累计欠款" value={fmt(billStats?.total ?? 0)} hint={`已还 ${fmt(billStats?.paid ?? 0)}`} className="text-amber-500" />
          <StatCard icon={Layers} label="借款平台" value={`${platformStats.platform_count} 个`} />
          <StatCard icon={Banknote} label="待还账单" value={`${(billStats?.status.pending ?? 0) + (billStats?.status.partial ?? 0)} 笔`} hint={`${billStats?.by_month[0]?.month ?? ''} 到期数据`} className="text-indigo-500" />
        </section>
      )}

      {/* 借款平台 */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
          <CardTitle className="text-lg font-medium">借款平台</CardTitle>
          <Button size="sm" variant="outline" onClick={() => setPfDialog(true)}><Plus /> 管理平台</Button>
        </CardHeader>
        <CardContent className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {platformStats?.platforms.map((p) => (
            <div key={p.id} className="rounded-lg border p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="font-medium">{p.name}</span>
                <Badge variant="outline">额度 {p.credit_limit != null ? fmt(p.credit_limit) : '—'}</Badge>
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
          <Button onClick={openBillCreate}><Plus /> 新增账单</Button>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>平台</TableHead><TableHead>账单月份</TableHead><TableHead>到期日</TableHead>
                <TableHead className="text-right">欠款</TableHead><TableHead className="text-right">已还</TableHead><TableHead className="text-right">剩余</TableHead><TableHead>状态</TableHead><TableHead className="text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {bills.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="h-16 text-center text-muted-foreground">暂无账单</TableCell></TableRow>
              ) : bills.map((b) => {
                const remaining = b.amount - b.paid_amount
                return (
                  <TableRow key={b.id} className={selectedBill === b.id ? 'bg-blue-50/60' : ''}>
                    <TableCell onClick={() => setSelectedBill(selectedBill === b.id ? null : b.id)} className="cursor-pointer font-medium">{platformName(b.platform_id)}</TableCell>
                    <TableCell>{b.bill_month}</TableCell>
                    <TableCell className="text-muted-foreground">{b.due_date ?? '—'}</TableCell>
                    <TableCell className="text-right">{fmt(b.amount)}</TableCell>
                    <TableCell className="text-right text-green-600">{fmt(b.paid_amount)}</TableCell>
                    <TableCell className={`text-right font-medium ${remaining > 0 ? 'text-red-600' : ''}`}>{fmt(remaining)}</TableCell>
                    <TableCell><Badge className={billStatusMeta[b.status]?.className}>{billStatusMeta[b.status]?.label ?? b.status}</Badge></TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        {remaining > 0 && (
                          <Button variant="ghost" size="sm" onClick={() => openRepay(b)} title="还款/一次结清"><Banknote /></Button>
                        )}
                        <Button variant="ghost" size="icon" onClick={() => { setBillForm({ platform_id: b.platform_id ? String(b.platform_id) : '', bill_month: b.bill_month, due_date: b.due_date ?? '', amount: String(b.amount), paid_amount: String(b.paid_amount), status: b.status, note: b.note ?? '' }); setBillDialog({ editing: b }) }}><Pencil /></Button>
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
                <TableHead>还款日期</TableHead><TableHead className="text-right">金额</TableHead><TableHead>方式</TableHead><TableHead>备注</TableHead>
                {selectedBill && <TableHead className="w-16 text-right">操作</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {!selectedBill ? (
                <TableRow><TableCell colSpan={4} className="h-16 text-center text-muted-foreground">请选择账单查看还款记录</TableCell></TableRow>
              ) : repayments.length === 0 ? (
                <TableRow><TableCell colSpan={4} className="h-16 text-center text-muted-foreground">该账单暂无还款记录</TableCell></TableRow>
              ) : repayments.map((r) => (
                <TableRow key={r.id}>
                  <TableCell>{r.repay_date}</TableCell>
                  <TableCell className="text-right font-medium">{fmt(r.amount)}</TableCell>
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
          <DialogHeader><DialogTitle>{billDialog?.editing ? '编辑账单' : '新增账单'}</DialogTitle><DialogDescription>欠款金额已含利息，无需单独计算。</DialogDescription></DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2"><Label>平台 <span className="text-destructive">*</span></Label>
              <Select value={billForm.platform_id} onValueChange={(v) => setBillForm({ ...billForm, platform_id: v })}>
                <SelectTrigger><SelectValue placeholder="选择平台" /></SelectTrigger>
                <SelectContent>{platforms.map((p) => <SelectItem key={p.id} value={String(p.id)}>{p.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2"><Label>账单月份 <span className="text-destructive">*</span></Label><Input type="date" value={billForm.bill_month} onChange={(e) => setBillForm({ ...billForm, bill_month: e.target.value })} /></div>
            <div className="space-y-2"><Label>到期日</Label><Input type="date" value={billForm.due_date} onChange={(e) => setBillForm({ ...billForm, due_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>欠款(含利息) <span className="text-destructive">*</span></Label><Input type="number" min={0} step="0.01" value={billForm.amount} onChange={(e) => setBillForm({ ...billForm, amount: e.target.value })} /></div>
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
            <div className="space-y-2"><Label>还款日期 <span className="text-destructive">*</span></Label><Input type="date" value={repayForm.repay_date} onChange={(e) => setRepayForm({ ...repayForm, repay_date: e.target.value })} /></div>
            <div className="space-y-2"><Label>金额 <span className="text-destructive">*</span></Label><Input type="number" min={0.01} step="0.01" value={repayForm.amount} onChange={(e) => setRepayForm({ ...repayForm, amount: e.target.value })} /></div>
            <div className="space-y-2"><Label>还款方式</Label><Input value={repayForm.method} onChange={(e) => setRepayForm({ ...repayForm, method: e.target.value })} placeholder="银行卡/支付宝等" /></div>
            <div className="col-span-2 space-y-2"><Label>备注</Label><Textarea value={repayForm.note} onChange={(e) => setRepayForm({ ...repayForm, note: e.target.value })} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRepayDialog(null)}>取消</Button>
            <Button onClick={submitRepay} disabled={saving}>{saving && <Loader2 className="animate-spin" />}确认还款</Button>
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