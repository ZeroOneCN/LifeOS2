import { useCallback, useEffect, useState } from 'react'

import { useRealtime } from '@/hooks/use-realtime'
import { api, type ListParams } from '@/lib/api'

type UseRecordListOptions = {
  /** 资源 API 路径，如 '/finance/shopping' */
  apiPath: string
  /** 每页条数，默认 10 */
  pageSize?: number
  /** 启用按月份过滤模式 */
  monthMode?: boolean
  /** 启用关键字搜索（配合后端 search_text） */
  searchable?: boolean
  /** 外部刷新触发器，变化时重新加载 */
  refreshKey?: number
  /** 实时刷新间隔（毫秒），默认 30s；传 0 关闭 */
  realtimeInterval?: number
}

type UseRecordListResult<T> = {
  items: T[]
  total: number
  page: number
  pageSize: number
  totalPages: number
  loading: boolean
  month: string
  keyword: string
  setPage: (p: number | ((prev: number) => number)) => void
  setMonth: (m: string) => void
  setKeyword: (k: string) => void
  load: () => Promise<void>
}

/**
 * 通用记录列表 Hook：封装分页、月份过滤、关键字搜索、实时刷新逻辑。
 *
 * 从 RecordManager 抽取而来，供需要列表加载但不使用 RecordManager 完整表格的页面复用。
 *
 * @param options 配置项（apiPath 必填，其余可选）
 * @returns 列表状态与操作方法
 */
export function useRecordList<T extends { id: number }>(
  options: UseRecordListOptions,
): UseRecordListResult<T> {
  const {
    apiPath,
    pageSize = 10,
    monthMode = false,
    searchable = false,
    refreshKey,
    realtimeInterval = 30_000,
  } = options

  const [items, setItems] = useState<T[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [keyword, setKeyword] = useState('')
  const [month, setMonthState] = useState(() => {
    const n = new Date()
    return `${n.getFullYear()}-${String(n.getMonth() + 1).padStart(2, '0')}`
  })

  const realtimeTick = useRealtime(realtimeInterval)

  const totalPages = Math.max(1, Math.ceil(total / pageSize))

  /** 加载列表数据：支持分页、月份过滤、关键字搜索。 */
  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params: ListParams = { page, page_size: pageSize }
      if (monthMode) {
        const [yy, mm] = month.split('-').map(Number)
        const last = String(new Date(yy, mm, 0).getDate()).padStart(2, '0')
        params.start = `${month}-01`
        params.end = `${month}-${last}`
      }
      if (searchable && keyword.trim()) {
        params.extra = { ...params.extra, search_text: keyword.trim() }
      }
      const res = await api.list<T>(apiPath, params)
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }, [apiPath, page, pageSize, monthMode, month, searchable, keyword])

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, refreshKey, month, realtimeTick, keyword])

  const setMonth = useCallback((m: string) => {
    setMonthState(m)
    setPage(1)
  }, [])

  const setKeywordWrapped = useCallback((k: string) => {
    setKeyword(k)
    setPage(1)
  }, [])

  return {
    items,
    total,
    page,
    pageSize,
    totalPages,
    loading,
    month,
    keyword,
    setPage,
    setMonth,
    setKeyword: setKeywordWrapped,
    load,
  }
}
