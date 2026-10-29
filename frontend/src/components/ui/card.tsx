import * as React from "react"

import { cn } from "@/lib/utils"

function Card({
  className,
  size = "default",
  ...props
}: React.ComponentProps<"div"> & { size?: "default" | "sm" }) {
  return (
    <div
      data-slot="card"
      data-size={size}
      className={cn(
        "group/card flex flex-col gap-(--card-spacing) overflow-hidden rounded-xl bg-card py-(--card-spacing) text-sm text-card-foreground ring-1 ring-foreground/10 [--card-spacing:--spacing(4)] has-data-[slot=card-footer]:pb-0 has-[>img:first-child]:pt-0 data-[size=sm]:[--card-spacing:--spacing(3)] data-[size=sm]:has-data-[slot=card-footer]:pb-0 *:[img:first-child]:rounded-t-xl *:[img:last-child]:rounded-b-xl",
        className
      )}
      {...props}
    />
  )
}

function CardHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-header"
      className={cn(
        "group/card-header @container/card-header grid min-w-0 auto-rows-min items-start gap-1 rounded-t-xl px-(--card-spacing) has-data-[slot=card-action]:grid-cols-[1fr_auto] has-data-[slot=card-description]:grid-rows-[auto_auto] [.border-b]:pb-(--card-spacing)",
        className
      )}
      {...props}
    />
  )
}

function CardTitle({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-title"
      className={cn(
        "font-heading text-base leading-snug font-medium group-data-[size=sm]/card:text-sm",
        className
      )}
      {...props}
    />
  )
}

function CardDescription({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

function CardAction({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-action"
      className={cn(
        "col-start-2 row-span-2 row-start-1 self-start justify-self-end",
        className
      )}
      {...props}
    />
  )
}

/**
 * 卡片头部操作区：容纳标题右侧的按钮 / 下拉框等控件。
 * 默认按内容宽度排布并由父级 `justify-between` 右对齐（与改造前视觉一致）；
 * 空间不足（如 <640px）时会收缩并改为单行横向滚动，而不是被卡片的 `overflow-hidden` 裁切掉。
 * 这里不设置 `flex-1`，避免与「标题按钮自带 flex-1」的头部（如报告预览卡）抢占宽度。
 * @param className 附加样式（内容间距 gap 已内置，无需重复传 flex/gap 类）
 * @returns 可横向滚动的操作区容器
 */
function CardHeaderActions({ className, children, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-header-actions"
      className={cn(
        "min-w-0 shrink overflow-x-auto overscroll-x-contain [scrollbar-width:thin]",
        className
      )}
      {...props}
    >
      {/* 内层 w-max：整体宽度不小于内容宽度，超出时由外层滚动；ml-auto 在容器被拉宽时保持右对齐 */}
      <div className="ml-auto flex w-max items-center gap-1.5">{children}</div>
    </div>
  )
}

function CardContent({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-content"
      className={cn("px-(--card-spacing)", className)}
      {...props}
    />
  )
}

function CardFooter({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-footer"
      className={cn(
        "flex items-center rounded-b-xl border-t bg-muted/50 p-(--card-spacing)",
        className
      )}
      {...props}
    />
  )
}

export {
  Card,
  CardHeader,
  CardHeaderActions,
  CardFooter,
  CardTitle,
  CardAction,
  CardDescription,
  CardContent,
}
