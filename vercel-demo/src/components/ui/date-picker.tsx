import * as React from 'react'
import { Popover as PopoverPrimitive } from 'radix-ui'
import {
  CalendarIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from 'lucide-react'

import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'

/** 星期表头：周一开头，中文 */
const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日']

/** 月份网格标签 */
const MONTHS = ['1月','2月','3月','4月','5月','6月','7月','8月','9月','10月','11月','12月']

function parseValue(v: string | undefined): Date | null {
  if (!v) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}

function toValue(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/** 中文日期，如 2026年9月3日 */
function formatCn(d: Date): string {
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}

function isSameDay(a: Date | null, b: Date | null): boolean {
  if (!a || !b) return false
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  )
}

/**
 * 主题化中文日期选择器，支持年/月/日三级快捷切换。
 * value/onChange 均使用 "YYYY-MM-DD" 字符串，与原有表单逻辑保持一致。
 */
export function DatePicker({
  value,
  onChange,
  placeholder = '选择日期',
  className,
  disabled,
  id,
}: {
  value?: string
  onChange: (value: string) => void
  placeholder?: string
  className?: string
  disabled?: boolean
  id?: string
}) {
  const [open, setOpen] = React.useState(false)
  const selected = React.useMemo(() => parseValue(value), [value])
  const today = React.useMemo(() => startOfDay(new Date()), [])
  // mode: date=选日  month=选月  year=选年
  const [mode, setMode] = React.useState<'date' | 'month' | 'year'>('date')
  const [view, setView] = React.useState(() => {
    const base = selected ?? today
    return { y: base.getFullYear(), m: base.getMonth() }
  })

  // 打开时定位到已选日期所在年月（无选中则当月），并回到选日视图
  const handleOpenChange = (o: boolean) => {
    setOpen(o)
    if (o) {
      const base = selected ?? today
      setView({ y: base.getFullYear(), m: base.getMonth() })
      setMode('date')
    }
  }

  const prevMonth = () =>
    setView((v) => (v.m === 0 ? { y: v.y - 1, m: 11 } : { y: v.y, m: v.m - 1 }))
  const nextMonth = () =>
    setView((v) => (v.m === 11 ? { y: v.y + 1, m: 0 } : { y: v.y, m: v.m + 1 }))
  const prevYear = () => setView((v) => ({ ...v, y: v.y - 1 }))
  const nextYear = () => setView((v) => ({ ...v, y: v.y + 1 }))
  // 年份视图：以 10 年为一个区间翻页
  const yearStart = Math.floor(view.y / 10) * 10
  const prevDecade = () => setView((v) => ({ ...v, y: v.y - 10 }))
  const nextDecade = () => setView((v) => ({ ...v, y: v.y + 10 }))

  const firstDayCol = (new Date(view.y, view.m, 1).getDay() + 6) % 7 // 周一为第 0 列
  const daysInMonth = new Date(view.y, view.m + 1, 0).getDate()
  const cells: (number | null)[] = [
    ...Array.from({ length: firstDayCol }, () => null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]

  return (
    <PopoverPrimitive.Root open={open} onOpenChange={handleOpenChange}>
      <PopoverPrimitive.Trigger asChild disabled={disabled}>
        <Button
          type="button"
          variant="outline"
          disabled={disabled}
          id={id}
          className={cn(
            'h-8 w-full justify-between px-2.5 font-normal',
            !selected && 'text-muted-foreground',
            className,
          )}
        >
          <span className="truncate">
            {selected ? formatCn(selected) : placeholder}
          </span>
          <CalendarIcon className="size-4 shrink-0 text-muted-foreground" />
        </Button>
      </PopoverPrimitive.Trigger>
      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align="start"
          sideOffset={6}
          className={cn(
            'z-50 w-72 rounded-lg bg-popover p-3 text-popover-foreground shadow-md ring-1 ring-foreground/10',
            'duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95',
          )}
        >
          {/* 导航：标题可点击切换 日→月→年 */}
          <div className="mb-2 flex items-center justify-between">
            {mode === 'date' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={prevMonth} aria-label="上个月">
                <ChevronLeftIcon />
              </Button>
            )}
            {mode === 'month' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={prevYear} aria-label="上一年">
                <ChevronLeftIcon />
              </Button>
            )}
            {mode === 'year' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={prevDecade} aria-label="上一个十年">
                <ChevronLeftIcon />
              </Button>
            )}
            {mode === 'date' ? (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setMode('month')}
                aria-label="选择月份"
                className="font-medium"
              >
                {view.y}年{view.m + 1}月
              </Button>
            ) : mode === 'month' ? (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setMode('year')}
                aria-label="选择年份"
                className="font-medium"
              >
                {view.y}年
              </Button>
            ) : (
              <span className="px-3 text-sm font-medium">
                {yearStart} - {yearStart + 11}
              </span>
            )}
            {mode === 'date' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={nextMonth} aria-label="下个月">
                <ChevronRightIcon />
              </Button>
            )}
            {mode === 'month' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={nextYear} aria-label="下一年">
                <ChevronRightIcon />
              </Button>
            )}
            {mode === 'year' && (
              <Button type="button" variant="ghost" size="icon-sm" onClick={nextDecade} aria-label="下一个十年">
                <ChevronRightIcon />
              </Button>
            )}
          </div>

          {mode === 'date' && (
            <>
              {/* 星期表头 */}
              <div className="grid grid-cols-7 text-center">
                {WEEKDAYS.map((w) => (
                  <div key={w} className="py-1 text-xs text-muted-foreground">
                    {w}
                  </div>
                ))}
              </div>
              {/* 日期网格 */}
              <div className="grid grid-cols-7 gap-0.5">
                {cells.map((d, i) =>
                  d === null ? (
                    <div key={`e-${i}`} className="size-8" />
                  ) : (
                    <button
                      key={d}
                      type="button"
                      onClick={() => {
                        onChange(toValue(new Date(view.y, view.m, d)))
                        setOpen(false)
                      }}
                      className={cn(
                        'flex size-8 items-center justify-center rounded-md text-sm transition-colors',
                        'hover:bg-accent hover:text-accent-foreground',
                        isSameDay(selected, new Date(view.y, view.m, d)) &&
                          'bg-primary font-medium text-primary-foreground hover:bg-primary hover:text-primary-foreground',
                        !isSameDay(selected, new Date(view.y, view.m, d)) &&
                          isSameDay(today, new Date(view.y, view.m, d)) &&
                          'ring-1 ring-primary ring-inset',
                      )}
                    >
                      {d}
                    </button>
                  ),
                )}
              </div>
            </>
          )}

          {mode === 'month' && (
            <div className="grid grid-cols-4 gap-1.5 py-1">
              {MONTHS.map((label, i) => {
                const same = selected && selected.getFullYear() === view.y && selected.getMonth() === i
                return (
                  <button
                    key={label}
                    type="button"
                    onClick={() => {
                      setView((v) => ({ ...v, m: i }))
                      setMode('date')
                    }}
                    className={cn(
                      'rounded-md py-2 text-sm transition-colors',
                      'hover:bg-accent hover:text-accent-foreground',
                      same && 'bg-primary font-medium text-primary-foreground hover:bg-primary hover:text-primary-foreground',
                    )}
                  >
                    {label}
                  </button>
                )
              })}
            </div>
          )}

          {mode === 'year' && (
            <div className="grid grid-cols-4 gap-1.5 py-1">
              {Array.from({ length: 12 }, (_, i) => yearStart + i).map((yr) => {
                const same = selected && selected.getFullYear() === yr
                return (
                  <button
                    key={yr}
                    type="button"
                    onClick={() => {
                      setView((v) => ({ ...v, y: yr }))
                      setMode('month')
                    }}
                    className={cn(
                      'rounded-md py-2 text-sm transition-colors',
                      'hover:bg-accent hover:text-accent-foreground',
                      same && 'bg-primary font-medium text-primary-foreground hover:bg-primary hover:text-primary-foreground',
                    )}
                  >
                    {yr}
                  </button>
                )
              })}
            </div>
          )}

          {/* 底部操作：选日视图显示选中日期与"今天" */}
          {mode === 'date' && (
            <div className="mt-2 flex items-center justify-between border-t pt-2">
              <span className="text-xs text-muted-foreground">
                {selected ? formatCn(selected) : '未选择'}
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  onChange(toValue(today))
                  setOpen(false)
                }}
              >
                今天
              </Button>
            </div>
          )}
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  )
}
