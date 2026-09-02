import { useCallback, useRef, useState, type ReactNode } from 'react'
import { TriangleAlert } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

export type ConfirmOptions = {
  title?: string
  description?: ReactNode
  confirmText?: string
  cancelText?: string
  danger?: boolean
}

/**
 * 全局二次确认：返回 { confirm, dialog }。
 * 调用 `await confirm('提示文案')` 或 `await confirm({...})`，
 * 将渲染一个样式化确认弹窗，返回 Promise<boolean>。
 */
export function useConfirm(defaultOptions: ConfirmOptions = {}) {
  const [state, setState] = useState<{ open: boolean; options: ConfirmOptions }>({
    open: false,
    options: defaultOptions,
  })
  const resolver = useRef<((v: boolean) => void) | null>(null)

  const confirm = useCallback(
    (opts?: string | ConfirmOptions): Promise<boolean> => {
      const options: ConfirmOptions =
        typeof opts === 'string' ? { description: opts } : opts ?? defaultOptions
      setState({ open: true, options })
      return new Promise<boolean>((resolve) => {
        resolver.current = resolve
      })
    },
    [defaultOptions],
  )

  const close = useCallback((value: boolean) => {
    setState((s) => ({ ...s, open: false }))
    resolver.current?.(value)
    resolver.current = null
  }, [])

  const dialog = (
    <Dialog open={state.open} onOpenChange={(o) => !o && close(false)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <TriangleAlert className="size-5 shrink-0 text-destructive" />
            <DialogTitle>{state.options.title ?? '确认操作'}</DialogTitle>
          </div>
          <DialogDescription className="pt-1">
            {state.options.description ?? '确定执行该操作吗？此操作不可撤销。'}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => close(false)}>
            {state.options.cancelText ?? '取消'}
          </Button>
          <Button
            variant={state.options.danger === false ? 'default' : 'destructive'}
            onClick={() => close(true)}
          >
            {state.options.confirmText ?? '确认删除'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )

  return { confirm, dialog }
}