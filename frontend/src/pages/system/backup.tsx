import { useEffect, useState } from 'react'
import {
  Clock,
  Database,
  Download,
  FileDown,
  FileUp,
  HardDrive,
  Loader2,
  Plus,
  RefreshCw,
  Trash2,
  Upload,
  FileJson,
  FileArchive,
  FileCode,
  Play,
  Pause,
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'

type TableInfo = {
  name: string
  count: number
}

type BackupFile = {
  filename: string
  size: number
  size_display: string
  modified_at: string
}

type ImportResult = {
  message: string
  total_inserted: number
  tables: Record<string, number>
}

type CronOption = 'preset' | 'custom'

type ScheduleItem = {
  id: number
  name: string
  enabled: boolean
  cron_expression: string
  export_format: string
  compress: boolean
  table_selection: string
  selected_tables: string[] | null
  last_run_at: string | null
  last_status: string | null
  created_at: string
  updated_at: string
}

const TABLE_LABELS: Record<string, string> = {
  health_vitals_sleep: '睡眠体征',
  health_fitness: '健身运动',
  health_diet: '饮食记录',
  health_body: '身体指标',
  health_steps: '步数统计',
  health_step_setting: '步数设置',
  health_checkup: '体检指标',
  health_checkup_template: '体检模板',
  health_checkup_panel: '体检面板',
  health_checkup_panel_item: '体检面板项目',
  health_medication: '用药记录',
  health_med_purchase: '购药记录',
  health_med_stock: '药品库存',
  health_reports: '健康报告',
  finance_shopping_records: '购物记录',
  finance_shopping_platforms: '购物平台',
  finance_shopping_ledgers: '购物账本',
  finance_travel_ledgers: '旅行账本',
  finance_travel_details: '旅行明细',
  finance_travel_payment_channels: '旅行支付方式',
  finance_travel_reports: '旅行报告',
  finance_housing: '住房信息',
  finance_rent_channels: '租金渠道',
  finance_rent_terms: '付款期次',
  finance_utilities: '水电账单',
  finance_subscriptions: '订阅续费',
  finance_subscription_categories: '订阅分类',
  finance_loan_platforms: '借款平台',
  finance_loan_bills: '借款账单',
  finance_repayments: '还款记录',
  finance_reminders: '账单提醒',
  finance_planning: '财务规划',
  finance_debts: '债务管理',
  finance_debt_payments: '债务还款',
  finance_investments: '投资记录',
  finance_memos: '备忘录',
  finance_currencies: '货币汇率',
  finance_reports: '财务报告',
  lifestyle_items: '物品追踪',
  lifestyle_phone_cards: '手机号管理',
  lifestyle_bank_cards: '银行卡管理',
  lifestyle_carriers: '运营商平台',
  lifestyle_card_bills: '卡账单',
  lifestyle_life_reports: '生活报告',
  lifestyle_todos: '待办清单',
  investment_forex: '外汇交易',
  investment_fund_records: '基金记录',
  investment_reports: '投资报告',
  notifications: '通知记录',
  notification_channels: '通知渠道',
  notification_templates: '通知模板',
  feature_reminder_settings: '功能提醒设置',
  notification_send_logs: '发送日志',
  activity_logs: '活动日志',
  user_profile: '用户信息',
  scheduled_backups: '定时备份计划',
}

const CRON_PRESETS = [
  { label: '每天 00:00', value: '0 0 * * *' },
  { label: '每天 03:00', value: '0 3 * * *' },
  { label: '每天 06:00', value: '0 6 * * *' },
  { label: '每天 12:00', value: '0 12 * * *' },
  { label: '每 6 小时', value: '0 */6 * * *' },
  { label: '每 12 小时', value: '0 */12 * * *' },
  { label: '每周一 03:00', value: '0 3 * * 1' },
  { label: '每月1日 03:00', value: '0 3 1 * *' },
  { label: '自定义', value: '__custom__' },
] as const

const TABS = [
  { key: 'export', label: '数据导出', icon: FileDown },
  { key: 'import', label: '数据导入', icon: FileUp },
  { key: 'schedule', label: '定时备份', icon: Clock },
  { key: 'manage', label: '备份管理', icon: HardDrive },
] as const

type TabKey = (typeof TABS)[number]['key']

function formatTime(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function BackupPage() {
  const [tab, setTab] = useState<TabKey>('export')
  const [tables, setTables] = useState<TableInfo[]>([])
  const [backups, setBackups] = useState<BackupFile[]>([])
  const [schedules, setSchedules] = useState<ScheduleItem[]>([])
  const [selectedTables, setSelectedTables] = useState<Set<string>>(new Set())
  const [exportFormat, setExportFormat] = useState('json')
  const [compress, setCompress] = useState(false)
  const [loadingTables, setLoadingTables] = useState(false)
  const [loadingBackups, setLoadingBackups] = useState(false)
  const [loadingSchedules, setLoadingSchedules] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [importing, setImporting] = useState(false)
  const [importFile, setImportFile] = useState<File | null>(null)
  const [importResult, setImportResult] = useState<ImportResult | null>(null)

  // 新增定时备份弹窗
  const [showScheduleDialog, setShowScheduleDialog] = useState(false)
  const [cronMode, setCronMode] = useState<CronOption>('preset')
  const [cronCustom, setCronCustom] = useState('0 3 * * *')
  const [newSchedule, setNewSchedule] = useState({
    name: '',
    cron_expression: '0 3 * * *',
    export_format: 'json',
    compress: false,
    table_selection: 'all',
  })
  const [savingSchedule, setSavingSchedule] = useState(false)

  const loadTables = async () => {
    setLoadingTables(true)
    try {
      const data = await api.query<TableInfo[]>('/backup/tables')
      setTables(data)
      setSelectedTables(new Set(data.filter((t) => t.count > 0).map((t) => t.name)))
    } catch {
      toast.error('加载数据表列表失败')
    } finally {
      setLoadingTables(false)
    }
  }

  const loadBackups = async () => {
    setLoadingBackups(true)
    try {
      const data = await api.query<BackupFile[]>('/backup/exports')
      setBackups(data)
    } catch {
      toast.error('加载备份文件列表失败')
    } finally {
      setLoadingBackups(false)
    }
  }

  const loadSchedules = async () => {
    setLoadingSchedules(true)
    try {
      const data = await api.query<ScheduleItem[]>('/backup/schedules')
      setSchedules(data)
    } catch {
      toast.error('加载定时备份任务列表失败')
    } finally {
      setLoadingSchedules(false)
    }
  }

  useEffect(() => {
    loadTables()
    loadBackups()
    loadSchedules()
  }, [])

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
      loadBackups()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '导出失败')
    } finally {
      setExporting(false)
    }
  }

  const handleImport = async () => {
    if (!importFile) {
      toast.error('请选择备份文件')
      return
    }
    if (!importFile.name.endsWith('.json')) {
      toast.error('仅支持 .json 格式的备份文件导入')
      return
    }
    setImporting(true)
    try {
      const formData = new FormData()
      formData.append('file', importFile)
      const result = await api.upload<ImportResult>('/backup/import', formData)
      setImportResult(result)
      toast.success(`导入完成，共插入 ${result.total_inserted} 条记录`)
      loadTables()
      setImportFile(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '导入失败')
    } finally {
      setImporting(false)
    }
  }

  const handleDownloadBackup = (filename: string) => {
    api.download(`/backup/exports/${encodeURIComponent(filename)}`, filename)
  }

  const handleDeleteBackup = async (filename: string) => {
    try {
      await api.del(`/backup/exports/${encodeURIComponent(filename)}`)
      toast.success(`备份文件 ${filename} 已删除`)
      loadBackups()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '删除失败')
    }
  }

  // ── 定时备份 ──

  const handleCreateSchedule = async () => {
    if (!newSchedule.name.trim()) {
      toast.error('请输入任务名称')
      return
    }
    const cronExpr = cronMode === 'custom' ? cronCustom.trim() : newSchedule.cron_expression
    if (!cronExpr) {
      toast.error('请输入 cron 表达式')
      return
    }
    setSavingSchedule(true)
    try {
      await api.post<ScheduleItem>('/backup/schedules', {
        ...newSchedule,
        cron_expression: cronExpr,
        selected_tables:
          newSchedule.table_selection === 'selected'
            ? Array.from(selectedTables)
            : null,
      })
      toast.success('定时备份任务已创建')
      setShowScheduleDialog(false)
      setCronMode('preset')
      setCronCustom('0 3 * * *')
      setNewSchedule({
        name: '',
        cron_expression: '0 3 * * *',
        export_format: 'json',
        compress: false,
        table_selection: 'all',
      })
      loadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '创建失败')
    } finally {
      setSavingSchedule(false)
    }
  }

  const handleToggleSchedule = async (id: number) => {
    try {
      const result = await api.post<ScheduleItem>(`/backup/schedules/${id}/toggle`)
      toast.success(result.enabled ? '定时备份已启用' : '定时备份已暂停')
      loadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '操作失败')
    }
  }

  const handleDeleteSchedule = async (id: number) => {
    try {
      await api.del(`/backup/schedules/${id}`)
      toast.success('定时备份任务已删除')
      loadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '删除失败')
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">数据备份</h1>
          <p className="text-muted-foreground text-sm">
            导出、导入和管理您的数据备份
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={loadTables}>
            <RefreshCw className="mr-1 h-4 w-4" />
            刷新
          </Button>
        </div>
      </div>

      {/* Tab 导航 */}
      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {TABS.map((t) => {
          const Icon = t.icon
          return (
            <Button
              key={t.key}
              variant={tab === t.key ? 'default' : 'ghost'}
              className="flex-1"
              onClick={() => setTab(t.key)}
            >
              <Icon className="mr-1.5 h-4 w-4" />
              {t.label}
            </Button>
          )
        })}
      </div>

      {/* ── 导出 Tab ── */}
      {tab === 'export' && (
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
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                  {tables.map((t) => {
                    const checked = selectedTables.has(t.name)
                    return (
                      <button
                        key={t.name}
                        type="button"
                        onClick={() => toggleTable(t.name)}
                        className={`flex items-center gap-2 rounded-md border px-3 py-2 text-sm text-left cursor-pointer transition-colors hover:bg-accent ${
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
                          <div className="truncate" title={TABLE_LABELS[t.name] || t.name}>
                          {TABLE_LABELS[t.name] || t.name}
                          </div>
                          <div className="text-muted-foreground text-xs">
                            {t.count} 条
                          </div>
                        </div>
                      </button>
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
      )}

      {/* ── 导入 Tab ── */}
      {tab === 'import' && (
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <Upload className="h-5 w-5" />
                导入数据
              </CardTitle>
              <CardDescription>
                上传之前导出的 JSON 备份文件，将数据恢复到当前数据库
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center gap-3">
                <input
                  type="file"
                  accept=".json"
                  id="import-file-input"
                  onChange={(e) => {
                    setImportFile(e.target.files?.[0] ?? null)
                    setImportResult(null)
                  }}
                  className="hidden"
                />
                <Button
                  variant="outline"
                  onClick={() => document.getElementById('import-file-input')?.click()}
                >
                  <Upload className="mr-1.5 h-4 w-4" />
                  选择备份文件
                </Button>
                <span className="text-sm text-muted-foreground">
                  {importFile ? importFile.name : '未选择文件'}
                </span>
              </div>
              {importFile && (
                <div className="rounded-md bg-muted/50 px-4 py-2 text-sm">
                  已选择：{importFile.name}（{(importFile.size / 1024).toFixed(1)} KB）
                </div>
              )}
              <div className="flex items-center gap-2 rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:bg-amber-950/30 dark:text-amber-300">
                <Database className="h-4 w-4" />
                导入将使用 INSERT IGNORE 方式，遇到主键冲突会自动跳过，不会覆盖已有数据
              </div>
              <Button onClick={handleImport} disabled={importing || !importFile}>
                {importing ? (
                  <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                ) : (
                  <Upload className="mr-1.5 h-4 w-4" />
                )}
                {importing ? '导入中...' : '开始导入'}
              </Button>
            </CardContent>
          </Card>

          {importResult && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Database className="h-5 w-5" />
                  导入结果
                </CardTitle>
                <CardDescription>
                  共插入 {importResult.total_inserted} 条记录，各表详情如下：
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>数据表</TableHead>
                        <TableHead className="text-right">插入条数</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {Object.entries(importResult.tables)
                        .filter(([, count]) => count > 0)
                        .sort((a, b) => b[1] - a[1])
                        .map(([tableName, count]) => (
                          <TableRow key={tableName}>
                            <TableCell>{TABLE_LABELS[tableName] || tableName}</TableCell>
                            <TableCell className="text-right">{count}</TableCell>
                          </TableRow>
                        ))}
                    </TableBody>
                  </Table>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* ── 定时备份 Tab ── */}
      {tab === 'schedule' && (
        <div className="space-y-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <div>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Clock className="h-5 w-5" />
                  定时备份任务
                </CardTitle>
                <CardDescription>
                  设置自动备份计划，系统将按 cron 表达式定时执行数据导出
                </CardDescription>
              </div>
              <Dialog open={showScheduleDialog} onOpenChange={setShowScheduleDialog}>
                <DialogTrigger asChild>
                  <Button>
                    <Plus className="mr-1 h-4 w-4" />
                    新建任务
                  </Button>
                </DialogTrigger>
                <DialogContent
                  onPointerDownOutside={(e) => e.preventDefault()}
                  onEscapeKeyDown={(e) => e.preventDefault()}
                >
                  <DialogHeader>
                    <DialogTitle>新建定时备份任务</DialogTitle>
                    <DialogDescription>
                      设置自动备份的计划和参数
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4 py-2">
                    <div className="space-y-1">
                      <Label>任务名称</Label>
                      <Input
                        value={newSchedule.name}
                        onChange={(e) =>
                          setNewSchedule({ ...newSchedule, name: e.target.value })
                        }
                        placeholder="例如：每日凌晨备份"
                      />
                    </div>
                    <div className="space-y-1">
                      <Label>执行计划</Label>
                      <div className="space-y-2">
                        <Select
                          value={cronMode === 'custom' ? '__custom__' : newSchedule.cron_expression}
                          onValueChange={(v) => {
                            if (v === '__custom__') {
                              setCronMode('custom')
                            } else {
                              setCronMode('preset')
                              setNewSchedule({ ...newSchedule, cron_expression: v })
                            }
                          }}
                        >
                          <SelectTrigger>
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {CRON_PRESETS.map((p) => (
                              <SelectItem key={p.value} value={p.value}>
                                {p.label}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        {cronMode === 'custom' && (
                          <Input
                            value={cronCustom}
                            onChange={(e) => setCronCustom(e.target.value)}
                            placeholder="5-field cron, e.g. 0 3 * * *"
                            className="font-mono text-xs"
                          />
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground">
                        cron 格式：分 时 日 月 周（例如 <code className="rounded bg-muted px-1">0 3 * * *</code> 表示每天 03:00）
                      </p>
                    </div>
                    <div className="space-y-1">
                      <Label>导出格式</Label>
                      <Select
                        value={newSchedule.export_format}
                        onValueChange={(v) =>
                          setNewSchedule({ ...newSchedule, export_format: v })
                        }
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="json">JSON</SelectItem>
                          <SelectItem value="sql">SQL</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    {newSchedule.export_format === 'json' && (
                      <div className="flex items-center gap-2">
                        <Switch
                          id="schedule-compress"
                          checked={newSchedule.compress}
                          onCheckedChange={(v) =>
                            setNewSchedule({ ...newSchedule, compress: v })
                          }
                        />
                        <Label htmlFor="schedule-compress" className="cursor-pointer">
                          压缩为 ZIP
                        </Label>
                      </div>
                    )}
                    <div className="space-y-1">
                      <Label>导出范围</Label>
                      <Select
                        value={newSchedule.table_selection}
                        onValueChange={(v) =>
                          setNewSchedule({ ...newSchedule, table_selection: v })
                        }
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="all">全部数据表</SelectItem>
                          <SelectItem value="selected">选中的数据表</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  <DialogFooter>
                    <Button variant="outline" onClick={() => setShowScheduleDialog(false)}>
                      取消
                    </Button>
                    <Button onClick={handleCreateSchedule} disabled={savingSchedule}>
                      {savingSchedule ? (
                        <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                      ) : null}
                      保存
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </CardHeader>
            <CardContent>
              {loadingSchedules ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                </div>
              ) : schedules.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
                  <Clock className="mb-2 h-10 w-10" />
                  <p>暂无定时备份任务</p>
                  <p className="text-xs">点击"新建任务"按钮创建自动备份计划</p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>任务名称</TableHead>
                        <TableHead>执行计划</TableHead>
                        <TableHead>格式</TableHead>
                        <TableHead>范围</TableHead>
                        <TableHead>上次执行</TableHead>
                        <TableHead>状态</TableHead>
                        <TableHead className="w-24 text-right">操作</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {schedules.map((s) => (
                        <TableRow key={s.id}>
                          <TableCell className="font-medium">{s.name}</TableCell>
                          <TableCell className="font-mono text-xs">{s.cron_expression}</TableCell>
                          <TableCell>
                            <Badge variant="outline" className="font-mono text-xs uppercase">
                              {s.export_format}
                              {s.compress && ' ZIP'}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-xs text-muted-foreground">
                            {s.table_selection === 'all' ? '全部' : '部分'}
                          </TableCell>
                          <TableCell className="text-xs text-muted-foreground">
                            {s.last_run_at ? formatTime(s.last_run_at) : '未执行'}
                          </TableCell>
                          <TableCell>
                            {s.last_status === 'success' ? (
                              <Badge className="bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400">
                                成功
                              </Badge>
                            ) : s.last_status === 'failed' ? (
                              <Badge variant="destructive">失败</Badge>
                            ) : s.enabled ? (
                              <Badge variant="secondary" className="bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400">
                                等待中
                              </Badge>
                            ) : (
                              <Badge variant="outline" className="text-muted-foreground">
                                已暂停
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="flex items-center justify-end gap-1">
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                title={s.enabled ? '暂停' : '启用'}
                                onClick={() => handleToggleSchedule(s.id)}
                              >
                                {s.enabled ? (
                                  <Pause className="h-4 w-4" />
                                ) : (
                                  <Play className="h-4 w-4" />
                                )}
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-destructive hover:text-destructive"
                                title="删除"
                                onClick={() => handleDeleteSchedule(s.id)}
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* ── 备份管理 Tab ── */}
      {tab === 'manage' && (
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-lg">
                <HardDrive className="h-5 w-5" />
                备份文件列表
              </CardTitle>
              <CardDescription>
                管理已生成的备份文件，可下载或删除
              </CardDescription>
            </CardHeader>
            <CardContent>
              {loadingBackups ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                </div>
              ) : backups.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
                  <HardDrive className="mb-2 h-10 w-10" />
                  <p>暂无备份文件</p>
                  <p className="text-xs">在"数据导出"或"定时备份"中导出数据后，备份文件将出现在这里</p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>文件名</TableHead>
                        <TableHead>大小</TableHead>
                        <TableHead>修改时间</TableHead>
                        <TableHead className="w-28 text-right">操作</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {backups.map((f) => (
                        <TableRow key={f.filename}>
                          <TableCell className="max-w-[300px] truncate font-mono text-xs" title={f.filename}>
                            {f.filename}
                          </TableCell>
                          <TableCell className="text-muted-foreground text-xs">{f.size_display}</TableCell>
                          <TableCell className="text-muted-foreground text-xs">
                            {formatTime(f.modified_at)}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="flex items-center justify-end gap-1">
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                title="下载"
                                onClick={() => handleDownloadBackup(f.filename)}
                              >
                                <Download className="h-4 w-4" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-destructive hover:text-destructive"
                                title="删除"
                                onClick={() => handleDeleteBackup(f.filename)}
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}