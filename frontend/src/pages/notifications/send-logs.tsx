import { useCallback, useEffect, useState } from 'react'
import { Eye, Loader2, RefreshCw } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { useRealtime } from '@/hooks/use-realtime'
import { api, type PageResult } from '@/lib/api'

type NotificationBrief = {
  title: string
  content?: string | null
  category?: string
  source?: string | null
  notify_date?: string | null
}

type Log = {
  id: number
  notification_id: number | null
  channel_type: string
  channel_id: number | null
  channel_name?: string | null
  status: string
  error?: string | null
  sent_at?: string | null
  created_at: string
  notification?: NotificationBrief | null
}

const CHANNEL_LABELS: Record<string, string> = {
  email: '邮件',
  dingtalk: '钉钉',
  feishu: '飞书',
  workwechat: '企业微信',
  tgbot: 'Telegram',
  webhook: 'Webhook',
}

/** 时间格式化：ISO 转 "YYYY-MM-DD HH:mm:ss"，空值返回占位符。 */
function formatTime(v?: string | null) {
  return v ? v.slice(0, 19).replace('T', ' ') : '—'
}

export function SendLogPanel() {
  const realtimeTick = useRealtime(30_000)
  const [logs, setLogs] = useState<Log[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [type, setType] = useState('')
  const [detail, setDetail] = useState<Log | null>(null)
  const pageSize = 10

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const params = new URLSearchParams()
      params.set('page', String(page))
      params.set('page_size', String(pageSize))
      if (status) params.set('status', status)
      if (type) params.set('channel_type', type)
      const res = await api.query<PageResult<Log>>(`/notifications/send-logs?${params.toString()}`)
      setLogs(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }, [page, status, type])

  useEffect(() => {
    load()
  }, [load, realtimeTick])

  const totalPages = Math.max(1, Math.ceil(total / pageSize))

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1) }}>
            <SelectTrigger className="w-32">
              <SelectValue placeholder="状态" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">全部</SelectItem>
              <SelectItem value="sent">成功</SelectItem>
              <SelectItem value="failed">失败</SelectItem>
            </SelectContent>
          </Select>
          <Select value={type} onValueChange={(v) => { setType(v); setPage(1) }}>
            <SelectTrigger className="w-36">
              <SelectValue placeholder="渠道类型" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="">全部</SelectItem>
              <SelectItem value="email">邮件</SelectItem>
              <SelectItem value="dingtalk">钉钉</SelectItem>
              <SelectItem value="feishu">飞书</SelectItem>
              <SelectItem value="workwechat">企业微信</SelectItem>
              <SelectItem value="tgbot">Telegram</SelectItem>
              <SelectItem value="webhook">Webhook</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" size="icon" onClick={load} title="刷新">
            <RefreshCw />
          </Button>
          <span className="text-sm text-muted-foreground">共 {total} 条</span>
        </div>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">发送记录</CardTitle>
          <CardDescription>各渠道外发的历史记录与失败原因，点击记录查看详情</CardDescription>
        </CardHeader>
        <CardContent className={`space-y-2 transition-opacity duration-200 ${loading && logs.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
          {logs.length === 0 ? (
            loading ? (
              <div className="flex justify-center py-12 text-muted-foreground">
                <Loader2 className="size-5 animate-spin" />
              </div>
            ) : (
              <p className="py-12 text-center text-sm text-muted-foreground">暂无发送记录</p>
            )
          ) : (
            logs.map((log) => (
              <div
                key={log.id}
                onClick={() => setDetail(log)}
                title="点击查看详情"
                className="group flex cursor-pointer items-start justify-between gap-3 rounded-lg border px-3 py-2 transition-colors hover:bg-muted/60"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Badge
                      className={
                        log.status === 'sent'
                          ? 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300'
                          : 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300'
                      }
                    >
                      {log.status === 'sent' ? '成功' : '失败'}
                    </Badge>
                    <span className="text-sm font-medium">
                      {CHANNEL_LABELS[log.channel_type] ?? log.channel_type}
                    </span>
                    {log.notification_id != null && (
                      <span className="text-xs text-muted-foreground">
                        通知 #{log.notification_id}
                      </span>
                    )}
                  </div>
                  {log.status === 'failed' && log.error && (
                    <p className="mt-1 line-clamp-2 break-words text-xs text-destructive">{log.error}</p>
                  )}
                </div>
                <div className="flex shrink-0 items-center gap-2 text-xs text-muted-foreground">
                  {log.sent_at ? formatTime(log.sent_at) : formatTime(log.created_at)}
                  <Eye className="size-4 opacity-0 transition-opacity group-hover:opacity-100" />
                </div>
              </div>
            ))
          )}
        </CardContent>
        {totalPages > 1 && (
          <div className="border-t px-4 py-2">
            <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />
          </div>
        )}
      </Card>

      <Dialog open={detail != null} onOpenChange={(open) => { if (!open) setDetail(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>发送详情</DialogTitle>
          </DialogHeader>
          {detail && (
            <>
              <div className="flex items-center gap-2">
                <Badge
                  className={
                    detail.status === 'sent'
                      ? 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300'
                      : 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300'
                  }
                >
                  {detail.status === 'sent' ? '成功' : '失败'}
                </Badge>
                <span className="text-sm font-medium">
                  {CHANNEL_LABELS[detail.channel_type] ?? detail.channel_type}
                  {detail.channel_name ? ` · ${detail.channel_name}` : ''}
                </span>
              </div>
              <div className="space-y-3 text-sm">
                <div>
                  <p className="text-xs text-muted-foreground">通知标题</p>
                  <p className="mt-0.5 break-words font-medium">
                    {detail.notification?.title ?? (detail.notification_id != null ? `通知 #${detail.notification_id}` : '—')}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">通知内容</p>
                  <p className="mt-0.5 whitespace-pre-wrap break-words text-muted-foreground">
                    {detail.notification?.content || '—'}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <p className="text-xs text-muted-foreground">通知分类</p>
                    <p className="mt-0.5 break-words">{detail.notification?.category || '—'}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">通知日期</p>
                    <p className="mt-0.5 break-words">{detail.notification?.notify_date || '—'}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">发送时间</p>
                    <p className="mt-0.5 break-words">{formatTime(detail.sent_at)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">记录时间</p>
                    <p className="mt-0.5 break-words">{formatTime(detail.created_at)}</p>
                  </div>
                </div>
                {detail.status === 'failed' && detail.error && (
                  <div>
                    <p className="text-xs text-muted-foreground">失败原因</p>
                    <p className="mt-0.5 whitespace-pre-wrap break-words text-destructive">
                      {detail.error}
                    </p>
                  </div>
                )}
              </div>
            </>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setDetail(null)}>关闭</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
