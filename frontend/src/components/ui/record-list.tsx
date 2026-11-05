import type { ElementType, ReactNode } from 'react'

import { cn } from '@/lib/utils'

/**
 * 记录行统一规格：最小高度 56px、左右/上下内边距 16px/12px。
 * 表格类记录列表用同等的内边距（`px-4 py-4`）与整块分隔线保持视觉一致。
 */
export const RECORD_ROW_CLASS = 'min-h-14 px-4 py-3'

/**
 * 记录列表容器：整块边框 + 行间分隔线，替代逐条圆角卡片。
 * @param as 语义标签，日志类用 ol、普通列表用 ul、无序号结构用 div
 */
export function RecordList({
  as: Tag = 'ol',
  className,
  children,
}: {
  as?: ElementType
  className?: string
  children: ReactNode
}) {
  return (
    <Tag className={cn('divide-y overflow-hidden rounded-lg border bg-card', className)}>
      {children}
    </Tag>
  )
}
