import { useCallback, useEffect, useState } from 'react'
import { Loader2, Pencil, Plus, Send, Trash2 } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'

type Channel = {
  id: number
  channel_type: string
  channel_type_label: string
  name: string
  enabled: boolean
  recipients?: string | null
  note?: string | null
  config: Record<string, unknown>
}

type ChannelField = {
  key: string
  label: string
  type: 'text' | 'number' | 'password' | 'textarea' | 'boolean' | 'select'
  secret?: boolean
  options?: string[]
}

const CHANNEL_TYPES = ['email', 'dingtalk', 'feishu', 'workwechat', 'tgbot', 'webhook']

const FIELD_DEFS: Record<string, ChannelField[]> = {
  email: [
    { key: 'smtp_host', label: 'SMTP 服务器', type: 'text' },
    { key: 'smtp_port', label: 'SMTP 端口', type: 'number' },
    { key: 'smtp_user', label: '账号', type: 'text' },
    { key: 'smtp_pass', label: '密码', type: 'password', secret: true },
    { key: 'use_ssl', label: '使用 SSL', type: 'boolean' },
    { key: 'from_name', label: '发件人名称', type: 'text' },
    { key: 'from_addr', label: '发件地址', type: 'text' },
  ],
  dingtalk: [{ key: 'webhook_url', label: 'Webhook URL', type: 'text' }],
  feishu: [{ key: 'webhook_url', label: 'Webhook URL', type: 'text' }],
  workwechat: [{ key: 'webhook_url', label: 'Webhook URL', type: 'text' }],
  tgbot: [
    { key: 'bot_token', label: 'Bot Token', type: 'password', secret: true },
    { key: 'chat_id', label: 'Chat ID', type: 'text' },
  ],
  webhook: [
    { key: 'url', label: 'URL', type: 'text' },
    { key: 'headers', label: 'Headers（JSON）', type: 'textarea' },
    { key: 'method', label: 'Method', type: 'select', options: ['POST', 'PUT'] },
  ],
}

const TYPE_LABEL: Record<string, string> = {
  email: '邮件',
  dingtalk: '钉钉',
  feishu: '飞书',
  workwechat: '企业微信',
  tgbot: 'Telegram Bot',
  webhook: 'Webhook',
}

export function ChannelsPanel() {
  const [channels, setChannels] = useState<Channel[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<Channel | null>(null)
  const [saving, setSaving] = useState(false)
  const [newType, setNewType] = useState('email')
  const [form, setForm] = useState<{ name: string; recipients: string; config: Record<string, string> }>({
    name: '',
    recipients: '',
    config: {},
  })
  const [testingId, setTestingId] = useState<number | null>(null)
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除该通知渠道吗？删除后相关提醒将不再通过该渠道下发。',
  })

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const rows = await api.query<Channel[]>('/notifications/channels')
      setChannels(rows)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const openCreate = (type: string) => {
    setEditing(null)
    setNewType(type)
    setForm({ name: '', recipients: '', config: {} })
    setOpen(true)
  }

  const openEdit = (ch: Channel) => {
    setEditing(ch)
    setNewType(ch.channel_type)
    const cfg = Object.fromEntries(
      Object.entries(ch.config).map(([k, v]) => [k, String(v ?? '')]),
    )
    setForm({ name: ch.name, recipients: ch.recipients ?? '', config: cfg })
    setOpen(true)
  }

  const setCfg = (key: string, value: string) =>
    setForm((f) => ({ ...f, config: { ...f.config, [key]: value } }))

  const save = async () => {
    setSaving(true)
    try {
      const payload = {
        channel_type: newType,
        name: form.name,
        recipients: form.recipients || null,
        enabled: editing?.enabled ?? true,
        note: null,
        config: form.config,
      }
      if (editing) await api.put(`/notifications/channels/${editing.id}`, payload)
      else await api.create('/notifications/channels', payload)
      toast.success(editing ? '渠道已更新' : '渠道已创建')
      setOpen(false)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const toggleEnable = async (ch: Channel, enabled: boolean) => {
    setChannels((cs) => cs.map((c) => (c.id === ch.id ? { ...c, enabled } : c)))
    try {
      await api.put(`/notifications/channels/${ch.id}`, {
        channel_type: ch.channel_type,
        name: ch.name,
        enabled,
        recipients: ch.recipients ?? null,
        note: ch.note ?? null,
        config: ch.config,
      })
      toast.success(enabled ? '渠道已启用' : '渠道已停用')
    } catch {
      setChannels((cs) => cs.map((c) => (c.id === ch.id ? { ...c, enabled: !enabled } : c)))
    }
  }

  const testSend = async (ch: Channel) => {
    setTestingId(ch.id)
    try {
      const res = await api.post<{ ok: boolean; message: string }>('/notifications/test-send', {
        channel_id: ch.id,
      })
      if (res.ok) toast.success(`测试发送成功：${res.message}`)
      else toast.error(`发送失败：${res.message}`)
    } catch (err) {
      toast.error(err instanceof Error ? err.message : '发送失败')
    } finally {
      setTestingId(null)
    }
  }

  const remove = async (ch: Channel) => {
    if (!(await confirm())) return
    await api.remove('/notifications/channels', ch.id)
    toast.success('渠道已删除')
    await load()
  }

  const byType = CHANNEL_TYPES.map((t) => ({
    type: t,
    label: TYPE_LABEL[t] ?? t,
    items: channels.filter((c) => c.channel_type === t),
  }))

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          配置各外发渠道。启用后，提醒开关指定的场景将按此处渠道下发通知。
        </p>
      </div>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {byType.map((group) => (
            <Card key={group.type}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
                <div>
                  <CardTitle className="text-sm font-medium">{group.label}</CardTitle>
                  <CardDescription>{group.type}</CardDescription>
                </div>
                <Button size="sm" variant="outline" onClick={() => openCreate(group.type)}>
                  <Plus /> 新建
                </Button>
              </CardHeader>
              <CardContent className="space-y-2">
                {group.items.length === 0 ? (
                  <p className="py-3 text-center text-sm text-muted-foreground">
                    尚未配置 {group.label} 渠道
                  </p>
                ) : (
                  group.items.map((ch) => (
                    <div
                      key={ch.id}
                      className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2"
                    >
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="truncate text-sm font-medium">{ch.name}</span>
                          {ch.enabled ? (
                            <Badge className="bg-green-100 text-green-700">启用</Badge>
                          ) : (
                            <Badge className="bg-gray-100 text-gray-500">停用</Badge>
                          )}
                        </div>
                        <p className="truncate text-xs text-muted-foreground">
                          {ch.recipients || TYPE_LABEL[ch.channel_type]}
                        </p>
                      </div>
                      <div className="flex shrink-0 items-center gap-1">
                        <Switch
                          checked={ch.enabled}
                          onCheckedChange={(v) => toggleEnable(ch, v)}
                          aria-label="启用/停用"
                        />
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => testSend(ch)}
                          disabled={testingId === ch.id}
                          title="发送测试通知"
                        >
                          {testingId === ch.id ? (
                            <Loader2 className="size-4 animate-spin" />
                          ) : (
                            <Send className="size-4" />
                          )}
                        </Button>
                        <Button variant="ghost" size="icon" onClick={() => openEdit(ch)}>
                          <Pencil />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="text-destructive"
                          onClick={() => remove(ch)}
                        >
                          <Trash2 />
                        </Button>
                      </div>
                    </div>
                  ))
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑渠道' : `新建 ${TYPE_LABEL[newType]} 渠道`}</DialogTitle>
            <DialogDescription>
              填写该渠道的连接配置，敏感字段仅本地加密存储。
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label htmlFor="ch-name">
                渠道名称<span className="text-destructive"> *</span>
              </Label>
              <Input
                id="ch-name"
                value={form.name}
                onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                placeholder="如 主邮箱 / 运维钉钉群"
              />
            </div>
            {newType === 'email' && (
              <div className="col-span-2 space-y-2">
                <Label htmlFor="ch-recipients">收件人（逗号分隔）</Label>
                <Input
                  id="ch-recipients"
                  value={form.recipients}
                  onChange={(e) => setForm((f) => ({ ...f, recipients: e.target.value }))}
                  placeholder="you@example.com, other@example.com"
                />
              </div>
            )}
            {(FIELD_DEFS[newType] ?? []).map((field) =>
              field.type === 'boolean' ? (
                <div key={field.key} className="col-span-2 flex items-center justify-between rounded-lg border px-3 py-2">
                  <Label htmlFor={field.key}>{field.label}</Label>
                  <Switch
                    id={field.key}
                    checked={form.config[field.key] === 'true'}
                    onCheckedChange={(v) => setCfg(field.key, String(v))}
                  />
                </div>
              ) : field.type === 'select' ? (
                <div key={field.key} className="col-span-2 space-y-2">
                  <Label htmlFor={field.key}>{field.label}</Label>
                  <Select value={form.config[field.key] ?? ''} onValueChange={(v) => setCfg(field.key, v)}>
                    <SelectTrigger id={field.key}>
                      <SelectValue placeholder="请选择" />
                    </SelectTrigger>
                    <SelectContent>
                      {(field.options ?? []).map((o) => (
                        <SelectItem key={o} value={o}>
                          {o}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              ) : field.type === 'textarea' ? (
                <div key={field.key} className="col-span-2 space-y-2">
                  <Label htmlFor={field.key}>{field.label}</Label>
                  <Textarea
                    id={field.key}
                    value={form.config[field.key] ?? ''}
                    onChange={(e) => setCfg(field.key, e.target.value)}
                    placeholder='{"Authorization":"Bearer xxx"}'
                  />
                </div>
              ) : (
                <div key={field.key} className="col-span-2 space-y-2">
                  <Label htmlFor={field.key}>{field.label}</Label>
                  <Input
                    id={field.key}
                    type={field.type}
                    value={form.config[field.key] ?? ''}
                    onChange={(e) => setCfg(field.key, e.target.value)}
                    placeholder=""
                  />
                </div>
              ),
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              取消
            </Button>
            <Button
              onClick={save}
              disabled={saving || !form.name}
            >
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}