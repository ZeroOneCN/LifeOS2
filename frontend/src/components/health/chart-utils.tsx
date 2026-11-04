import { useEffect, useState } from 'react'

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'

/** 统计天数：数字表示近 N 天，'all' 表示全部历史 */
export type StatsDays = number | 'all'

const STORAGE_KEY = 'lifeos_stats_days'

function readDefaultStatsDays(): StatsDays {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw === 'all') return 'all'
    const n = Number(raw)
    if (Number.isInteger(n) && n >= 1) return n
  } catch {
    /* localStorage 不可用时回退默认 */
  }
  return 30
}

/** 读取全局默认统计天数（localStorage 持久化，各页初始一致） */
export function getDefaultStatsDays(): StatsDays {
  return readDefaultStatsDays()
}

/** 设置全局默认统计天数（localStorage 持久化） */
export function setGlobalStatsDays(d: StatsDays) {
  try {
    localStorage.setItem(STORAGE_KEY, String(d))
  } catch {
    /* ignore */
  }
}

/** 统计天数选择器：近 7/30/90 天 / 全部；可选开启"对比上期"开关。 */
export function StatsPeriodPicker({
  value,
  onChange,
  compare,
  onCompareChange,
}: {
  value: StatsDays
  onChange: (d: StatsDays) => void
  compare?: boolean
  onCompareChange?: (v: boolean) => void
}) {
  return (
    <div className="flex items-center gap-2">
      <Select
        value={value === 'all' ? 'all' : String(value)}
        onValueChange={(v) => onChange(v === 'all' ? 'all' : Number(v))}
      >
        <SelectTrigger className="w-36">
          <SelectValue placeholder="统计天数" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="7">近 7 天</SelectItem>
          <SelectItem value="30">近 30 天</SelectItem>
          <SelectItem value="90">近 90 天</SelectItem>
          <SelectItem value="all">全部</SelectItem>
        </SelectContent>
      </Select>
      {onCompareChange && (
        <label className="flex cursor-pointer items-center gap-1.5 text-sm text-muted-foreground">
          <input
            type="checkbox"
            checked={!!compare}
            onChange={(e) => onCompareChange(e.target.checked)}
            className="size-4 rounded border-border"
          />
          对比上期
        </label>
      )}
    </div>
  )
}

/**
 * 计算上一等长周期的起止日期（用于对比）。
 * 例如 days=30 时，当前周期为近 30 天，上一周期为再往前 30 天。
 */
function previousPeriod(days: StatsDays): { start: string; end: string } | null {
  if (days === 'all') return null
  const today = new Date()
  const end = new Date(today)
  end.setDate(today.getDate() - days)
  const start = new Date(end)
  start.setDate(end.getDate() - days + 1)
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) }
}

/**
 * 拉取统计数据。默认每 30 秒 + 窗口聚焦 + 数据变更时自动刷新（无感实时）；
 * intervalMs 传 0 则关闭定时轮询，仅保留聚焦与变更刷新。
 * 当 compare=true 时，同时拉取上一等长周期数据并以 compareData 返回。
 */
export function useStats<T>(
  path: string,
  days: StatsDays = 30,
  refresh?: number,
  intervalMs = 30_000,
  compare = false,
): { data: T | null; compareData: T | null } {
  const realtimeTick = useRealtime(intervalMs)
  const [data, setData] = useState<T | null>(null)
  const [compareData, setCompareData] = useState<T | null>(null)

  useEffect(() => {
    api
      .stats<T>(path, days)
      .then(setData)
      .catch(() => setData(null))
  }, [path, days, refresh, realtimeTick])

  useEffect(() => {
    if (!compare) {
      setCompareData(null)
      return
    }
    const prev = previousPeriod(days)
    if (!prev) {
      setCompareData(null)
      return
    }
    api
      .statsRange<T>(path, prev.start, prev.end)
      .then(setCompareData)
      .catch(() => setCompareData(null))
  }, [path, days, refresh, realtimeTick, compare])

  return { data, compareData }
}
