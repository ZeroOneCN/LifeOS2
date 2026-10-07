import { useCallback, useEffect, useState } from 'react'
import { Loader2, LogOut, Monitor, RefreshCw } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Skeleton } from '@/components/ui/skeleton'
import { api } from '@/lib/api'

type UserSession = {
  id: number
  device: string | null
  ip_address: string | null
  created_at: string
  last_used_at: string
  expires_at: string
  is_current: boolean
}

/** 格式化 ISO 时间为本地可读字符串。 */
function formatTime(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** 会话管理页面：查看在线设备并支持强制下线。 */
export function SessionsPage() {
  const [sessions, setSessions] = useState<UserSession[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [revokingId, setRevokingId] = useState<number | null>(null)
  const [revokingOthers, setRevokingOthers] = useState(false)
  const { confirm, dialog: confirmDialog } = useConfirm()

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const refreshToken = localStorage.getItem('lifeos_refresh_token') || ''
      const data = await api.query<UserSession[]>(
        `/auth/sessions${refreshToken ? `?current_token=${encodeURIComponent(refreshToken)}` : ''}`,
      )
      setSessions(data)
    } catch {
      setSessions([])
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  /** 强制下线指定会话。 */
  const revoke = async (id: number) => {
    if (!(await confirm({
      title: '强制下线',
      description: '确定要下线该设备吗？该设备将立即被登出，无法继续访问。',
    }))) return
    setRevokingId(id)
    try {
      await api.remove('/auth/sessions', id)
      toast.success('已下线该设备')
      await load()
    } catch (e) {
      toast.error('下线失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setRevokingId(null)
    }
  }

  /** 下线除当前设备外的所有其他会话。 */
  const revokeOthers = async () => {
    if (!(await confirm({
      title: '下线其他设备',
      description: '确定要下线除当前设备外的所有其他设备吗？这些设备将立即被登出。',
    }))) return
    const refreshToken = localStorage.getItem('lifeos_refresh_token')
    if (!refreshToken) {
      toast.error('未找到当前会话信息')
      return
    }
    setRevokingOthers(true)
    try {
      await api.post('/auth/sessions/revoke-others', { refresh_token: refreshToken })
      toast.success('已下线其他设备')
      await load()
    } catch (e) {
      toast.error('操作失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setRevokingOthers(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">会话管理</h1>
        <div className="flex gap-2">
          <Button variant="outline" onClick={load} disabled={loading}>
            <RefreshCw className={loading ? 'animate-spin' : ''} /> 刷新
          </Button>
          <Button
            variant="destructive"
            onClick={revokeOthers}
            disabled={revokingOthers || sessions === null || sessions.length <= 1}
          >
            {revokingOthers ? <Loader2 className="animate-spin" /> : <LogOut />} 下线其他设备
          </Button>
        </div>
      </div>

      {loading ? (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
      ) : sessions && sessions.length > 0 ? (
        <div className="space-y-3">
          {sessions.map((s) => (
            <Card key={s.id}>
              <CardContent className="flex items-center gap-4 p-4">
                <div className="rounded-lg bg-muted p-3">
                  <Monitor className="size-6 text-muted-foreground" />
                </div>
                <div className="flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{s.device || '未知设备'}</span>
                    {s.is_current && <Badge variant="secondary">当前设备</Badge>}
                  </div>
                  <div className="text-sm text-muted-foreground">
                    IP：{s.ip_address || '-'} · 最近活跃：{formatTime(s.last_used_at)}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    登录于 {formatTime(s.created_at)} · 过期于 {formatTime(s.expires_at)}
                  </div>
                </div>
                {!s.is_current && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => revoke(s.id)}
                    disabled={revokingId === s.id}
                  >
                    {revokingId === s.id ? (
                      <Loader2 className="animate-spin" />
                    ) : (
                      <LogOut />
                    )}
                    下线
                  </Button>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">暂无活跃会话</CardContent>
        </Card>
      )}
      {confirmDialog}
    </div>
  )
}
