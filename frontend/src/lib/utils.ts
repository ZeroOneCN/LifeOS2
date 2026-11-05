import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/** 日期时间格式化统一由 lib/format.ts 提供，此处仅保留旧导入路径的转发。 */
export { formatDateTime } from "./format"
