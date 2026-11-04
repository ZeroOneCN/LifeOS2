/** 体检页面共享类型、常量与判定工具（供页面与子组件复用）。 */

export type CheckupRecord = {
  id: number
  check_date: string
  item_name: string
  value?: number
  unit?: string
  ref_low?: number
  ref_high?: number
  reference_range?: string
  result?: string
  note?: string
}

export type TrendPoint = { check_date: string; value?: number | null; result?: string | null }

export type CheckupStats = {
  items: {
    item_name: string
    unit?: string
    reference_range?: string
    ref_low?: number | null
    ref_high?: number | null
    latest: { check_date: string; value?: number; result?: string } | null
    count: number
    trend?: TrendPoint[]
  }[]
  total_count?: number
  abnormal_count: number
  status_counts: { normal: number; high: number; low: number }
  abnormal_items: { check_date: string; value?: number; result?: string }[]
}

export type Template = { id: number; item_name: string; category?: string; unit?: string; ref_low?: number; ref_high?: number }

export type PanelItem = { item_name: string; unit?: string; ref_low?: number | null; ref_high?: number | null; reference_range?: string }
export type Panel = { id: number; panel_name: string; note?: string; items: PanelItem[] }

export type RecordItemForm = {
  item_name: string
  value: string
  unit?: string
  ref_low?: number | null
  ref_high?: number | null
  reference_range?: string
}

export const resultMeta: Record<string, { label: string; className: string }> = {
  normal: { label: '正常', className: 'bg-success-muted text-success-muted-foreground' },
  high: { label: '偏高', className: 'bg-danger-muted text-danger-muted-foreground' },
  low: { label: '偏低', className: 'bg-warning-muted text-warning-muted-foreground' },
}

export function judge(value: string, lo?: number | null, hi?: number | null): string {
  const v = Number(value)
  if (Number.isNaN(v)) return ''
  if (hi != null && v > hi) return 'high'
  if (lo != null && v < lo) return 'low'
  return 'normal'
}

export function fmtRange(lo?: number | null, hi?: number | null): string {
  if (lo == null && hi == null) return ''
  if (lo != null && hi != null) return `${lo}~${hi}`
  if (lo != null) return `≥${lo}`
  return `≤${hi}`
}

/** 结果严重度排序：偏高/偏低（异常）优先，正常次之，未判定最后。 */
export const RESULT_RANK: Record<string, number> = { high: 0, low: 1, normal: 2 }

/** 概览筛选维度。 */
export const OVERVIEW_FILTERS = [
  { key: 'all', label: '全部' },
  { key: 'abnormal', label: '异常' },
  { key: 'normal', label: '正常' },
] as const

export type OverviewFilter = (typeof OVERVIEW_FILTERS)[number]['key']

export const STAT_TONE: Record<'danger' | 'success' | 'warn' | 'neutral', string> = {
  danger: 'text-danger',
  success: 'text-success',
  warn: 'text-warning',
  neutral: 'text-foreground',
}

/** 计算最新一次相对上一次的数值变化；数据不足两次返回 null。 */
export function deltaOf(trend?: TrendPoint[]): number | null {
  if (!trend || trend.length < 2) return null
  const cur = trend[trend.length - 1]?.value
  const prev = trend[trend.length - 2]?.value
  if (cur == null || prev == null) return null
  return Number((cur - prev).toFixed(2))
}
