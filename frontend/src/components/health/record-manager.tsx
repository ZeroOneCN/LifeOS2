import { useEffect, useState, useCallback, type ReactNode } from 'react'
import { ChevronLeft, ChevronRight, Download, Loader2, Pencil, Plus, Search, Trash2, X } from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Skeleton } from '@/components/ui/skeleton'
import { useRecordList } from '@/hooks/use-record-list'
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
  /** 启用按「账单月」分页（仿网贷账单），按月份过滤，头部提供 ‹ › » 翻页 */
  monthMode?: boolean
  /** CRUD 成功后回调（新增/编辑/删除），用于页面同步刷新统计图表 */
  onMutate?: () => void
  /** 启用批量选择模式，表格首列渲染 checkbox */
  enableBatch?: boolean
  /** 批量操作工具栏，选中项目后显示在表格上方 */
  batchToolbar?: (selectedIds: number[], clearSelection: () => void) => ReactNode
  /** 是否启用关键字搜索（配合后端 search_text 全局模糊搜索） */
  searchable?: boolean
  /** 搜索框占位提示 */
  searchPlaceholder?: string
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
  onMutate,
  enableBatch = false,
  batchToolbar,
  searchable = false,
  searchPlaceholder = '搜索…',
}: RecordManagerProps<T>) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<T | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set())

  // 列表加载逻辑统一委托给 useRecordList Hook（分页/月份过滤/搜索/实时刷新）
  const { items, total, page, setPage, loading, month, setMonth, keyword, setKeyword, load } =
    useRecordList<T>({
      apiPath,
      pageSize: PAGE_SIZE,
      monthMode,
      searchable,
      refreshKey,
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

  // 翻页时清空选择
  useEffect(() => {
    setSelectedIds(new Set())
  }, [page])

  const allVisibleSelected = enableBatch && items.length > 0 && items.every((r) => selectedIds.has(r.id))
  const someVisibleSelected = enableBatch && items.length > 0 && !allVisibleSelected && items.some((r) => selectedIds.has(r.id))

  const clearSelection = useCallback(() => setSelectedIds(new Set()), [])

  const toggleAll = () => {
    if (allVisibleSelected) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(items.map((r) => r.id)))
    }
  }

  const toggleOne = (id: number) => {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const batchColSpan = enableBatch ? 1 : 0

  /** 批量删除选中项：调用后端批量删除接口，成功后清空选择并刷新。 */
  const batchRemove = async () => {
    if (!(await confirm({
      title: '批量删除',
      description: `确定删除选中的 ${selectedIds.size} 条记录吗？此操作不可恢复。`,
    }))) return
    try {
      await api.batchRemove(apiPath, [...selectedIds])
      setSelectedIds(new Set())
      // 删除后若当前页为空且非首页，回退一页
      if (items.length === selectedIds.size && page > 1) setPage(page - 1)
      else await load()
      onMutate?.()
      toast.success(`已删除 ${selectedIds.size} 条记录`)
    } catch (e) {
      toast.error('批量删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  /** 导出当前筛选条件下的全部记录为 CSV 文件（上限 10000 条，超限提示）。 */
  const exportCsv = async () => {
    try {
      const params: Parameters<typeof api.list>[1] = { page: 1, page_size: 10000 }
      if (monthMode) {
        const [yy, mm] = month.split('-').map(Number)
        const last = new Date(yy, mm, 0).getDate()
        params.start = `${month}-01`
        params.end = `${month}-${String(last).padStart(2, '0')}`
      }
      if (searchable && keyword.trim()) {
        params.extra = { search_text: keyword.trim() }
      }
      const res = await api.list<T>(apiPath, params)
      if (!res.items.length) {
        toast.info('没有可导出的数据')
        return
      }
      // 数据量超 10000 条时提示用户仅导出了前 10000 条
      if (res.total > 10000) {
        toast.warning(`数据共 ${res.total} 条，仅导出前 10000 条`, {
          description: '请缩小筛选范围后分批导出',
        })
      }
      const headers = columns.map((c) => c.key)
      const headerLabel = columns.map((c) => c.label)
      const rows = res.items.map((item) =>
        headers.map((h) => {
          const val = (item as Record<string, unknown>)[h]
          const s = val === null || val === undefined ? '' : String(val)
          // CSV 转义：含逗号/引号/换行时用双引号包裹，内部引号转义
          return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
        }).join(','),
      )
      const csv = '\uFEFF' + [headerLabel.join(','), ...rows].join('\n')
      const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${title}_${new Date().toISOString().slice(0, 10)}.csv`
      a.click()
      URL.revokeObjectURL(url)
      toast.success(`已导出 ${res.items.length} 条记录`)
    } catch (e) {
      toast.error('导出失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const openCreate = () => {
    setEditing(null)
    const initial: Record<string, string> = Object.fromEntries(fields.map((f) => [f.key, '']))
    if (monthMode) {
      // monthMode 下查找第一个日期类型字段并默认填充当月1日
      const dateField = fields.find((f) => f.type === 'date')
      if (dateField) {
        initial[dateField.key] = `${month}-01`
      }
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
              <Button variant="ghost" size="icon" className="h-7 w-7" title="上一月" onClick={() => setMonth(shiftMonth(month, -1))}><ChevronLeft /></Button>
              <span className="min-w-[72px] text-center text-sm font-medium">{month}</span>
              <Button variant="ghost" size="icon" className="h-7 w-7" title="下一月" onClick={() => setMonth(shiftMonth(month, 1))}><ChevronRight /></Button>
              <Button variant="outline" size="sm" className="h-7 px-2 text-xs" onClick={() => { const n = new Date(); setMonth(`${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`) }}>当月</Button>
            </div>
          ) : null}
          {searchable && (
            <div className="relative">
              <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={keyword}
                onChange={(e) => setKeyword(e.target.value)}
                placeholder={searchPlaceholder}
                className="h-9 w-56 pl-8"
              />
              {keyword && (
                <Button
                  variant="ghost"
                  size="icon"
                  className="absolute right-1 top-1/2 size-6 -translate-y-1/2"
                  onClick={() => setKeyword('')}
                  title="清除搜索"
                >
                  <X className="size-3.5" />
                </Button>
              )}
            </div>
          )}
          {headerExtra}
          <Button variant="outline" onClick={exportCsv} title="导出当前筛选数据为 CSV">
            <Download /> 导出
          </Button>
          <Button onClick={openCreate}>
            <Plus /> 新增记录
          </Button>
        </div>
      </section>

      {extra}

      {enableBatch && selectedIds.size > 0 && (
        <div className="flex items-center gap-3 rounded-lg border bg-muted/40 px-4 py-2.5">
          <span className="text-sm text-muted-foreground">
            已选 <strong className="text-foreground">{selectedIds.size}</strong> 项
          </span>
          <div className="ml-auto flex items-center gap-2">
            {batchToolbar?.([...selectedIds], clearSelection)}
            <Button variant="destructive" size="sm" onClick={batchRemove}>
              <Trash2 /> 批量删除
            </Button>
            <Button variant="ghost" size="icon" className="size-7" onClick={clearSelection} title="取消选择">
              <X />
            </Button>
          </div>
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                {enableBatch && (
                  <TableHead className="w-10">
                    <Checkbox
                      checked={allVisibleSelected ? true : someVisibleSelected ? 'indeterminate' : false}
                      onCheckedChange={toggleAll}
                      aria-label="全选"
                    />
                  </TableHead>
                )}
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
                  <>
                    {Array.from({ length: 5 }).map((_, i) => (
                      <TableRow key={i}>
                        {enableBatch && (
                          <TableCell className="w-10">
                            <Skeleton className="size-4" />
                          </TableCell>
                        )}
                        {columns.map((col) => (
                          <TableCell key={col.key}>
                            <Skeleton className="h-4 w-[80%]" />
                          </TableCell>
                        ))}
                        <TableCell className="w-24">
                          <Skeleton className="h-8 w-20" />
                        </TableCell>
                      </TableRow>
                    ))}
                  </>
                ) : (
                  <TableRow>
                    <TableCell
                      colSpan={columns.length + 1 + batchColSpan}
                      className="h-24 text-center text-muted-foreground"
                    >
                      暂无记录，点击"新增记录"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id} className={selectedIds.has(row.id) ? 'bg-muted/30' : ''}>
                    {enableBatch && (
                      <TableCell className="w-10">
                        <Checkbox
                          checked={selectedIds.has(row.id)}
                          onCheckedChange={() => toggleOne(row.id)}
                          aria-label={`选择 ${(row as Record<string, unknown>).item_name ?? row.id}`}
                        />
                      </TableCell>
                    )}
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
