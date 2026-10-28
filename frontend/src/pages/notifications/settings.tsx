import { useCallback, useEffect, useState } from 'react'
import { Loader2, Play, Save } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { useRealtime } from '@/hooks/use-realtime'
import { api } from '@/lib/api'
import { getCategoryStyle } from './types'

type Setting = {
  id: number
  feature_key: string
  name: string
  category: string
  enabled: boolean
  advance_days: number
  channels: number[]
  channel_names: string[]
}

type ChannelOption = { id: number; name: string; channel_type: string }

export function ReminderSettingsPanel() {
  const [items, setItems] = useState<Setting[]>([])
  const [channelOptions, setChannelOptions] = useState<ChannelOption[]>([])
  const [loading, setLoading] = useState(true)
  const [scanning, setScanning] = useState(false)
  const [savingId, setSavingId] = useState<number | null>(null)
  const [draft, setDraft] = useState<Record<number, Setting>>({})
  const realtimeTick = useRealtime()

  /** 拉取提醒开关列表与可用渠道，并同步编辑草稿。 */
  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [rows, chs] = await Promise.all([
        api.query<Setting[]>('/notifications/settings'),
        api.query<ChannelOption[]>('/notifications/settings/channels'),
      ])
      setItems(rows)
      setChannelOptions(chs)
      setDraft(Object.fromEntries(rows.map((r) => [r.id, r])))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load, realtimeTick])

  /** 更新某条开关的草稿字段。 */
  const patch = (id: number, key: keyof Setting, value: Setting[keyof Setting]) =>
    setDraft((d) => ({ ...d, [id]: { ...d[id], [key]: value } }))

  /** 切换某条开关的下发渠道。 */
  const toggleChannel = (id: number, cid: number) => {
    const cur = draft[id]?.channels ?? []
    const next = cur.includes(cid) ? cur.filter((c) => c !== cid) : [...cur, cid]
    patch(id, 'channels', next)
  }

  /** 保存单条提醒开关配置。 */
  const save = async (id: number) => {
    const s = draft[id]
    if (!s) return
    setSavingId(id)
    try {
      await api.put(`/notifications/settings/${id}`, {
        name: s.name,
        category: s.category,
        enabled: s.enabled,
        advance_days: Number(s.advance_days) || 0,
        channels: s.channels,
      })
      toast.success('提醒开关已保存')
    } finally {
      setSavingId(null)
    }
  }

  /** 立即执行一次提醒扫描并下发。 */
  const runScan = async () => {
    setScanning(true)
    try {
      const res = await api.post<{ scanned: number; created: number; skipped: number; sent: number; failed: number }>('/notifications/scan')
      toast.success(
        `扫描完成：新增 ${res.created} 条提醒，下发成功 ${res.sent}，失败 ${res.failed}`,
      )
    } catch (err) {
      toast.error(err instanceof Error ? err.message : '扫描失败')
    } finally {
      setScanning(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          管理各功能的提醒开关、提前天数与下发渠道。开启后按设定周期自动扫描并下发。
        </p>
        <Button onClick={runScan} disabled={scanning}>
          {scanning ? <Loader2 className="animate-spin" /> : <Play />}
          立即扫描
        </Button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-3">
          {items.map((s) => {
            const d = draft[s.id] ?? s
            return (
              <Card key={s.id} className="flex h-full flex-col">
                <CardHeader className="pb-0">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 space-y-1.5">
                      <CardTitle className="text-sm leading-snug font-medium">{d.name}</CardTitle>
                      <div className="flex flex-wrap items-center gap-1.5">
                        <Badge className={getCategoryStyle(d.category)}>{d.category}</Badge>
                        <span className="font-mono text-[11px] text-muted-foreground/70">
                          {d.feature_key}
                        </span>
                      </div>
                    </div>
                    <Switch
                      checked={d.enabled}
                      onCheckedChange={(v) => patch(s.id, 'enabled', v)}
                      aria-label="启用提醒"
                    />
                  </div>
                </CardHeader>

                <CardContent
                  className={`flex-1 space-y-4 transition-opacity ${d.enabled ? '' : 'pointer-events-none opacity-50'}`}
                >
                  <div className="flex items-center justify-between gap-3">
                    <div className="space-y-0.5">
                      <p className="text-sm">提前提醒</p>
                      <p className="text-xs text-muted-foreground">到期前多少天开始生成提醒</p>
                    </div>
                    <div className="flex shrink-0 items-center gap-1.5">
                      <Input
                        type="number"
                        min={0}
                        className="h-8 w-16 text-center"
                        value={d.advance_days}
                        onChange={(e) => patch(s.id, 'advance_days', Number(e.target.value) || 0)}
                      />
                      <span className="text-xs text-muted-foreground">天</span>
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    <p className="text-sm">下发渠道</p>
                    <p className="text-xs text-muted-foreground">不选则默认使用全部已启用渠道</p>
                    <div className="flex flex-wrap gap-1.5 pt-0.5">
                      {channelOptions.length === 0 ? (
                        <span className="text-xs text-muted-foreground">暂无已启用渠道</span>
                      ) : (
                        channelOptions.map((ch) => {
                          const active = (d.channels ?? []).includes(ch.id)
                          return (
                            <button
                              key={ch.id}
                              type="button"
                              onClick={() => toggleChannel(s.id, ch.id)}
                              className={`rounded-full border px-2.5 py-1 text-xs transition-colors select-none ${
                                active
                                  ? 'border-primary bg-primary text-primary-foreground shadow-sm'
                                  : 'border-input text-muted-foreground hover:border-primary/40 hover:bg-muted'
                              }`}
                            >
                              {ch.name}
                            </button>
                          )
                        })
                      )}
                    </div>
                  </div>
                </CardContent>

                <CardFooter className="justify-between gap-2 py-2.5">
                  <span
                    className={`inline-flex items-center gap-1.5 text-xs ${
                      d.enabled ? 'text-green-600 dark:text-green-400' : 'text-muted-foreground'
                    }`}
                  >
                    <span className="size-1.5 rounded-full bg-current" />
                    {d.enabled ? '已启用' : '已停用'}
                  </span>
                  <Button size="sm" onClick={() => save(s.id)} disabled={savingId === s.id}>
                    {savingId === s.id ? <Loader2 className="animate-spin" /> : <Save />}
                    保存
                  </Button>
                </CardFooter>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
