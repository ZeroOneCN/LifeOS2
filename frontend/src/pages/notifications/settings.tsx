import { useCallback, useEffect, useState } from 'react'
import { Loader2, Play, Save } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'

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
  }, [load])

  const patch = (id: number, key: keyof Setting, value: Setting[keyof Setting]) =>
    setDraft((d) => ({ ...d, [id]: { ...d[id], [key]: value } }))

  const toggleChannel = (id: number, cid: number) => {
    const cur = draft[id]?.channels ?? []
    const next = cur.includes(cid) ? cur.filter((c) => c !== cid) : [...cur, cid]
    patch(id, 'channels', next)
  }

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
        <div className="grid gap-4 lg:grid-cols-2">
          {items.map((s) => {
            const d = draft[s.id] ?? s
            return (
              <Card key={s.id}>
                <CardContent className="space-y-3 py-4">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium">{d.name}</span>
                      <Badge className="bg-purple-100 text-purple-700">{d.category}</Badge>
                    </div>
                    <Switch
                      checked={d.enabled}
                      onCheckedChange={(v) => patch(s.id, 'enabled', v)}
                      aria-label="开关"
                    />
                  </div>
                  <p className="text-xs text-muted-foreground">{d.feature_key}</p>

                  <div className="flex items-center gap-2">
                    <label className="text-sm text-muted-foreground">提前提醒（天）</label>
                    <Input
                      type="number"
                      min={0}
                      className="w-24"
                      value={d.advance_days}
                      onChange={(e) => patch(s.id, 'advance_days', Number(e.target.value) || 0)}
                    />
                  </div>

                  <div>
                    <p className="mb-1 text-sm text-muted-foreground">下发渠道（不选=全部启用渠道）</p>
                    <div className="flex flex-wrap gap-2">
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
                              className={`rounded-full border px-3 py-1 text-xs transition-colors ${
                                active
                                  ? 'border-primary bg-primary text-primary-foreground'
                                  : 'border-input text-muted-foreground hover:bg-muted'
                              }`}
                            >
                              {ch.name}
                            </button>
                          )
                        })
                      )}
                    </div>
                  </div>

                  <div className="flex justify-end">
                    <Button size="sm" onClick={() => save(s.id)} disabled={savingId === s.id}>
                      {savingId === s.id ? <Loader2 className="animate-spin" /> : <Save />}
                      保存
                    </Button>
                  </div>
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}