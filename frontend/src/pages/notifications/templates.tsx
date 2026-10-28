import { useCallback, useEffect, useState } from 'react'
import { Loader2, Pencil, RotateCcw } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
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
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { getCategoryStyle, getSourceLabel } from './types'

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
  const realtimeTick = useRealtime()
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
  }, [load, realtimeTick])

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
            <Card key={t.id} className="flex h-full flex-col">
              <CardHeader className="pb-0">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0 space-y-1.5">
                    <CardTitle className="text-sm leading-snug font-medium">{t.name}</CardTitle>
                    <div className="flex flex-wrap items-center gap-1.5">
                      <Badge className={getCategoryStyle(t.category)}>{t.category}</Badge>
                      <span className="text-xs text-muted-foreground">{getSourceLabel(t.source)}</span>
                    </div>
                  </div>
                  <Badge
                    className={
                      t.is_default
                        ? 'bg-muted text-muted-foreground'
                        : 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300'
                    }
                  >
                    {t.is_default ? '系统默认' : '已自定义'}
                  </Badge>
                </div>
              </CardHeader>

              <CardContent className="flex-1 space-y-3">
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">标题</p>
                  <p className="text-sm leading-relaxed break-words">{t.title_template}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground">内容</p>
                  <p className="line-clamp-3 rounded-md bg-muted/40 px-2.5 py-2 text-xs leading-relaxed whitespace-pre-wrap text-muted-foreground">
                    {t.content_template}
                  </p>
                </div>
              </CardContent>

              <CardFooter className="justify-end gap-1.5 py-2.5">
                <Button variant="outline" size="sm" onClick={() => openEdit(t)}>
                  <Pencil />
                  编辑
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => reset(t)}
                  className="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  <RotateCcw />
                  重置
                </Button>
              </CardFooter>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent
          className="max-h-[85vh] overflow-y-auto sm:max-w-lg"
          onInteractOutside={(e) => e.preventDefault()}
          onEscapeKeyDown={(e) => e.preventDefault()}
        >
          <DialogHeader>
            <DialogTitle>编辑模板 · {editing?.name}</DialogTitle>
            <DialogDescription>可使用占位变量，点击下方按钮插入到内容末尾。</DialogDescription>
          </DialogHeader>
          <div className="space-y-5">
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
                className="leading-relaxed"
                value={form.content_template}
                onChange={(e) => setForm((f) => ({ ...f, content_template: e.target.value }))}
              />
              <div className="flex flex-wrap gap-1.5 pt-0.5">
                {VARIABLES.map((v) => (
                  <Button
                    key={v}
                    type="button"
                    variant="secondary"
                    size="xs"
                    className="font-mono"
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