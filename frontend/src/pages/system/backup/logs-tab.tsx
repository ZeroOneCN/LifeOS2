import { type Dispatch, type SetStateAction } from 'react'
import { Eraser, Loader2, ScrollText } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { PaginationBar } from '@/components/ui/pagination-bar'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Tip } from '@/components/ui/tip'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'
import { DASH } from '@/lib/format'

import { formatTime, type LogItem } from './shared'

type LogsTabProps = {
  // 当前页码由页面持有，切换 Tab 后不重置（与原单组件行为一致）
  logPage: number
  setLogPage: Dispatch<SetStateAction<number>>
  // 列表数据由页面层的统一轮询提供
  logs: LogItem[]
  logTotal: number
  loadingLogs: boolean
  /** 清除日志后复位页面层缓存 */
  resetLogs: () => void
}

export function LogsTab({ logPage, setLogPage, logs, logTotal, loadingLogs, resetLogs }: LogsTabProps) {
  const { confirm, dialog: confirmDialog } = useConfirm()
  const logPageSize = 10

  const handleClearLogs = async () => {
    const ok = await confirm({
      title: '清除执行日志',
      description: '确定要清除全部备份执行日志吗？此操作不可撤销，但不会删除已生成的备份文件。',
      confirmText: '确认清除',
      danger: true,
    })
    if (!ok) return
    try {
      const res = await api.del<{ deleted: number }>('/backup/logs')
      toast.success(`已清除 ${res.deleted} 条执行日志`)
      resetLogs()
      setLogPage(1)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '清除日志失败')
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <ScrollText className="h-5 w-5" />
            备份执行日志
          </CardTitle>
          <CardDescription>
            查看每次自动/手动备份的执行结果，共 {logTotal} 条记录
          </CardDescription>
          <CardAction>
            <Button
              variant="outline"
              size="sm"
              className="text-destructive hover:text-destructive"
              disabled={logTotal === 0}
              onClick={handleClearLogs}
            >
              <Eraser className="mr-1 h-4 w-4" />
              清除日志
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent>
          {logs.length === 0 && loadingLogs ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : logs.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
              <ScrollText className="mb-2 h-10 w-10" />
              <p>暂无备份日志</p>
              <p className="text-xs">执行数据导出或定时备份后，执行记录将出现在这里</p>
            </div>
          ) : (
            <div
              className={`overflow-x-auto transition-opacity ${
                loadingLogs ? 'pointer-events-none opacity-60' : ''
              }`}
            >
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[180px]">任务</TableHead>
                    <TableHead className="w-16">格式</TableHead>
                    <TableHead className="w-56">文件名</TableHead>
                    <TableHead className="w-[110px]">结果</TableHead>
                    <TableHead className="w-[150px]">执行时间</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {logs.map((l) => (
                    <TableRow key={l.id}>
                      <Tip label={l.name}>
                        <TableCell className="max-w-[180px] truncate font-medium">
                          {l.name}
                        </TableCell>
                      </Tip>
                      <TableCell>
                        <Badge variant="outline" className="font-mono text-xs uppercase">
                          {l.export_format}
                        </Badge>
                      </TableCell>
                      <Tip label={l.filename || ''}>
                        <TableCell className="max-w-[200px] truncate font-mono text-xs">
                          {l.filename || DASH}
                        </TableCell>
                      </Tip>
                      <TableCell>
                        {l.status === 'success' ? (
                          <div className="flex items-center gap-1.5">
                            <Badge className="bg-success-muted text-success-muted-foreground">
                              成功
                            </Badge>
                            {l.file_size_display && (
                              <span className="text-xs text-muted-foreground">{l.file_size_display}</span>
                            )}
                          </div>
                        ) : (
                          <Tip label={l.error_message || '执行失败'}>
                            <Badge variant="destructive" className="cursor-help">
                              失败
                            </Badge>
                          </Tip>
                        )}
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground whitespace-nowrap">
                        {formatTime(l.started_at)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          {/* 分页 */}
          {logTotal > logPageSize && (
            <div className="mt-4">
              <PaginationBar
                page={logPage}
                totalPages={Math.max(1, Math.ceil(logTotal / logPageSize))}
                total={logTotal}
                onPageChange={setLogPage}
              />
            </div>
          )}
        </CardContent>
      </Card>
      {confirmDialog}
    </div>
  )
}
