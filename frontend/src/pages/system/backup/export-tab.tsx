import { useMemo, useState, type Dispatch, type SetStateAction } from 'react'
import {
  ChevronDown,
  Database,
  Download,
  FileArchive,
  FileCode,
  FileDown,
  FileJson,
  Loader2,
} from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Tip } from '@/components/ui/tip'

import type { TableInfo } from './shared'

type ExportTabProps = {
  tables: TableInfo[]
  loadingTables: boolean
  selectedTables: Set<string>
  setSelectedTables: Dispatch<SetStateAction<Set<string>>>
  // 导出格式 / 压缩 / 折叠状态由页面持有，切换 Tab 后不重置（与原单组件行为一致）
  exportFormat: string
  setExportFormat: (value: string) => void
  compress: boolean
  setCompress: (value: boolean) => void
  collapsedModules: Set<string>
  setCollapsedModules: Dispatch<SetStateAction<Set<string>>>
}

export function ExportTab({
  tables,
  loadingTables,
  selectedTables,
  setSelectedTables,
  exportFormat,
  setExportFormat,
  compress,
  setCompress,
  collapsedModules,
  setCollapsedModules,
}: ExportTabProps) {
  const [exporting, setExporting] = useState(false)

  const toggleTable = (name: string) => {
    setSelectedTables((prev) => {
      const next = new Set(prev)
      if (next.has(name)) next.delete(name)
      else next.add(name)
      return next
    })
  }

  const selectAllTables = () => {
    setSelectedTables(new Set(tables.map((t) => t.name)))
  }

  const deselectAllTables = () => {
    setSelectedTables(new Set())
  }

  const toggleModuleCollapse = (key: string) => {
    setCollapsedModules((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  // 按模块归属分组（后端已按模块顺序返回，此处仅做聚合）
  const tableGroups = useMemo(() => {
    const groups: { key: string; label: string; tables: TableInfo[] }[] = []
    for (const t of tables) {
      const group = groups.find((g) => g.key === t.module)
      if (group) group.tables.push(t)
      else groups.push({ key: t.module, label: t.module_label, tables: [t] })
    }
    return groups
  }, [tables])

  const handleExport = async () => {
    if (selectedTables.size === 0) {
      toast.error('请至少选择一张数据表')
      return
    }
    setExporting(true)
    try {
      const tablesArr = Array.from(selectedTables)
      const body = JSON.stringify({
        tables: tablesArr.length < tables.length ? tablesArr : null,
        format: exportFormat,
        compress,
      })
      const token = localStorage.getItem('lifeos_token')
      const res = await fetch('/api/v1/backup/export', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body,
      })
      if (!res.ok) {
        const errBody = await res.json().catch(() => null)
        throw new Error(errBody?.detail ?? '导出失败')
      }
      const blob = await res.blob()
      const disp = res.headers.get('Content-Disposition') || ''
      const match = disp.match(/filename\*=UTF-8''([^;]+)/)
      const filename = match
        ? decodeURIComponent(match[1])
        : `backup.${exportFormat === 'sql' ? 'sql' : compress ? 'zip' : 'json'}`
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = filename
      a.click()
      URL.revokeObjectURL(url)
      toast.success(`数据已导出：${filename}`)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '导出失败')
    } finally {
      setExporting(false)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Database className="h-5 w-5" />
            选择数据表
          </CardTitle>
          <CardDescription>
            勾选需要导出的数据表，全选或取消后点击"导出数据"按钮
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="mb-3 flex items-center gap-3">
            <Button variant="outline" size="sm" onClick={selectAllTables}>
              全选
            </Button>
            <Button variant="outline" size="sm" onClick={deselectAllTables}>
              取消全选
            </Button>
            <span className="text-muted-foreground text-xs">
              已选 {selectedTables.size} / {tables.length} 张表
            </span>
          </div>
          {loadingTables ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : (
            <div className="space-y-3">
              {tableGroups.map((group) => {
                const collapsed = collapsedModules.has(group.key)
                const selectedCount = group.tables.filter((t) =>
                  selectedTables.has(t.name)
                ).length
                return (
                  <div key={group.key} className="overflow-hidden rounded-md border">
                    <button
                      type="button"
                      onClick={() => toggleModuleCollapse(group.key)}
                      className="flex w-full cursor-pointer items-center gap-2 border-b bg-muted/40 px-3 py-2.5 text-left transition-colors hover:bg-muted/70"
                    >
                      <ChevronDown
                        className={`h-4 w-4 shrink-0 text-muted-foreground transition-transform ${
                          collapsed ? '-rotate-90' : ''
                        }`}
                      />
                      <span className="text-sm font-medium">{group.label}</span>
                      <span className="text-muted-foreground text-xs">
                        已选 {selectedCount} / {group.tables.length} 张表
                      </span>
                    </button>
                    {!collapsed && (
                      <div className="grid grid-cols-2 gap-2 p-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                        {group.tables.map((t) => {
                          const checked = selectedTables.has(t.name)
                          return (
                            <button
                              key={t.name}
                              type="button"
                              onClick={() => toggleTable(t.name)}
                              className={`flex items-center gap-2 rounded-md border px-3 py-2 text-left text-sm transition-colors hover:bg-accent ${
                                checked ? 'border-primary bg-primary/5' : ''
                              }`}
                            >
                              <span
                                className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-[3px] border text-xs transition-colors ${
                                  checked
                                    ? 'border-primary bg-primary text-primary-foreground'
                                    : 'border-input'
                                }`}
                              >
                                {checked && (
                                  <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                                  </svg>
                                )}
                              </span>
                              <div className="min-w-0 flex-1 truncate">
                                <Tip label={t.mapped ? t.label ?? t.name : `${t.name}（未配置中文名）`}>
                                  <div className="flex items-center gap-1 truncate">
                                    <span className="truncate">{t.label ?? t.name}</span>
                                    {!t.mapped && (
                                      <Badge variant="outline" className="shrink-0 px-1 py-0 text-[10px] text-warning">
                                        未配置中文名
                                      </Badge>
                                    )}
                                  </div>
                                </Tip>
                                <div className="text-muted-foreground text-xs">
                                  {t.count} 条
                                </div>
                              </div>
                            </button>
                          )
                        })}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <FileDown className="h-5 w-5" />
            导出设置
          </CardTitle>
          <CardDescription>选择导出格式和压缩选项</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-4">
            <div className="space-y-1">
              <Label>导出格式</Label>
              <Select value={exportFormat} onValueChange={setExportFormat}>
                <SelectTrigger className="w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="json">
                    <span className="flex items-center gap-1">
                      <FileJson className="h-3.5 w-3.5" /> JSON
                    </span>
                  </SelectItem>
                  <SelectItem value="sql">
                    <span className="flex items-center gap-1">
                      <FileCode className="h-3.5 w-3.5" /> SQL
                    </span>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
            {exportFormat === 'json' && (
              <div className="flex items-center gap-2 pt-5">
                <button
                  type="button"
                  role="checkbox"
                  aria-checked={compress}
                  onClick={() => setCompress(!compress)}
                  className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-[3px] border text-xs transition-colors ${
                    compress
                      ? 'border-primary bg-primary text-primary-foreground'
                      : 'border-input'
                  }`}
                >
                  {compress && (
                    <svg className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" />
                    </svg>
                  )}
                </button>
                <Label onClick={() => setCompress(!compress)} className="cursor-pointer select-none">
                  <FileArchive className="mr-1 inline h-3.5 w-3.5" />
                  压缩为 ZIP
                </Label>
              </div>
            )}
          </div>
          <div className="flex items-center gap-2 rounded-lg bg-muted/50 px-4 py-3 text-sm text-muted-foreground">
            <Database className="h-4 w-4" />
            {exportFormat === 'sql'
              ? 'SQL 格式使用 mysqldump 导出，包含表结构和数据，适合完整迁移'
              : 'JSON 格式导出数据内容，可通过导入功能恢复，适合跨环境迁移'}
          </div>
          <Button onClick={handleExport} disabled={exporting || selectedTables.size === 0}>
            {exporting ? (
              <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
            ) : (
              <Download className="mr-1.5 h-4 w-4" />
            )}
            {exporting ? '导出中...' : '导出数据'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
