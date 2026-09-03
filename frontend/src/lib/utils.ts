import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * 统一格式化日期时间字符串（ISO，如 `2026-09-03T01:29:53`）为 `YYYY-MM-DD HH:mm`。
 * 若传入已是纯日期（如 `2026-09-03`）则原样返回。无效输入返回空串或原样。
 */
export function formatDateTime(value?: string | number | Date | null): string {
  if (value === null || value === undefined || value === "") return ""
  // 已是纯日期（YYYY-MM-DD）直接返回，避免补 00:00
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value
  const d = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(d.getTime())) return typeof value === "string" ? value : ""
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
