/**
 * 全站数值/日期/时长格式化的唯一真源。
 *
 * 统一口径：
 * - 金额：固定 2 位小数 + 千分位，符号在货币符号前（-¥1,234.56），0 显示 0.00；
 *   人民币用 formatCny，美元用 formatUsd（投资域一律 USD，财务域 CNY）。
 * - 百分比：默认 1 位小数，0 显示 0.0%；费率类可显式传 2 位。
 * - 整数：一律千分位（4,277），图表轴复用同一函数。
 * - 日期：展示层 YYYY-MM-DD；含时间 YYYY-MM-DD HH:mm（不显示秒）。
 * - 时长：< 60 分钟显示「40 分钟」，>= 60 显示「1 小时 5 分钟」。
 * - 占位符：全站统一全角破折号「—」（常量 DASH）。
 */

/** 全站统一占位符：全角破折号 */
export const DASH = '—'

/** 数值兜底：非有限数（null/undefined/NaN）按 0 处理，避免出现 NaN 文案 */
function toNumber(n: number | null | undefined): number {
  return typeof n === 'number' && Number.isFinite(n) ? n : 0
}

/**
 * 千分位小数格式化。
 * @param n 原始数值
 * @param min 最少小数位（默认 2）
 * @param max 最多小数位（默认与 min 相同）
 * @returns 带千分位的字符串；极小值（浮点误差产生的负零）归零
 */
export function formatDecimal(n: number | null | undefined, min = 2, max = min): string {
  const v = toNumber(n)
  const zeroed = Math.abs(v) < Number(`1e-${max + 1}`) ? 0 : v
  return zeroed.toLocaleString('en-US', {
    minimumFractionDigits: min,
    maximumFractionDigits: max,
  })
}

/**
 * 整数格式化：四舍五入后加千分位。
 * @param n 原始数值
 * @returns 如 4,277；零显示 0
 */
export function formatInt(n: number | null | undefined): string {
  return Math.round(toNumber(n)).toLocaleString('en-US')
}

/**
 * 金额格式化（通用）：固定 2 位小数、千分位，负号在货币符号前。
 * @param n 原始金额
 * @param symbol 货币符号（如 ¥、$）
 * @param withPlus 正数是否显示 + 号（盈亏类用 true）
 * @returns 如 -$1,234.56；0 显示 $0.00
 */
export function formatMoney(
  n: number | null | undefined,
  symbol: string,
  withPlus = false,
): string {
  const raw = toNumber(n)
  const v = Math.abs(raw) < 0.005 ? 0 : raw
  const abs = formatDecimal(Math.abs(v), 2)
  if (v < 0) return `-${symbol}${abs}`
  if (v > 0 && withPlus) return `+${symbol}${abs}`
  return `${symbol}${abs}`
}

/**
 * 人民币金额（财务域）。
 * @param n 原始金额
 * @returns 如 ¥1,234.56、-¥1,234.56
 */
export function formatCny(n: number | null | undefined): string {
  return formatMoney(n, '¥')
}

/**
 * 美元金额（投资域）。
 * @param n 原始金额
 * @returns 如 $1,234.56、-$1,234.56
 */
export function formatUsd(n: number | null | undefined): string {
  return formatMoney(n, '$')
}

/**
 * 美元盈亏：正数带 + 号，负数带 - 号，0 不带符号。
 * @param n 原始盈亏金额
 * @returns 如 +$1,234.56、-$1,234.56、$0.00
 */
export function formatUsdSigned(n: number | null | undefined): string {
  return formatMoney(n, '$', true)
}

/**
 * 图表坐标轴（美元）：取整 + 千分位，避免轴刻度被小数挤满。
 * @param n 轴刻度数值
 * @returns 如 -$1,234
 */
export function formatUsdAxis(n: number): string {
  return `${n < 0 ? '-' : ''}$${formatInt(Math.abs(n))}`
}

/**
 * 图表坐标轴（人民币）：取整 + 千分位。
 * @param n 轴刻度数值
 * @returns 如 -¥1,234
 */
export function formatCnyAxis(n: number): string {
  return `${n < 0 ? '-' : ''}¥${formatInt(Math.abs(n))}`
}

/**
 * 百分比格式化：同一信息域内位数保持一致，0 显示 0.0%。
 * @param n 百分比数值（后端已按点数返回，如 52.3 表示 52.3%）
 * @param digits 最少小数位，默认 1
 * @param maxDigits 最多小数位，默认与 digits 相同（费率类用 1~2 位以保留 0.05% 精度）
 * @returns 如 52.3%、0.0%、0.05%
 */
export function formatPercent(
  n: number | null | undefined,
  digits = 1,
  maxDigits = digits,
): string {
  return `${formatDecimal(n, digits, maxDigits)}%`
}

/** 判断字符串是否已是纯日期（YYYY-MM-DD） */
function isDateOnly(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value)
}

/** 将输入解析为 Date；无法解析返回 null */
function parseDate(value?: string | number | Date | null): Date | null {
  if (value === null || value === undefined || value === '') return null
  const d = value instanceof Date ? value : new Date(value)
  return Number.isNaN(d.getTime()) ? null : d
}

/**
 * 日期格式化：展示层统一 YYYY-MM-DD。
 * @param value 日期字符串 / 时间戳 / Date
 * @returns 如 2026-08-07；无效或空值返回「—」
 */
export function formatDate(value?: string | number | Date | null): string {
  if (typeof value === 'string' && isDateOnly(value)) return value
  const d = parseDate(value)
  if (!d) return DASH
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

/**
 * 日期时间格式化：展示层统一 YYYY-MM-DD HH:mm（不显示秒）。
 * @param value 日期时间字符串 / 时间戳 / Date
 * @returns 纯日期输入原样返回；无效或空值返回「—」
 */
export function formatDateTime(value?: string | number | Date | null): string {
  if (typeof value === 'string' && isDateOnly(value)) return value
  const d = parseDate(value)
  if (!d) return DASH
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/**
 * 统计区间格式化：统一「YYYY-MM-DD ~ YYYY-MM-DD」。
 * @param start 起始日期
 * @param end 结束日期
 * @param label 起始/结束缺失时的兜底文案（如后端 period_label）
 * @returns 如 2026-08-07 ~ 2026-09-05；无任何可用信息返回空串
 */
export function formatRange(
  start?: string | null,
  end?: string | null,
  label?: string | null,
): string {
  if (start && end) return `${formatDate(start)} ~ ${formatDate(end)}`
  return label ?? ''
}

/**
 * 时长格式化：统一「X 分钟」/「X 小时 Y 分钟」。
 * @param minutes 分钟数
 * @returns < 60 显示「40 分钟」；>= 60 显示「1 小时 5 分钟」；空值返回「—」
 */
export function formatDuration(minutes?: number | null): string {
  if (minutes === null || minutes === undefined || !Number.isFinite(minutes) || minutes < 0) {
    return DASH
  }
  const total = Math.round(minutes)
  if (total < 60) return `${total} 分钟`
  const h = Math.floor(total / 60)
  const m = total % 60
  return m === 0 ? `${h} 小时` : `${h} 小时 ${m} 分钟`
}

/**
 * 健康指标（BMI、体脂率等）固定 1 位小数。
 * @param n 原始数值
 * @returns 如 25.0；空值返回「—」
 */
export function formatHealth1(n?: number | null): string {
  return n === null || n === undefined ? DASH : formatDecimal(n, 1)
}

/**
 * 报告标题去重：去掉标题中已由副标题展示的统计区间，避免同一区间出现两次。
 * 支持「2026-08-07 ~ 2026-09-05 财务报告」的前缀区间与
 * 「健康报告（2026-08-07 至 2026-09-05）」的括号区间；不含日期的括号（如行程名）保持原样。
 * @param title 后端报告标题
 * @returns 去掉区间后的标题
 */
export function reportTitle(title?: string | null): string {
  if (!title) return ''
  return title
    .replace(
      /（\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}）/g,
      '',
    )
    .replace(
      /^\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2}\s+/,
      '',
    )
    .trim()
}

/**
 * 从 User-Agent 中识别浏览器名称与主版本号。
 * @param ua 原始 User-Agent
 * @returns 如 `Chrome 131`；无法识别返回 null
 */
function detectBrowser(ua: string): string | null {
  const rules: { pattern: RegExp; name: string }[] = [
    { pattern: /Edg(?:iOS|A)?\/(\d+)/, name: 'Edge' },
    { pattern: /OPR\/(\d+)/, name: 'Opera' },
    { pattern: /Vivaldi\/(\d+)/, name: 'Vivaldi' },
    { pattern: /Chrome\/(\d+)/, name: 'Chrome' },
    { pattern: /Firefox\/(\d+)/, name: 'Firefox' },
    { pattern: /Version\/(\d+)[\d.]*[ ;]*(?:Mobile\/[\d.]+[ ;]*)?Safari\//, name: 'Safari' },
  ]
  for (const rule of rules) {
    const match = ua.match(rule.pattern)
    if (match?.[1]) return `${rule.name} ${match[1]}`
  }
  return null
}

/**
 * 从 User-Agent 中识别操作系统。
 * @param ua 原始 User-Agent
 * @returns 如 `Windows 10/11`、`macOS`；无法识别返回 null
 */
function detectOS(ua: string): string | null {
  if (/Windows NT 10\.0/.test(ua)) return 'Windows 10/11'
  if (/Windows NT 6\.3/.test(ua)) return 'Windows 8.1'
  if (/Windows NT 6\.2/.test(ua)) return 'Windows 8'
  if (/Windows NT 6\.1/.test(ua)) return 'Windows 7'
  if (/Windows NT/.test(ua)) return 'Windows'
  if (/iPhone|iPad|iPod/.test(ua)) return 'iOS'
  if (/Mac OS X/.test(ua)) return 'macOS'
  if (/CrOS/.test(ua)) return 'ChromeOS'
  if (/Android/.test(ua)) return 'Android'
  if (/Linux/.test(ua)) return 'Linux'
  return null
}

/**
 * 将 User-Agent 转换为可读的客户端描述，用于活动日志 / 登录审计展示。
 *
 * 与 `mobile/lib/core/network/client_identity.dart` 的 UA 格式保持一致：
 * - 移动端 App：`Xiaomi 23127PN0CC / Android 14`；
 * - 历史 Flutter 默认 UA（`Dart/x.x (dart:io)`）：`移动端（型号未知）`，
 *   不伪造机型；
 * - 网页端：`Chrome 131 / Windows 10/11`；
 * - 自动化任务等内部标记映射为中文说明；
 * - 完全无法识别时原样返回，避免丢失信息。
 * @param ua 后端返回的 user_agent 原始值
 * @returns 可直接展示的客户端描述；空值返回「—」
 */
export function formatUserAgent(ua?: string | null): string {
  const raw = (ua ?? '').trim()
  if (!raw) return DASH
  if (raw === 'system-auto') return '自动任务'
  if (raw === 'ble-scale') return '蓝牙体脂秤采集'
  if (raw === 'web-bluetooth') return '网页蓝牙称重'
  // Flutter 默认 UA 无法还原机型：明确标注为型号未知，不猜测品牌
  if (raw.startsWith('Dart/') || raw.includes('dart:io')) return '移动端（型号未知）'

  const mobile = raw.match(/^LifeOS(?:[/ ]([^\s(]+))?\s*\(([^)]*)\)/i)
  if (mobile) {
    const [deviceRaw, osRaw] = (mobile[2] ?? '').split(';').map((s) => s.trim())
    const device = deviceRaw && deviceRaw !== 'Android Device' ? deviceRaw : 'Android 设备'
    const os = osRaw || 'Android'
    // 型号与系统都未知时只显示「Android 设备」，避免重复堆叠
    if (device === 'Android 设备' && os === 'Android') return device
    return `${device} / ${os}`
  }

  if (raw.includes('WindowsPowerShell/')) {
    const version = raw.match(/WindowsPowerShell\/(\d+\.\d+)/)?.[1]
    return version ? `PowerShell ${version} / Windows` : 'PowerShell / Windows'
  }

  const browser = detectBrowser(raw)
  const os = detectOS(raw)
  if (browser && os) return `${browser} / ${os}`
  return browser ?? os ?? raw
}

/**
 * 报告摘要去重：后端摘要常以「统计区间 YYYY-MM-DD ~ YYYY-MM-DD，」开头，
 * 而报告卡片副标题已经展示同一区间。这里剥离摘要开头的区间前缀，
 * 保证同一日期只出现一次（副标题保留区间，摘要保留内容）。
 * @param summary 原始报告摘要
 * @returns 去掉重复区间前缀后的摘要
 */
export function reportSummary(summary?: string | null): string {
  if (!summary) return ''
  return summary
    .replace(
      /^统计区间\s*\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}\s*[，,、]?\s*/,
      '',
    )
    .replace(
      /^\d{4}-\d{2}-\d{2}\s*(?:~|至)\s*\d{4}-\d{2}-\d{2}\s*[，,、]?\s*/,
      '',
    )
    .trim()
}
