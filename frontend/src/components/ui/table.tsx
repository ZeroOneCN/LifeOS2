"use client"

import * as React from "react"

import { cn } from "@/lib/utils"

/** 吸附列：横向滚动时保持可见。配合不透明背景，避免下方内容透出。 */
export const stickyLeftClass = "sticky left-0 z-10 bg-card"
/** 吸附操作列：右侧吸附并带左侧阴影，提示内容已滚到列边界。 */
export const stickyRightClass =
  "sticky right-0 z-10 bg-card shadow-[-6px_0_8px_-6px_rgba(0,0,0,0.18)]"

function Table({ className, ...props }: React.ComponentProps<"table">) {
  const scrollRef = React.useRef<HTMLDivElement>(null)
  const [edges, setEdges] = React.useState({ left: false, right: false, overflow: false })

  React.useEffect(() => {
    const el = scrollRef.current
    if (!el) return
    const update = () => {
      const max = el.scrollWidth - el.clientWidth
      setEdges({
        left: el.scrollLeft > 1,
        right: max - el.scrollLeft > 1,
        overflow: max > 1,
      })
    }
    update()
    el.addEventListener("scroll", update, { passive: true })
    const ro = new ResizeObserver(update)
    ro.observe(el)
    if (el.firstElementChild) ro.observe(el.firstElementChild)
    return () => {
      el.removeEventListener("scroll", update)
      ro.disconnect()
    }
  }, [])

  return (
    <div className="w-full">
      <div className="relative w-full">
        <div
          ref={scrollRef}
          data-slot="table-container"
          className="w-full overflow-x-auto"
        >
          <table
            data-slot="table"
            className={cn("w-full caption-bottom text-sm", className)}
            {...props}
          />
        </div>
        {edges.left && (
          <div className="pointer-events-none absolute inset-y-0 left-0 w-6 bg-gradient-to-r from-card to-transparent" />
        )}
        {edges.right && (
          <div className="pointer-events-none absolute inset-y-0 right-0 w-6 bg-gradient-to-l from-card to-transparent" />
        )}
      </div>
      {edges.overflow && (
        <p className="mt-1 text-right text-xs text-muted-foreground sm:hidden">左右滑动查看更多</p>
      )}
    </div>
  )
}

function TableHeader({ className, ...props }: React.ComponentProps<"thead">) {
  return (
    <thead
      data-slot="table-header"
      className={cn("[&_tr]:border-b", className)}
      {...props}
    />
  )
}

function TableBody({ className, ...props }: React.ComponentProps<"tbody">) {
  return (
    <tbody
      data-slot="table-body"
      className={cn("[&_tr:last-child]:border-0", className)}
      {...props}
    />
  )
}

function TableFooter({ className, ...props }: React.ComponentProps<"tfoot">) {
  return (
    <tfoot
      data-slot="table-footer"
      className={cn(
        "border-t bg-muted/50 font-medium [&>tr]:last:border-b-0",
        className
      )}
      {...props}
    />
  )
}

function TableRow({ className, ...props }: React.ComponentProps<"tr">) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        "border-b transition-colors hover:bg-muted/50 has-aria-expanded:bg-muted/50 data-[state=selected]:bg-muted",
        className
      )}
      {...props}
    />
  )
}

function TableHead({ className, ...props }: React.ComponentProps<"th">) {
  return (
    <th
      data-slot="table-head"
      className={cn(
        "h-10 px-2 text-left align-middle font-medium whitespace-nowrap text-foreground [&:has([role=checkbox])]:pr-0",
        className
      )}
      {...props}
    />
  )
}

function TableCell({ className, ...props }: React.ComponentProps<"td">) {
  return (
    <td
      data-slot="table-cell"
      className={cn(
        "p-2 align-middle whitespace-nowrap [&:has([role=checkbox])]:pr-0",
        className
      )}
      {...props}
    />
  )
}

function TableCaption({
  className,
  ...props
}: React.ComponentProps<"caption">) {
  return (
    <caption
      data-slot="table-caption"
      className={cn("mt-4 text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export {
  Table,
  TableHeader,
  TableBody,
  TableFooter,
  TableHead,
  TableRow,
  TableCell,
  TableCaption,
}
