"use client"

import * as React from "react"
import { Dialog as DialogPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { XIcon } from "lucide-react"

function Dialog({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Root>) {
  return <DialogPrimitive.Root data-slot="dialog" {...props} />
}

function DialogTrigger({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Trigger>) {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

function DialogPortal({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Portal>) {
  return <DialogPrimitive.Portal data-slot="dialog-portal" {...props} />
}

function DialogClose({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Close>) {
  return <DialogPrimitive.Close data-slot="dialog-close" {...props} />
}

function DialogOverlay({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      data-slot="dialog-overlay"
      className={cn(
        "fixed inset-0 isolate z-50 bg-black/10 duration-100 supports-backdrop-filter:backdrop-blur-xs data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
        className
      )}
      {...props}
    />
  )
}

// 全局滚动锁：支持弹窗嵌套，且仅在弹窗真正打开(data-state=open)时锁定，
// 关闭后自动恢复，避免历史遗留的 hidden 导致页面无法滚动。
const scrollLockCount = { value: 0 }
function lockScroll() {
  scrollLockCount.value += 1
  document.documentElement.style.overflow = "hidden"
  document.body.style.overflow = "hidden"
}
function unlockScroll() {
  scrollLockCount.value = Math.max(0, scrollLockCount.value - 1)
  if (scrollLockCount.value === 0) {
    document.documentElement.style.overflow = ""
    document.body.style.overflow = ""
  }
}

function DialogContent({
  className,
  children,
  showCloseButton = true,
  closeOnEscape = false,
  onConfirmEnter = true,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & {
  showCloseButton?: boolean
  closeOnEscape?: boolean
  onConfirmEnter?: boolean
}) {
  const contentRef = React.useRef<React.ComponentRef<typeof DialogPrimitive.Content>>(null)

  // 弹窗打开期间锁定页面滚动；随 data-state 变化锁定/恢复，关闭时确保释放
  React.useEffect(() => {
    const el = contentRef.current
    if (!el) return
    let isOpen = el.getAttribute("data-state") === "open"
    if (isOpen) lockScroll()
    const observer = new MutationObserver(() => {
      const open = el.getAttribute("data-state") === "open"
      if (open === isOpen) return
      if (open) lockScroll()
      else unlockScroll()
      isOpen = open
    })
    observer.observe(el, { attributes: true, attributeFilter: ["data-state"] })
    return () => {
      observer.disconnect()
      if (isOpen) unlockScroll()
    }
  }, [])

  // 回车确认：命中「保存/确认/确定/生成」类主操作按钮
  const onKeyDownCapture = React.useCallback(
    (e: React.KeyboardEvent) => {
      if (!onConfirmEnter || e.key !== 'Enter') return
      const target = e.target as HTMLElement
      if (target instanceof HTMLTextAreaElement) return
      if (target instanceof HTMLButtonElement) return
      if (target instanceof HTMLInputElement || target === e.currentTarget) {
        const content = e.currentTarget as HTMLElement
        const buttons = Array.from(
          content.querySelectorAll<HTMLButtonElement>('button[data-slot="dialog-footer"] button, button[data-confirm-enter]')
        )
        const confirmBtn = buttons
          .filter((b) => !b.closest('[data-close-cancel]'))
          .find((b) => /保存|确认|确定|生成|提交|确定删除|删除/.test(b.textContent ?? ''))
        if (confirmBtn) {
          e.preventDefault()
          confirmBtn.click()
        }
      }
    },
    [onConfirmEnter]
  )

  return (
    <DialogPortal>
      <DialogOverlay />
      <DialogPrimitive.Content
        ref={contentRef}
        data-slot="dialog-content"
        className={cn(
          "fixed top-1/2 left-1/2 z-50 grid w-full max-w-[calc(100%-2rem)] -translate-x-1/2 -translate-y-1/2 gap-4 rounded-xl bg-popover p-4 text-sm text-popover-foreground ring-1 ring-foreground/10 duration-100 outline-none sm:max-w-sm data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        onCloseAutoFocus={(e) => e.preventDefault()}
        onPointerDownOutside={(e) => e.preventDefault()}
        onInteractOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={closeOnEscape ? undefined : (e) => e.preventDefault()}
        onKeyDownCapture={onKeyDownCapture}
        {...props}
      >
        {children}
        {showCloseButton && (
          <DialogPrimitive.Close data-slot="dialog-close" asChild>
            <Button
              variant="ghost"
              className="absolute top-2 right-2"
              size="icon-sm"
            >
              <XIcon
              />
              <span className="sr-only">Close</span>
            </Button>
          </DialogPrimitive.Close>
        )}
      </DialogPrimitive.Content>
    </DialogPortal>
  )
}

function DialogHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="dialog-header"
      className={cn("flex flex-col gap-2", className)}
      {...props}
    />
  )
}

function DialogFooter({
  className,
  showCloseButton = false,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  showCloseButton?: boolean
}) {
  return (
    <div
      data-slot="dialog-footer"
      className={cn(
        "-mx-4 -mb-4 flex flex-col-reverse gap-2 rounded-b-xl border-t bg-muted/50 p-4 sm:flex-row sm:justify-end",
        className
      )}
      {...props}
    >
      {children}
      {showCloseButton && (
        <DialogPrimitive.Close asChild>
          <Button variant="outline">Close</Button>
        </DialogPrimitive.Close>
      )}
    </div>
  )
}

function DialogTitle({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Title>) {
  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      className={cn(
        "font-heading text-base leading-none font-medium",
        className
      )}
      {...props}
    />
  )
}

function DialogDescription({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Description>) {
  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      className={cn(
        "text-sm text-muted-foreground *:[a]:underline *:[a]:underline-offset-3 *:[a]:hover:text-foreground",
        className
      )}
      {...props}
    />
  )
}

export {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
  DialogTrigger,
}
