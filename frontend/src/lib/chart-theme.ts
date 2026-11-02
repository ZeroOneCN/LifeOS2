import { useSyncExternalStore } from 'react'

/** 图表色板令牌：chart-N 为顺序色板，其余为语义别名与中性辅助色 */
export type ChartColorToken =
  | 'chart-1'
  | 'chart-2'
  | 'chart-3'
  | 'chart-4'
  | 'chart-5'
  | 'chart-6'
  | 'chart-7'
  | 'chart-8'
  | 'chart-9'
  | 'chart-10'
  | 'success'
  | 'warning'
  | 'danger'
  | 'info'
  | 'chart-muted'
  | 'chart-axis'

/** 当前主题下的图表色板：语义令牌映射 + 饼图用的 10 色顺序色板 */
export type ChartPalette = Record<ChartColorToken, string> & {
  series: string[]
}

/** 语义令牌与 index.css 中 CSS 变量的对应关系（唯一真源在 index.css） */
const CSS_VARIABLE: Record<ChartColorToken, string> = {
  'chart-1': '--chart-1',
  'chart-2': '--chart-2',
  'chart-3': '--chart-3',
  'chart-4': '--chart-4',
  'chart-5': '--chart-5',
  'chart-6': '--chart-6',
  'chart-7': '--chart-7',
  'chart-8': '--chart-8',
  'chart-9': '--chart-9',
  'chart-10': '--chart-10',
  success: '--success',
  warning: '--warning',
  danger: '--danger',
  info: '--info',
  'chart-muted': '--chart-muted',
  'chart-axis': '--chart-axis',
}

/** 顺序色板令牌，用于饼图按分类依次取色 */
const SERIES_TOKENS: ChartColorToken[] = [
  'chart-1',
  'chart-2',
  'chart-3',
  'chart-4',
  'chart-5',
  'chart-6',
  'chart-7',
  'chart-8',
  'chart-9',
  'chart-10',
]

const ALL_TOKENS = Object.keys(CSS_VARIABLE) as ChartColorToken[]

/** 取色失败时的兜底颜色（正常浏览器路径不会命中） */
const FALLBACK_COLOR = 'gray'

type ThemeMode = 'light' | 'dark'

/** 读取当前主题模式：next-themes 通过 <html> 的 class 控制深浅色 */
function readMode(): ThemeMode {
  if (typeof document === 'undefined') return 'light'
  return document.documentElement.classList.contains('dark') ? 'dark' : 'light'
}

/**
 * 读取指定 CSS 变量在当前主题下的计算值。
 * 注意：SVG 的 fill/stroke 是表现属性，不接受 var() 引用，
 * 因此必须在这里取到具体颜色字符串再交给 Recharts。
 * @param name CSS 变量名（含 -- 前缀）
 * @returns 变量值；读取失败时返回兜底颜色
 */
function readCssVariable(name: string): string {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim()
  return value || FALLBACK_COLOR
}

/** 色板快照缓存：同一主题内复用同一对象，保证 useSyncExternalStore 快照引用稳定 */
let cachedPalette: ChartPalette | null = null
let cachedMode: ThemeMode | null = null

/**
 * 构建当前主题的图表色板。
 * 只在主题变化时重建，其余情况返回缓存对象。
 * @returns 当前主题下的色板（含语义令牌与顺序色板）
 */
function getChartPalette(): ChartPalette {
  const mode = readMode()
  if (cachedPalette && cachedMode === mode) return cachedPalette

  const palette = {} as Record<ChartColorToken, string>
  for (const token of ALL_TOKENS) {
    palette[token] = readCssVariable(CSS_VARIABLE[token])
  }

  cachedMode = mode
  cachedPalette = {
    ...palette,
    series: SERIES_TOKENS.map((token) => palette[token]),
  }
  return cachedPalette
}

/**
 * 订阅主题切换：监听 <html> 的 class 变化（next-themes 切换深浅色即改写该属性）。
 * @param onChange 主题变化后的回调
 * @returns 取消订阅函数
 */
function subscribeTheme(onChange: () => void): () => void {
  if (typeof MutationObserver === 'undefined') return () => {}
  const observer = new MutationObserver(onChange)
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] })
  return () => observer.disconnect()
}

/**
 * 获取当前主题的图表色板，并在深浅色切换时自动触发重渲染。
 * @returns 语义令牌到具体颜色值的映射，以及饼图用的 10 色顺序色板
 */
export function useChartColors(): ChartPalette {
  return useSyncExternalStore(subscribeTheme, getChartPalette, getChartPalette)
}

/**
 * 将系列颜色配置解析为可直接用于 SVG 属性（fill/stroke）的颜色值。
 * 传入语义令牌（如 success）时从当前主题色板取值；传入具体颜色时原样返回；
 * 未传时回退到色板首色。
 * @param token 语义令牌或具体颜色值
 * @param palette 当前主题色板（由 useChartColors 取得）
 * @returns 解析后的具体颜色字符串
 */
export function resolveChartColor(token: string | undefined, palette: ChartPalette): string {
  if (!token) return palette['chart-1']
  const resolved = palette[token as ChartColorToken]
  return typeof resolved === 'string' ? resolved : token
}
