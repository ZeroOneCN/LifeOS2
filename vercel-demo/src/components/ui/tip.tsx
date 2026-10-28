import * as React from 'react'
import { HelpCircle } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

type Side = 'top' | 'right' | 'bottom' | 'left'

/**
 * 悬停气泡提示：包裹任意可接收 ref 的元素，鼠标悬停时以带样式的气泡展示文字。
 * 用于替代浏览器原生 title 提示（例如按钮的动作说明），保证全站悬停样式统一。
 * 若包裹的是本项目的 Button，则直接透传 tip 属性（Button 内部已统一挂载提示），
 * 避免出现内外两层气泡。
 * @param label 悬停时展示的文字
 * @param children 触发元素（如 Button、Link、span、div 等）
 * @param side 气泡出现方向，默认 top
 * @returns 带样式 Tooltip 的包裹元素
 */
export function Tip({
  label,
  children,
  side = 'top',
}: {
  label: string
  children: React.ReactNode
  side?: Side
}) {
  if (React.isValidElement(children) && children.type === Button) {
    return React.cloneElement(
      children as React.ReactElement<{ tip?: string; tipSide?: Side }>,
      { tip: label, tipSide: side },
    )
  }

  return (
    <Tooltip>
      <TooltipTrigger asChild>{children}</TooltipTrigger>
      <TooltipContent side={side}>{label}</TooltipContent>
    </Tooltip>
  )
}

/**
 * 说明提示：问号图标 + 悬停气泡，用于解释字段 / 术语等小字说明，避免说明文字单独占用一行。
 * @param text 悬停时展示的解释内容
 * @param side 气泡出现方向，默认 top
 * @returns 绑定 Tooltip 的问号图标
 */
export function Hint({ text, side = 'top' }: { text: string; side?: Side }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <HelpCircle className="size-3.5 shrink-0 cursor-help text-muted-foreground" />
      </TooltipTrigger>
      <TooltipContent side={side}>{text}</TooltipContent>
    </Tooltip>
  )
}
