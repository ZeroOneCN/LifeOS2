import { useEffect, useState, type ReactNode } from 'react'
import { ChevronLeft, ChevronRight, Loader2, Pencil, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'

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
import { PaginationBar } from '@/components/ui/pagination-bar'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api, type ListParams } from '@/lib/api'

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
  /** 启用按「账单月」分页（仿网贷账单），按 monthField 的月份过滤，头部提供 ‹ › » 翻页 */
  monthMode?: boolean
  /** monthMode 生效时用于过滤的日期字段 */
  monthField?: string
  /** CRUD 成功后回调（新增/编辑/删除），用于页面同步刷新统计图表 */
  onMutate?: () => void
}

const PAGE_SIZE = 10

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
  monthMode,
  monthField = 'reminder_date',
  onMutate,
}: RecordManagerProps<T>) {
  const [items, setItems] = useState<T[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<T | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})
  const [month, setMonth] = useState(() => {
    const n = new Date()
    return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`
  })

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条记录吗？此操作不可恢复。',
  })

  const shiftMonth = (m: string, delta: number) => {
    const [y, mm] = m.split('-').map(Number)
    const dt = new Date(y, mm - 1 + delta, 1)
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`
  }
  const jumpMonth = (m: string) => {
    setMonth(m)
    setPage(1)
  }

  const load = async () => {
    // 翻页/刷新时保留旧数据渲染（仅首载显示加载占位），避免高度变化引起抖动
    setLoading(true)
    try {
      const params: ListParams = { page, page_size: PAGE_SIZE }
      if (monthMode) {
        const [yy, mm] = month.split('-').map(Number)
        const last = String(new Date(yy, mm, 0).getDate()).padStart(2, '0')
        params.start = `${month}-01`
        params.end = `${month}-${last}`
      }
      const res = await api.list<T>(apiPath, params)
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, refreshKey, month])

  const openCreate = () => {
    setEditing(null)
    const initial: Record<string, string> = Object.fromEntries(fields.map((f) => [f.key, '']))
    if (monthMode && fields.some((f) => f.key === monthField)) {
      initial[monthField] = `${month}-01`
    }
    setForm(initial)
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
        // 未选择时不上送，避免覆盖后端默认值
        if (raw === 'true' || raw === 'false') payload[field.key] = raw === 'true'
      } else if (field.type === 'select') {
        // 未选择时不上送，让后端使用默认值
        if (raw !== '') payload[field.key] = raw
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
      if (editing) {
        // 编辑保存后停留在当前页，避免跳回第一页
        await load()
      } else {
        setPage(1)
        await load()
      }
      onMutate?.()
      toast.success(editing ? '记录已更新' : '记录已添加')
    } catch (e) {
      toast.error(editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: T) => {
    if (!(await confirm())) return
    try {
      await api.remove(apiPath, row.id)
      if (items.length === 1 && page > 1) setPage(page - 1)
      else await load()
      onMutate?.()
      toast.success('记录已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
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
          {monthMode ? (
            <div className="flex items-center gap-1 rounded-lg border p-1">
              <Button variant="ghost" size="icon" className="h-7 w-7" title="上一月" onClick={() => jumpMonth(shiftMonth(month, -1))}><ChevronLeft /></Button>
              <span className="min-w-[72px] text-center text-sm font-medium">{month}</span>
              <Button variant="ghost" size="icon" className="h-7 w-7" title="下一月" onClick={() => jumpMonth(shiftMonth(month, 1))}><ChevronRight /></Button>
              <Button variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={() => { const n = new Date(); jumpMonth(`${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`) }}>当月</Button>
            </div>
          ) : null}
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
            <TableBody
              className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}
            >
              {items.length === 0 ? (
                loading ? (
                  <TableRow>
                    <TableCell
                      colSpan={columns.length + 1}
                      className="h-24 text-center text-muted-foreground"
                    >
                      <Loader2 className="mx-auto size-5 animate-spin" />
                    </TableCell>
                  </TableRow>
                ) : (
                  <TableRow>
                    <TableCell
                      colSpan={columns.length + 1}
                      className="h-24 text-center text-muted-foreground"
                    >
                      暂无记录，点击"新增记录"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
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

      <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />

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
                ) : field.type === 'date' ? (
                  <DatePicker
                    id={field.key}
                    value={form[field.key] ?? ''}
                    onChange={(v) => setForm((f) => ({ ...f, [field.key]: v }))}
                    placeholder={field.placeholder ?? '选择日期'}
                  />
                ) : (
                  <Input
                    id={field.key}
                    type={field.type === 'number' ? 'number' : field.type === 'time' ? 'time' : field.type === 'datetime' ? 'datetime-local' : 'text'}
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
