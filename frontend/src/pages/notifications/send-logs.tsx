import { useCallback, useEffect, useState } from 'react'
import { Loader2, RefreshCw } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { api, type PageResult } from '@/lib/api'

type Log = {
  id: number
  notification_id: number | null
  channel_type: string
  channel_id: number | null
  status: string
  error?: string | null
  sent_at?: string | null
  created_at: string
}

export function SendLogPanel() {
  const [logs, setLogs] = useState<Log[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [type, setType] = useState('')
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
  }, [load])

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
          <CardDescription>各渠道外发的历史记录与失败原因</CardDescription>
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
              <div key={log.id} className="flex items-start justify-between gap-3 rounded-lg border px-3 py-2">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Badge
                      className={
                        log.status === 'sent'
                          ? 'bg-green-100 text-green-700'
                          : 'bg-red-100 text-red-700'
                      }
                    >
                      {log.status === 'sent' ? '成功' : '失败'}
                    </Badge>
                    <span className="text-sm font-medium">{log.channel_type}</span>
                    {log.notification_id != null && (
                      <span className="text-xs text-muted-foreground">
                        通知 #{log.notification_id}
                      </span>
                    )}
                  </div>
                  {log.status === 'failed' && log.error && (
                    <p className="mt-1 break-words text-xs text-destructive">{log.error}</p>
                  )}
                </div>
                <div className="shrink-0 text-xs text-muted-foreground">
                  {log.sent_at ? log.sent_at.slice(0, 19).replace('T', ' ') : log.created_at.slice(0, 19).replace('T', ' ')}
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
    </div>
  )
}