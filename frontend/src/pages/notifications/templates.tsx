import { useCallback, useEffect, useState } from 'react'
import { Loader2, Pencil, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
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
import { api } from '@/lib/api'

type Tpl = {
  id: number
  source: string
  category: string
  name: string
  title_template: string
  content_template: string
  is_default: boolean
  note?: string | null
}

const VARIABLES = ['{name}', '{amount}', '{due_date}', '{days_left}', '{category}', '{status}', '{platform}', '{priority}']

export function TemplatesPanel() {
  const [items, setItems] = useState<Tpl[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<Tpl | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ title_template: string; content_template: string }>({
    title_template: '',
    content_template: '',
  })

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const rows = await api.query<Tpl[]>('/notifications/templates')
      setItems(rows)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const openEdit = (t: Tpl) => {
    setEditing(t)
    setForm({ title_template: t.title_template, content_template: t.content_template })
    setOpen(true)
  }

  const save = async () => {
    if (!editing) return
    setSaving(true)
    try {
      await api.put(`/notifications/templates/${editing.id}`, {
        name: editing.name,
        title_template: form.title_template,
        content_template: form.content_template,
      })
      toast.success('模板已保存')
      setOpen(false)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const reset = async (t: Tpl) => {
    await api.post(`/notifications/templates/${t.id}/reset`)
    toast.success('模板已重置为默认')
    await load()
  }

  const insertVar = (v: string) =>
    setForm((f) => ({ ...f, content_template: f.content_template + v }))

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        各提醒功能的默认通知模板，支持 {VARIABLES.join(' ')} 等占位变量，创建提醒时自动替换为实际值。
      </p>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {items.map((t) => (
            <Card key={t.id}>
              <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2">
                <div>
                  <CardTitle className="text-sm font-medium">{t.name}</CardTitle>
                  <CardDescription>{t.source}</CardDescription>
                </div>
                <Badge className="bg-blue-100 text-blue-700">{t.category}</Badge>
              </CardHeader>
              <CardContent className="space-y-2">
                <p className="text-sm">
                  <span className="text-muted-foreground">标题：</span>
                  {t.title_template}
                </p>
                <p className="line-clamp-3 whitespace-pre-wrap rounded bg-muted/40 p-2 text-xs text-muted-foreground">
                  {t.content_template}
                </p>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">
                    {t.is_default ? '系统默认' : '已自定义'}
                  </span>
                  <div className="flex gap-1">
                    <Button variant="ghost" size="icon" onClick={() => openEdit(t)} title="编辑模板">
                      <Pencil />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => reset(t)}
                      title="重置为默认"
                      className="text-destructive"
                    >
                      <RotateCcw />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>编辑模板 · {editing?.name}</DialogTitle>
            <DialogDescription>可使用占位变量，插入到内容末尾。</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="t-title">标题模板</Label>
              <Input
                id="t-title"
                value={form.title_template}
                onChange={(e) => setForm((f) => ({ ...f, title_template: e.target.value }))}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="t-content">内容模板</Label>
              <Textarea
                id="t-content"
                rows={6}
                value={form.content_template}
                onChange={(e) => setForm((f) => ({ ...f, content_template: e.target.value }))}
              />
              <div className="flex flex-wrap gap-1">
                {VARIABLES.map((v) => (
                  <Button
                    key={v}
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => insertVar(v)}
                  >
                    {v}
                  </Button>
                ))}
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              取消
            </Button>
            <Button onClick={save} disabled={saving}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}