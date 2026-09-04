import * as React from 'react'
import { Popover as PopoverPrimitive } from 'radix-ui'
import { CalendarIcon, ChevronLeftIcon, ChevronRightIcon } from 'lucide-react'

import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'

const MONTHS = ['1月','2月','3月','4月','5月','6月','7月','8月','9月','10月','11月','12月']

function parseValue(v: string | undefined): Date | null {
  if (!v) return null
  const m = /^(\d{4})-(\d{2})/.exec(v)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, 1)
}

/**
 * 主题化月份选择器，仅选择年月（不选到日）。
 * value/onChange 使用 "YYYY-MM-01" 字符串（首日），与后端 date 字段一致。
 */
export function MonthPicker({
  value,
  onChange,
  placeholder = '选择月份',
  className,
  id,
}: {
  value?: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
  id?: string
}) {
  const [open, setOpen] = React.useState(false)
  const selected = React.useMemo(() => parseValue(value), [value])
  const today = React.useMemo(() => new Date(), [])
  const [view, setView] = React.useState(() => {
    const base = selected ?? today
    return { y: base.getFullYear() }
  })

  const handleOpenChange = (o: boolean) => {
    setOpen(o)
    if (o) setView({ y: (selected ?? today).getFullYear() })
  }

  const pick = (y: number, m: number) => {
    onChange(`${y}-${String(m).padStart(2, '0')}-01`)
    setOpen(false)
  }

  return (
    <PopoverPrimitive.Root open={open} onOpenChange={handleOpenChange}>
      <PopoverPrimitive.Trigger asChild>
        <Button
          type="button"
          variant="outline"
          id={id}
          className={cn(
            'h-8 w-full justify-between px-2.5 font-normal',
            !selected && 'text-muted-foreground',
            className,
          )}
        >
          <span className="truncate">
            {selected ? `${selected.getFullYear()}年${selected.getMonth() + 1}月` : placeholder}
          </span>
          <CalendarIcon className="size-4 shrink-0 text-muted-foreground" />
        </Button>
      </PopoverPrimitive.Trigger>
      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align="start"
          sideOffset={6}
          className={cn(
            'z-50 w-64 rounded-lg bg-popover p-3 text-popover-foreground shadow-md ring-1 ring-foreground/10',
            'duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95',
          )}
        >
          <div className="mb-2 flex items-center justify-between">
            <Button type="button" variant="ghost" size="icon-sm" onClick={() => setView((v) => ({ y: v.y - 1 }))} aria-label="上一年">
              <ChevronLeftIcon />
            </Button>
            <span className="text-sm font-medium">{view.y}年</span>
            <Button type="button" variant="ghost" size="icon-sm" onClick={() => setView((v) => ({ y: v.y + 1 }))} aria-label="下一年">
              <ChevronRightIcon />
            </Button>
          </div>
          <div className="grid grid-cols-3 gap-1.5">
            {MONTHS.map((label, i) => {
              const same = selected && selected.getFullYear() === view.y && selected.getMonth() === i
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => pick(view.y, i)}
                  className={cn(
                    'rounded-md px-2 py-2 text-sm transition-colors hover:bg-accent hover:text-accent-foreground',
                    same && 'bg-primary font-medium text-primary-foreground hover:bg-primary hover:text-primary-foreground',
                  )}
                >
                  {label}
                </button>
              )
            })}
          </div>
          <div className="mt-2 flex items-center justify-end border-t pt-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => pick(today.getFullYear(), today.getMonth())}
            >
              本月
            </Button>
          </div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  )
}