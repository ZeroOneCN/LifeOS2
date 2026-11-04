import { useEffect, useState } from 'react'
import { Clock, FileDown, FileUp, HardDrive, RefreshCw, ScrollText } from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { api } from '@/lib/api'

import { ExportTab } from './export-tab'
import { ImportTab } from './import-tab'
import { LogsTab } from './logs-tab'
import { ManageTab } from './manage-tab'
import { ScheduleTab } from './schedule-tab'
import type { ImportResult, TableInfo } from './shared'

const TABS = [
  { key: 'export', label: '数据导出', icon: FileDown },
  { key: 'import', label: '数据导入', icon: FileUp },
  { key: 'schedule', label: '定时备份', icon: Clock },
  { key: 'logs', label: '执行日志', icon: ScrollText },
  { key: 'manage', label: '备份管理', icon: HardDrive },
] as const

type TabKey = (typeof TABS)[number]['key']

/**
 * 数据备份页：按 TABS 拆分为独立子模块。
 * 跨 Tab 需保留的交互状态（导出格式、压缩、模块折叠、已选导入文件、两个分页页码）
 * 仍由本页面持有，保证切换 Tab 后不被重置，与原单组件版本行为一致。
 */
export function BackupPage() {
  const [tab, setTab] = useState<TabKey>('export')
  const [refreshing, setRefreshing] = useState(false)
  const [refreshTick, setRefreshTick] = useState(0)
  const [tables, setTables] = useState<TableInfo[]>([])
  const [selectedTables, setSelectedTables] = useState<Set<string>>(new Set())
  const [loadingTables, setLoadingTables] = useState(false)

  // 导出 Tab：格式 / 压缩 / 分区折叠
  const [exportFormat, setExportFormat] = useState('json')
  const [compress, setCompress] = useState(false)
  const [collapsedModules, setCollapsedModules] = useState<Set<string>>(new Set())
  // 导入 Tab：已选文件 / 导入结果
  const [importFile, setImportFile] = useState<File | null>(null)
  const [importResult, setImportResult] = useState<ImportResult | null>(null)
  // 日志 / 备份管理：分页页码
  const [logPage, setLogPage] = useState(1)
  const [backupPage, setBackupPage] = useState(1)

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

  useEffect(() => {
    loadTables()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

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
          <Button
            variant="outline"
            size="sm"
            disabled={refreshing}
            onClick={async () => {
              setRefreshing(true)
              setRefreshTick((t) => t + 1)
              await loadTables()
              setRefreshing(false)
            }}
          >
            <RefreshCw className={`mr-1 h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            刷新
          </Button>
        </div>
      </div>

      {/* Tab 导航 */}
      <div className="flex gap-1 overflow-x-auto rounded-lg bg-muted p-1">
        {TABS.map((t) => {
          const Icon = t.icon
          return (
            <Button
              key={t.key}
              variant={tab === t.key ? 'default' : 'ghost'}
              className="min-w-max flex-1 whitespace-nowrap"
              onClick={() => setTab(t.key)}
            >
              <Icon className="size-4" /> {t.label}
            </Button>
          )
        })}
      </div>

      {tab === 'export' && (
        <ExportTab
          tables={tables}
          loadingTables={loadingTables}
          selectedTables={selectedTables}
          setSelectedTables={setSelectedTables}
          exportFormat={exportFormat}
          setExportFormat={setExportFormat}
          compress={compress}
          setCompress={setCompress}
          collapsedModules={collapsedModules}
          setCollapsedModules={setCollapsedModules}
        />
      )}
      {tab === 'import' && (
        <ImportTab
          tables={tables}
          reloadTables={loadTables}
          importFile={importFile}
          setImportFile={setImportFile}
          importResult={importResult}
          setImportResult={setImportResult}
        />
      )}
      {tab === 'schedule' && (
        <ScheduleTab selectedTables={selectedTables} refreshTick={refreshTick} />
      )}
      {tab === 'logs' && (
        <LogsTab refreshTick={refreshTick} logPage={logPage} setLogPage={setLogPage} />
      )}
      {tab === 'manage' && (
        <ManageTab refreshTick={refreshTick} backupPage={backupPage} setBackupPage={setBackupPage} />
      )}
    </div>
  )
}
