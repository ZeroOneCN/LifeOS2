import { useEffect, useState } from 'react'
import { Check, Layers, Loader2, Pencil, Plus, Repeat, Trash2, Wallet, X } from 'lucide-react'

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
import { Tip } from '@/components/ui/tip'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { toast } from 'sonner'

import { fmt } from './shared'
import { StatCard } from './stat-card'

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
  active: { label: '生效中', className: 'bg-success-muted text-success-muted-foreground' },
  expired: { label: '已过期', className: 'bg-danger-muted text-danger-muted-foreground' },
  cancelled: { label: '已取消', className: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400' },
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
  status: 'active' | 'expired' | 'cancelled'
  note?: string
}
type SubStats = {
  total_active: number
  active_count: number
  total_count: number
  by_category: { category: string; amount: number }[]
  upcoming: { id: number; name: string; category: string; amount: number; next_renewal: string }[]
}
type SubCategory = { id: number; name: string }

export function SubscriptionTab() {
  const realtimeTick = useRealtime(30_000)
  const [items, setItems] = useState<Subscription[]>([])
  const [stats, setStats] = useState<SubStats | null>(null)
  const [categories, setCategories] = useState<SubCategory[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Subscription }>(null)
  const [catDialog, setCatDialog] = useState(false)
  const [newCategory, setNewCategory] = useState('')
  const [catEditId, setCatEditId] = useState<number | null>(null)
  const [catEditName, setCatEditName] = useState('')
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Subscription>('/finance/subscriptions', { page_size: 100 })
    setItems(res.items)
    try { setStats(await api.stats<SubStats>('/finance/subscriptions')) }
    catch { setStats(null) }
  }
  const loadCategories = async () => {
    api.list<SubCategory>('/finance/subscription-categories', { page_size: 100 }).then((res) => setCategories(res.items)).catch(() => setCategories([]))
  }
  useEffect(() => { load(); loadCategories() }, [realtimeTick])

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
      toast.error('删除失败', { description: e instanceof Error ? e.message : '请稍后重试' })
    }
  }
  const startEditCat = (c: SubCategory) => {
    setCatEditId(c.id)
    setCatEditName(c.name)
  }
  const saveCatEdit = async () => {
    if (catEditId == null) return
    const name = catEditName.trim()
    if (!name) { setCatEditId(null); return }
    try {
      await api.update('/finance/subscription-categories', catEditId, { name })
      setCatEditId(null)
      await loadCategories()
      toast.success('订阅分类已更新')
    } catch (e) {
      toast.error('更新失败', { description: e instanceof Error ? e.message : '请稍后重试' })
    }
  }

  const openCreate = () => {
    setForm({ name: '', plan_name: '', category: categories[0]?.name ?? '会员', billing_cycle: 'month', amount: '', start_date: new Date().toISOString().slice(0, 10), end_date: '', auto_renew: 'false', status: 'active', note: '' })
    setDialog({})
  }
  const save = async () => {
    const payload = {
      name: form.name, plan_name: form.plan_name || null, category: form.category, billing_cycle: form.billing_cycle,
      amount: Number(form.amount), start_date: form.start_date, end_date: form.end_date || null,
      auto_renew: form.auto_renew === 'true',
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
            <StatCard icon={Repeat} label="即将续费" value={`${stats.upcoming.length} 项`} hint={stats.upcoming[0] ? `最近 ${stats.upcoming[0].next_renewal}` : '近期无续费'} className="text-warning" />
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
            <Card className="border-warning/40 bg-warning-muted">
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium text-warning-muted-foreground">即将续费提醒</CardTitle></CardHeader>
              <CardContent className="space-y-1.5 text-sm">
                {stats.upcoming.map((u) => (
                  <div key={u.id} className="flex flex-wrap items-center justify-between rounded-md bg-white/70 dark:bg-white/5 px-3 py-1.5">
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
        <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
          <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">服务订阅</CardTitle>
          <CardHeaderActions>
            <Button size="sm" variant="outline" onClick={() => { setNewCategory(''); setCatDialog(true) }}><Layers className="size-4" /> 分类设置</Button>
            <Button onClick={openCreate}><Plus /> 新增订阅</Button>
          </CardHeaderActions>
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
                  <TableCell>{s.auto_renew ? <Badge className="bg-success-muted text-success-muted-foreground">是</Badge> : <Badge variant="outline">否</Badge>}</TableCell>
                  <TableCell><Badge className={subStatusMeta[s.status]?.className}>{subStatusMeta[s.status]?.label ?? s.status}</Badge></TableCell>
                  <Tip label={s.note ?? ''}><TableCell className="max-w-[160px] truncate text-muted-foreground">{s.note ?? '—'}</TableCell></Tip>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setForm({ name: s.name, plan_name: s.plan_name ?? '', category: s.category, billing_cycle: s.billing_cycle, amount: String(s.amount), start_date: s.start_date, end_date: s.end_date ?? '', auto_renew: s.auto_renew ? 'true' : 'false', status: s.status, note: s.note ?? '' }); setDialog({ editing: s }) }}><Pencil /></Button></Tip>
                      <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(s)}><Trash2 /></Button></Tip>
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
                <div key={c.id} className="flex items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm">
                  {catEditId === c.id ? (
                    <>
                      <Input value={catEditName} onChange={(e) => setCatEditName(e.target.value)} autoFocus
                        onKeyDown={(e) => e.key === 'Enter' && saveCatEdit()} className="min-w-0 flex-1" />
                      <div className="flex shrink-0 gap-0.5">
                        <Tip label="保存"><Button size="icon" variant="ghost" onClick={saveCatEdit}><Check /></Button></Tip>
                        <Tip label="取消"><Button size="icon" variant="ghost" onClick={() => setCatEditId(null)}><X /></Button></Tip>
                      </div>
                    </>
                  ) : (
                    <>
                      <span className="min-w-0 flex-1 truncate">{c.name}</span>
                      <div className="flex shrink-0 gap-0.5">
                        <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => startEditCat(c)}><Pencil /></Button></Tip>
                        <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeCategory(c)}><Trash2 /></Button></Tip>
                      </div>
                    </>
                  )}
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
