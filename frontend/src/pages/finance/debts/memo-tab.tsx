import { useEffect, useState } from 'react'
import { Loader2, Pencil, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'

import { useRealtime } from '@/hooks/use-realtime'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { DatePicker } from '@/components/ui/date-picker'
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
import { Textarea } from '@/components/ui/textarea'
import { Tip } from '@/components/ui/tip'
import { api } from '@/lib/api'

/* ---------------- 备忘录 ---------------- */

type Memo = { id: number; title: string; content?: string; memo_date?: string }

export function MemoTab() {
  const realtimeTick = useRealtime(30_000)
  const [items, setItems] = useState<Memo[]>([])
  const [dialog, setDialog] = useState<null | { editing?: Memo }>(null)
  const [form, setForm] = useState<Record<string, string>>({})
  const [saving, setSaving] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这条记录吗？此操作不可恢复。' })

  const load = async () => {
    const res = await api.list<Memo>('/finance/memos', { page_size: 100 })
    setItems(res.items)
  }
  useEffect(() => { load() }, [realtimeTick])

  const openCreate = () => { setForm({ title: '', content: '', memo_date: new Date().toISOString().slice(0, 10) }); setDialog({}) }
  const save = async () => {
    const payload = { title: form.title, content: form.content || null, memo_date: form.memo_date || null }
    setSaving(true)
    try {
      if (dialog?.editing) await api.update('/finance/memos', dialog.editing.id, payload)
      else await api.create('/finance/memos', payload)
      setDialog(null)
      await load()
      toast.success(dialog?.editing ? '备忘已更新' : '备忘已添加')
    } catch (e) {
      toast.error(dialog?.editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }
  const remove = async (m: Memo) => {
    if (!(await confirm())) return
    try {
      await api.remove('/finance/memos', m.id)
      await load()
      toast.success('备忘已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardContent className="p-0">
          <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-3">
            <CardTitle className="text-lg font-medium min-w-0 max-w-[55%] truncate">备忘录（模糊记忆）</CardTitle>
            <CardHeaderActions>
              <Button onClick={openCreate}><Plus /> 新增备忘</Button>
            </CardHeaderActions>
          </CardHeader>
          <div className="grid gap-2 p-4 grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-6">
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
                    <Tip label="编辑"><Button variant="ghost" size="icon" onClick={() => { setForm({ title: m.title, content: m.content ?? '', memo_date: m.memo_date ?? '' }); setDialog({ editing: m }) }}><Pencil /></Button></Tip>
                    <Tip label="删除"><Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(m)}><Trash2 /></Button></Tip>
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
            <div className="space-y-2"><Label>日期</Label><DatePicker value={form.memo_date} onChange={(v) => setForm({ ...form, memo_date: v })} /></div>
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
