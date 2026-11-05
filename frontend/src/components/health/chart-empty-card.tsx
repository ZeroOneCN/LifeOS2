import type { ReactNode } from 'react'
import { Inbox } from 'lucide-react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

/**
 * 图表空数据占位卡：保留卡片标题与记录入口，整体高度压到 120px，
 * 避免无数据时仍渲染一整块只有坐标轴的空白图表。
 *
 * 单独放在无 recharts 依赖的模块中，供图表门面在数据为空时直接渲染，
 * 这样空态不会先闪一次 240px 的图表骨架再塌缩。
 *
 * @param title 卡片标题，保持与有数据时一致，便于用户知道缺的是哪张图
 * @param message 一句空态说明，默认提示记录后可见趋势
 * @param action 记录入口按钮（由页面传入，未传时只展示说明）
 */
export function ChartEmptyCard({
  title,
  message = '暂无数据，记录后即可查看趋势',
  action,
}: {
  title: string
  message?: string
  action?: ReactNode
}) {
  return (
    <Card className="flex h-[120px] flex-col gap-0 py-0">
      <CardHeader className="px-4 pb-1 pt-3">
        <CardTitle className="truncate text-sm font-medium text-muted-foreground">{title}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-1 items-center justify-between gap-3 px-4 pb-3 pt-0">
        <div className="flex min-w-0 items-center gap-2">
          <Inbox className="size-5 shrink-0 text-muted-foreground" />
          <p className="line-clamp-2 text-sm text-muted-foreground" title={message}>{message}</p>
        </div>
        {action && <div className="shrink-0">{action}</div>}
      </CardContent>
    </Card>
  )
}
