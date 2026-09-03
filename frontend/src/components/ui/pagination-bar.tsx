import { useState } from 'react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

type PaginationBarProps = {
  page: number
  totalPages: number
  onPageChange: (page: number) => void
  total?: number
  className?: string
}

/**
 * 统一分页栏：首页 / 上一页 / 页码指示 / 下一页 / 末页 / 输入页码跳转。
 */
export function PaginationBar({ page, totalPages, onPageChange, total, className }: PaginationBarProps) {
  const [value, setValue] = useState('')

  const jump = () => {
    const n = Number(value)
    setValue('')
    if (!Number.isInteger(n) || n < 1) return
    const target = Math.min(n, totalPages)
    if (target !== page) onPageChange(target)
  }

  return (
    <div
      className={`flex w-full flex-wrap items-center justify-between gap-2 text-sm text-muted-foreground ${className ?? ''}`}
    >
      {total != null && <span>共 {total} 条记录</span>}
      <div className="flex flex-wrap items-center gap-1.5">
        <Button
          variant="outline"
          size="sm"
          disabled={page <= 1}
          onClick={() => onPageChange(1)}
        >
          首页
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={page <= 1}
          onClick={() => onPageChange(page - 1)}
        >
          上一页
        </Button>
        <span className="min-w-16 text-center">
          {page} / {totalPages}
        </span>
        <Button
          variant="outline"
          size="sm"
          disabled={page >= totalPages}
          onClick={() => onPageChange(page + 1)}
        >
          下一页
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={page >= totalPages}
          onClick={() => onPageChange(totalPages)}
        >
          末页
        </Button>
        <div className="ml-1 flex items-center gap-1.5">
          <Input
            className="h-8 w-14"
            type="number"
            min={1}
            max={totalPages}
            placeholder="页码"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') jump()
            }}
          />
          <Button variant="outline" size="sm" onClick={jump}>
            跳转
          </Button>
        </div>
      </div>
    </div>
  )
}
