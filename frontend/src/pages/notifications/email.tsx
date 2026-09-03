import { useCallback, useEffect, useState } from 'react'
import { Loader2, MailCheck, Pencil, Plus, Send } from 'lucide-react'
import { toast } from 'sonner'

import { api } from '@/lib/api'
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
import { Switch } from '@/components/ui/switch'
import type { Channel } from './types'

type EmailForm = {
  name: string
  recipients: string
  smtp_host: string
  smtp_port: string
  smtp_user: string
  smtp_pass: string
  use_ssl: string
  from_name: string
  from_addr: string
}

const emptyForm: EmailForm = {
  name: '',
  recipients: '',
  smtp_host: '',
  smtp_port: '465',
  smtp_user: '',
  smtp_pass: '',
  use_ssl: 'true',
  from_name: '',
  from_addr: '',
}

export function EmailConfigPanel() {
  const [channels, setChannels] = useState<Channel[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [form, setForm] = useState<EmailForm>(emptyForm)
  const [saving, setSaving] = useState(false)
  const [testingId, setTestingId] = useState<number | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const rows = await api.query<Channel[]>('/notifications/channels')
      setChannels(rows.filter((c) => c.channel_type === 'email'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const openCreate = () => {
    setEditingId(null)
    setForm(emptyForm)
    setOpen(true)
  }

  const openEdit = (ch: Channel) => {
    setEditingId(ch.id)
    setForm({
      name: ch.name,
      recipients: ch.recipients ?? '',
      smtp_host: String(ch.config.smtp_host ?? ''),
      smtp_port: String(ch.config.smtp_port ?? '465'),
      smtp_user: String(ch.config.smtp_user ?? ''),
      smtp_pass: ch.config.smtp_pass === '******' ? '' : String(ch.config.smtp_pass ?? ''),
      use_ssl: String(ch.config.use_ssl ?? 'true'),
      from_name: String(ch.config.from_name ?? ''),
      from_addr: String(ch.config.from_addr ?? ''),
    })
    setOpen(true)
  }

  const set = <K extends keyof EmailForm>(key: K, value: EmailForm[K]) =>
    setForm((f) => ({ ...f, [key]: value }))

  const save = async () => {
    setSaving(true)
    try {
      const config = {
        smtp_host: form.smtp_host,
        smtp_port: form.smtp_port,
        smtp_user: form.smtp_user,
        smtp_pass: form.smtp_pass,
        use_ssl: form.use_ssl,
        from_name: form.from_name,
        from_addr: form.from_addr,
      }
      const payload = {
        channel_type: 'email',
        name: form.name,
        enabled: true,
        recipients: form.recipients || null,
        note: null,
        config,
      }
      if (editingId) await api.put(`/notifications/channels/${editingId}`, payload)
      else await api.create('/notifications/channels', payload)
      toast.success('邮件配置已保存')
      setOpen(false)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const testSend = async (ch: Channel) => {
    setTestingId(ch.id)
    try {
      const res = await api.post<{ ok: boolean; message: string }>('/notifications/test-send', {
        channel_id: ch.id,
      })
      if (res.ok) toast.success(`测试邮件已发送：${res.message}`)
      else toast.error(`发送失败：${res.message}`)
    } catch (err) {
      toast.error(err instanceof Error ? err.message : '发送失败')
    } finally {
      setTestingId(null)
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          配置 SMTP 邮件通知。保存后可用测试按钮向收件人发送一封测试邮件。
        </p>
        <Button onClick={openCreate}>
          <Plus /> 配置邮件
        </Button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : channels.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
            <MailCheck className="size-8 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">尚未配置邮件渠道，点击"配置邮件"开始。</p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {channels.map((ch) => (
            <Card key={ch.id}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
                <div>
                  <CardTitle className="text-sm font-medium">{ch.name}</CardTitle>
                  <CardDescription>
                    {String(ch.config.smtp_host ?? '')}:{String(ch.config.smtp_port ?? '')}　
                    {ch.recipients || '未配置收件人'}
                  </CardDescription>
                </div>
                <Badge className={ch.enabled ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}>
                  {ch.enabled ? '启用' : '停用'}
                </Badge>
              </CardHeader>
              <CardContent className="flex items-center gap-2">
                <Button variant="outline" size="sm" onClick={() => openEdit(ch)}>
                  <Pencil /> 编辑
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => testSend(ch)}
                  disabled={testingId === ch.id}
                >
                  {testingId === ch.id ? (
                    <Loader2 className="size-4 animate-spin" />
                  ) : (
                    <Send className="size-4" />
                  )}
                  发送测试邮件
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editingId ? '编辑邮件配置' : '配置邮件通知'}</DialogTitle>
            <DialogDescription>配置 SMTP 服务，用于发送邮件提醒。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label htmlFor="em-name">
                渠道名称<span className="text-destructive"> *</span>
              </Label>
              <Input
                id="em-name"
                value={form.name}
                onChange={(e) => set('name', e.target.value)}
                placeholder="如 主邮箱"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-host">
                SMTP 服务器<span className="text-destructive"> *</span>
              </Label>
              <Input id="em-host" value={form.smtp_host} onChange={(e) => set('smtp_host', e.target.value)} placeholder="smtp.example.com" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-port">
                SMTP 端口<span className="text-destructive"> *</span>
              </Label>
              <Input id="em-port" value={form.smtp_port} onChange={(e) => set('smtp_port', e.target.value)} placeholder="465" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-user">
                账号<span className="text-destructive"> *</span>
              </Label>
              <Input id="em-user" value={form.smtp_user} onChange={(e) => set('smtp_user', e.target.value)} placeholder="you@example.com" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-pass">密码（授权码）</Label>
              <Input
                id="em-pass"
                type="password"
                value={form.smtp_pass}
                onChange={(e) => set('smtp_pass', e.target.value)}
                placeholder={editingId ? '留空则保持不变' : ''}
              />
            </div>
            <div className="col-span-2 flex items-center justify-between rounded-lg border px-3 py-2">
              <Label htmlFor="em-ssl">使用 SSL</Label>
              <Switch id="em-ssl" checked={form.use_ssl === 'true'} onCheckedChange={(v) => set('use_ssl', String(v))} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-from-name">发件人名称</Label>
              <Input id="em-from-name" value={form.from_name} onChange={(e) => set('from_name', e.target.value)} placeholder="LifeOS" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="em-from-addr">发件地址</Label>
              <Input id="em-from-addr" value={form.from_addr} onChange={(e) => set('from_addr', e.target.value)} placeholder="you@example.com" />
            </div>
            <div className="col-span-2 space-y-2">
              <Label htmlFor="em-recipients">收件人（逗号分隔）</Label>
              <Input id="em-recipients" value={form.recipients} onChange={(e) => set('recipients', e.target.value)} placeholder="you@example.com" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              取消
            </Button>
            <Button onClick={save} disabled={saving || !form.name}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}