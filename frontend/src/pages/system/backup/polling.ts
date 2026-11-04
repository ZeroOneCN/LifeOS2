import { useEffect, useState } from 'react'
import { toast } from 'sonner'

import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'

import type { BackupFile, BackupPage, LogItem, LogPage, ScheduleItem } from './shared'

const BACKUP_PAGE_SIZE = 10
const LOG_PAGE_SIZE = 10

type PollingOptions = {
  /** 备份文件列表当前页码（由页面持有） */
  backupPage: number
  /** 执行日志当前页码（由页面持有） */
  logPage: number
  /** 当前激活的 Tab：日志仅在其 Tab 可见时轮询，切到定时任务/备份管理时立即拉取一次 */
  activeTab: string
}

/**
 * 备份页统一的数据轮询调度。
 *
 * 拆分前所有请求都在同一个组件里，定时任务列表与备份文件列表即使当前不在对应 Tab 也照常每 30s 刷新；
 * 拆分后子组件按需挂载会让未挂载 Tab 的轮询停掉。这里把轮询与数据状态上提到页面层：
 * 无论 Tab 是否挂载，定时任务与备份文件都按 30s 周期执行，可见的 Tab 直接读取这里的数据。
 * （执行日志按原逻辑依赖分页参数，仅在其 Tab 可见时轮询；切 Tab 时对应列表立即拉取一次。）
 */
export function useBackupPolling({ backupPage, logPage, activeTab }: PollingOptions) {
  const realtimeTick = useRealtime(30_000)
  const logsActive = activeTab === 'logs'

  const [backups, setBackups] = useState<BackupFile[]>([])
  const [backupTotal, setBackupTotal] = useState(0)
  const [loadingBackups, setLoadingBackups] = useState(false)

  const [schedules, setSchedules] = useState<ScheduleItem[]>([])
  const [loadingSchedules, setLoadingSchedules] = useState(false)

  const [logs, setLogs] = useState<LogItem[]>([])
  const [logTotal, setLogTotal] = useState(0)
  const [loadingLogs, setLoadingLogs] = useState(false)

  const loadBackups = async () => {
    setLoadingBackups(true)
    try {
      const data = await api.query<BackupPage>(
        `/backup/exports?page=${backupPage}&page_size=${BACKUP_PAGE_SIZE}`
      )
      setBackups(data.items)
      setBackupTotal(data.total)
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

  const loadLogs = async () => {
    setLoadingLogs(true)
    try {
      const data = await api.query<LogPage>(`/backup/logs?page=${logPage}&page_size=${LOG_PAGE_SIZE}`)
      setLogs(data.items)
      setLogTotal(data.total)
    } catch {
      toast.error('加载备份日志失败')
    } finally {
      setLoadingLogs(false)
    }
  }

  // 首屏预取：与原实现一致，进入页面即加载定时任务与备份列表
  useEffect(() => {
    loadBackups()
    loadSchedules()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // 常驻轮询：与当前 Tab 无关，30s 一次刷新定时任务与备份列表
  useEffect(() => {
    loadBackups()
    loadSchedules()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [realtimeTick, backupPage])

  // 执行日志：仅在其 Tab 可见时按 30s 轮询（依赖分页参数）
  useEffect(() => {
    if (logsActive) loadLogs()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [logsActive, logPage, realtimeTick])

  // 切换到定时任务 / 备份管理时立即拉取一次，与原单组件版本一致（不等下一轮 30s）
  useEffect(() => {
    if (activeTab === 'manage') loadBackups()
    if (activeTab === 'schedule') loadSchedules()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab])

  /** 手动刷新：并行拉取定时任务、备份列表，日志可见时一并刷新 */
  const reloadAll = async () => {
    const tasks: Promise<void>[] = [loadBackups(), loadSchedules()]
    if (logsActive) tasks.push(loadLogs())
    await Promise.all(tasks)
  }

  /** 清除日志后的本地状态复位（不触发请求） */
  const resetLogs = () => {
    setLogs([])
    setLogTotal(0)
  }

  return {
    backups,
    backupTotal,
    loadingBackups,
    loadBackups,
    schedules,
    loadingSchedules,
    loadSchedules,
    logs,
    logTotal,
    loadingLogs,
    loadLogs,
    resetLogs,
    reloadAll,
  }
}
