import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"

/** 气泡出现方向 */
type TipSide = "top" | "right" | "bottom" | "left"

/**
 * 递归提取子节点中的文本，用于未显式提供提示时自动生成悬停文案。
 * 只深入原生标签（如 span），不解析自定义组件，避免把图标组件内部文字误当按钮名称。
 * @param node React 子节点
 * @returns 提取到的文本（空白已压缩），无文本时返回空字符串
 */
function extractText(node: React.ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node)
  if (Array.isArray(node)) return node.map(extractText).join("")
  if (React.isValidElement(node) && typeof node.type === "string") {
    return extractText((node.props as { children?: React.ReactNode }).children)
  }
  return ""
}

const buttonVariants = cva(
  "group/button inline-flex shrink-0 items-center justify-center rounded-lg border border-transparent bg-clip-padding text-sm font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/80",
        outline:
          "border-border bg-background hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-[color-mix(in_oklch,var(--secondary),var(--foreground)_5%)] aria-expanded:bg-secondary aria-expanded:text-secondary-foreground",
        ghost:
          "hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:hover:bg-muted/50",
        destructive:
          "bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30 dark:focus-visible:ring-destructive/40",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default:
          "h-8 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        xs: "h-6 gap-1 rounded-[min(var(--radius-md),10px)] px-2 text-xs in-data-[slot=button-group]:rounded-lg has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3",
        sm: "h-7 gap-1 rounded-[min(var(--radius-md),12px)] px-2.5 text-[0.8rem] in-data-[slot=button-group]:rounded-lg has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3.5",
        lg: "h-9 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        icon: "size-8",
        "icon-xs":
          "size-6 rounded-[min(var(--radius-md),10px)] in-data-[slot=button-group]:rounded-lg [&_svg:not([class*='size-'])]:size-3",
        "icon-sm":
          "size-7 rounded-[min(var(--radius-md),12px)] in-data-[slot=button-group]:rounded-lg",
        "icon-lg": "size-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

/**
 * 通用按钮：全站所有按钮都经由此组件渲染，因此在此统一挂载悬停气泡提示。
 * 提示文案优先级：显式 `tip` > `aria-label` > `title` > 按钮可见文本。
 * `title` 被用作提示来源后不再透传到 DOM，避免浏览器原生提示与样式气泡重复出现。
 * 以下情况不挂载提示：`asChild`（子元素不确定）、禁用态（无指针事件）、无可用文案。
 * @param tip 显式指定的悬停提示文案
 * @param tipSide 气泡出现方向，默认 top
 * @returns 带样式悬停提示的按钮（无法提示时返回普通按钮）
 */
function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  tip,
  tipSide = "top",
  title,
  disabled,
  children,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean
    tip?: string
    tipSide?: TipSide
  }) {
  const Comp = asChild ? Slot.Root : "button"

  // 显式文案（图标按钮通常用 aria-label / title 提供）
  const explicitTip = tip ?? (props["aria-label"] as string | undefined) ?? title
  // 兜底文案：按钮自身的可见文字（文字按钮），超过 40 字不展示
  const textTip = explicitTip
    ? undefined
    : extractText(children).replace(/\s+/g, " ").trim()
  const finalTip =
    explicitTip || (textTip && textTip.length <= 40 ? textTip : undefined)

  const content = (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      disabled={disabled}
      {...props}
    >
      {children}
    </Comp>
  )

  if (!finalTip || asChild || disabled) return content

  return (
    <Tooltip delayDuration={explicitTip ? 0 : 300}>
      <TooltipTrigger asChild>{content}</TooltipTrigger>
      <TooltipContent side={tipSide}>{finalTip}</TooltipContent>
    </Tooltip>
  )
}

export { Button, buttonVariants }
