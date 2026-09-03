import { useEffect, useState, type ReactNode } from 'react'
import { Loader2, Pencil, Plus, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
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
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'

export type FieldType = 'date' | 'time' | 'datetime' | 'number' | 'text' | 'textarea' | 'select' | 'boolean'

export type FieldDef = {
  key: string
  label: string
  type: FieldType
  required?: boolean
  options?: { value: string; label: string }[]
  placeholder?: string
  step?: string
  min?: number
  /** 占据整行（多用于 textarea） */
  full?: boolean
}

export type ColumnDef<T> = {
  key: string
  label: string
  render?: (row: T) => ReactNode
  className?: string
}

type RecordManagerProps<T extends { id: number }> = {
  title: string
  description: string
  apiPath: string
  fields: FieldDef[]
  columns: ColumnDef<T>[]
  /** 列表上方附加内容（如统计图表） */
  extra?: ReactNode
  /** 头部右侧、新增按钮旁的自定义内容（如同步入口） */
  headerExtra?: ReactNode
  /** 每行操作列中间的自定义行内操作（渲染在编辑之前） */
  rowActions?: (row: T) => ReactNode
  /** 变化时重新拉取列表（用于外部操作后刷新） */
  refreshKey?: number
  /** 隐藏内置标题区（主标题已由页面统一在 Tab 上方展示），仅保留右侧操作按钮 */
  hideHeader?: boolean
}

const PAGE_SIZE = 20

function toFormValue(field: FieldDef, value: unknown): string {
  if (value === null || value === undefined) return ''
  if (field.type === 'boolean') return value ? 'true' : 'false'
  if (field.type === 'time') return String(value).slice(0, 5)
  return String(value)
}

export function RecordManager<T extends { id: number }>({
  title,
  description,
  apiPath,
  fields,
  columns,
  extra,
  headerExtra,
  rowActions,
  refreshKey,
  hideHeader,
}: RecordManagerProps<T>) {
  const [items, setItems] = useState<T[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<T | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条记录吗？此操作不可恢复。',
  })

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<T>(apiPath, { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, refreshKey])

  const openCreate = () => {
    setEditing(null)
    setForm(Object.fromEntries(fields.map((f) => [f.key, ''])))
    setDialogOpen(true)
  }

  const openEdit = (row: T) => {
    setEditing(row)
    setForm(Object.fromEntries(fields.map((f) => [f.key, toFormValue(f, (row as Record<string, unknown>)[f.key])])))
    setDialogOpen(true)
  }

  const submit = async () => {
    const payload: Record<string, unknown> = {}
    for (const field of fields) {
      const raw = form[field.key] ?? ''
      if (field.type === 'number') {
        payload[field.key] = raw === '' ? null : Number(raw)
      } else if (field.type === 'boolean') {
        payload[field.key] = raw === 'true'
      } else {
        payload[field.key] = raw === '' ? null : raw
      }
    }
    setSaving(true)
    try {
      if (editing) {
        await api.update(apiPath, editing.id, payload)
      } else {
        await api.create(apiPath, payload)
      }
      setDialogOpen(false)
      if (editing && page === 1) await load()
      else {
        setPage(1)
        await load()
      }
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: T) => {
    if (!(await confirm())) return
    await api.remove(apiPath, row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  return (
    <div className="flex flex-col gap-4">
      <section className={`flex flex-wrap items-end gap-3 ${hideHeader ? 'justify-end' : 'justify-between'}`}>
        {!hideHeader && (
          <div className="space-y-1">
            <h1 className="font-heading text-2xl font-semibold tracking-tight">
              {title}
            </h1>
            <p className="text-sm text-muted-foreground">{description}</p>
          </div>
        )}
        <div className="flex items-center gap-2">
          {headerExtra}
          <Button onClick={openCreate}>
            <Plus /> 新增记录
          </Button>
        </div>
      </section>

      {extra}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                {columns.map((col) => (
                  <TableHead key={col.key} className={col.className}>
                    {col.label}
                  </TableHead>
                ))}
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loading ? (
                <TableRow>
                  <TableCell
                    colSpan={columns.length + 1}
                    className="h-24 text-center text-muted-foreground"
                  >
                    <Loader2 className="mx-auto size-5 animate-spin" />
                  </TableCell>
                </TableRow>
              ) : items.length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={columns.length + 1}
                    className="h-24 text-center text-muted-foreground"
                  >
                    暂无记录，点击"新增记录"添加第一条数据
                  </TableCell>
                </TableRow>
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    {columns.map((col) => (
                      <TableCell key={col.key} className={col.className}>
                        {col.render ? col.render(row) : String((row as Record<string, unknown>)[col.key] ?? '')}
                      </TableCell>
                    ))}
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        {rowActions?.(row)}
                        <Button variant="ghost" size="icon" onClick={() => openEdit(row)}>
                          <Pencil />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-destructive"
                          onClick={() => remove(row)}
                        >
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <div className="flex items-center justify-between text-sm text-muted-foreground">
        <span>
          共 {total} 条记录
        </span>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => setPage(page - 1)}
          >
            上一页
          </Button>
          <span>
            {page} / {totalPages}
          </span>
          <Button
            variant="outline"
            size="sm"
            disabled={page >= totalPages}
            onClick={() => setPage(page + 1)}
          >
            下一页
          </Button>
        </div>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑记录' : '新增记录'}</DialogTitle>
            <DialogDescription>
              {editing ? '修改并保存本条记录。' : '填写以下信息创建一条新记录。'}
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            {fields.map((field) => (
              <div key={field.key} className={`space-y-2 ${field.full ? 'col-span-2' : ''}`}>
                <Label htmlFor={field.key}>
                  {field.label}
                  {field.required && <span className="text-destructive"> *</span>}
                </Label>
                {field.type === 'select' || field.type === 'boolean' ? (
                  <Select
                    value={form[field.key] ?? ''}
                    onValueChange={(v) => setForm((f) => ({ ...f, [field.key]: v }))}
                  >
                    <SelectTrigger id={field.key}>
                      <SelectValue placeholder={`请选择${field.label}`} />
                    </SelectTrigger>
                    <SelectContent>
                      {(field.options ?? []).map((opt) => (
                        <SelectItem key={opt.value} value={opt.value}>
                          {opt.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : field.type === 'textarea' ? (
                  <Textarea
                    id={field.key}
                    value={form[field.key] ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, [field.key]: e.target.value }))}
                    placeholder={field.placeholder}
                  />
                ) : (
                  <Input
                    id={field.key}
                    type={field.type === 'number' ? 'number' : field.type === 'date' ? 'date' : field.type === 'time' ? 'time' : field.type === 'datetime' ? 'datetime-local' : 'text'}
                    step={field.step}
                    min={field.min}
                    value={form[field.key] ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, [field.key]: e.target.value }))}
                    placeholder={field.placeholder}
                  />
                )}
              </div>
            ))}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={submit} disabled={saving}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}
