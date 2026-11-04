import { useEffect, useState } from 'react'
import { ArrowDownCircle, ArrowUpCircle, Loader2, Pencil, Plus, Trash2, Wallet } from 'lucide-react'
import { toast } from 'sonner'

import { useRealtime } from '@/hooks/use-realtime'
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
import { Tip } from '@/components/ui/tip'
import { api } from '@/lib/api'

import { investCategories } from './shared'
import { StatCard } from './stat-card'

/* ---------------- 投资记账 ---------------- */

type Investment = { id: number; platform: string; account?: string; category: string; pnl: number; note?: string }
type InvStats = { count: number; total_pnl: number; profit: number; loss: number; by_category: { category: string; amount: number }[]; by_platform: { platform: string; amount: number }[] }

export function InvestTab() {
  // 投资记账统一按美元计算与显示，不做汇率换算
  const usd = (n: number) => `$${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
  const realtimeTick = useRealtime(30_000)
  const [items, setItems] = useState<Investment[]>([])
  const [stats, setStats] = useState<InvStats | null>(null)
  const [dialog, setDialog] = useState<null | { editing?: Investment }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [selCats, setSelCats] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Investment>('/finance/investments', { page_size: 100 })
    setItems(res.items)
    api.stats<InvStats>('/finance/investments').then(setStats).catch(() => setStats(null))
  }
  useEffect(() => { load() }, [realtimeTick])

  const toggleCat = (c: string) => {
    setSelCats((prev) => (prev.includes(c) ? prev.filter((x) => x !== c) : [...prev, c]))
  }
  const openCreate = () => {
    setForm({ platform: '', account: '', pnl: '', note: '' })
    setSelCats([])
    setDialog({})
  }
  const save = async () => {
    const payload = {
      platform: form.platform, account: form.account || null, category: selCats.join(',') || investCategories[0],
      pnl: Number(form.pnl), note: form.note || null,
    }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/investments', dialog.editing.id, payload)
      else await api.create('/finance/investments', payload)
      setDialog(null)
      await load()
      toast.success(dialog?.editing ? '投资记录已更新' : '投资记录已添加')
    } catch (e) {
      toast.error(dialog?.editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const remove = async (iv: Investment) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/investments', iv.id)
      await load()
      toast.success('投资记录已删除')
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
            <StatCard icon={Wallet} label="投资平台数" value={`${stats.count} 个`} />
            <StatCard icon={ArrowUpCircle} label="整体盈亏" value={usd(stats.total_pnl)} className={stats.total_pnl >= 0 ? 'text-success' : 'text-danger'} />
            <StatCard icon={ArrowUpCircle} label="盈利合计" value={usd(stats.profit)} className="text-success" />
            <StatCard icon={ArrowDownCircle} label="亏损合计" value={usd(stats.loss)} className="text-danger" />
          </section>
          {stats.by_category.length > 0 && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-sm font-medium">按投资类别盈亏</CardTitle></CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {stats.by_category.map((c) => (
                    <Badge key={c.category} variant="outline">
                      {c.category}：<span className={c.amount >= 0 ? 'text-success' : 'text-danger'}>{usd(c.amount)}</span>
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
          <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
            <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">投资平台记账</CardTitle>
            <CardHeaderActions>
              <Button onClick={openCreate}><Plus /> 新增投资</Button>
            </CardHeaderActions>
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
                  <TableCell className="max-w-[200px]">
                    <div className="flex flex-wrap gap-1">
                      {iv.category.split(',').filter((c) => c.trim()).map((c) => <Badge key={c} variant="outline">{c.trim()}</Badge>)}
                    </div>
                  </TableCell>
                  <TableCell className={`text-right font-medium ${iv.pnl >= 0 ? 'text-success' : 'text-danger'}`}>{usd(iv.pnl)}</TableCell>
                  <Tip label={iv.note ?? ''}><TableCell className="max-w-[160px] truncate text-muted-foreground">{iv.note ?? '—'}</TableCell></Tip>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setForm({ platform: iv.platform, account: iv.account ?? '', pnl: String(iv.pnl), note: iv.note ?? '' }); setSelCats(iv.category.split(',').map((s) => s.trim()).filter(Boolean)); setDialog({ editing: iv }) }}><Pencil /></Button></Tip>
                      <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(iv)}><Trash2 /></Button></Tip>
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
            <div className="col-span-2 space-y-2"><Label>类别 *（可多选）</Label>
              <div className="flex flex-wrap gap-2">
                {investCategories.map((c) => {
                  const on = selCats.includes(c)
                  return (
                    <button type="button" key={c} onClick={() => toggleCat(c)}
                      className={`rounded-full border px-3 py-1 text-sm transition-colors ${on ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-background text-muted-foreground hover:bg-muted'}`}>
                      {c}
                    </button>
                  )
                })}
              </div>
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
