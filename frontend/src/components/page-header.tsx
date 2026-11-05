import type { ReactNode } from 'react'

import { cn } from '@/lib/utils'

type PageHeaderProps = {
  /** 页面主标题（纯文本，统一由组件控制标题样式） */
  title: string
  /** 标题下的说明文案，可省略 */
  description?: ReactNode
  /** 右侧操作区（按钮等），375 下保持右对齐并可换行 */
  actions?: ReactNode
  /** 附加样式类，用于少量页面级微调 */
  className?: string
}

/**
 * 全站统一页头：标题字号、字重、字距与页头到首块内容的间距都收敛到这里。
 * 统一规格：`font-heading text-2xl font-semibold tracking-tight`，说明文字 `text-sm`。
 * @param title 页面主标题
 * @param description 标题下的说明文案
 * @param actions 右侧操作区
 * @param className 附加样式类
 * @returns 统一页头区块
 */
export function PageHeader({ title, description, actions, className }: PageHeaderProps) {
  return (
    <section className={cn('flex flex-wrap items-end justify-between gap-3', className)}>
      <div className="min-w-0 space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">{title}</h1>
        {description ? <p className="text-sm text-muted-foreground">{description}</p> : null}
      </div>
      {actions ? (
        <div className="flex flex-wrap items-center justify-end gap-2">{actions}</div>
      ) : null}
    </section>
  )
}
