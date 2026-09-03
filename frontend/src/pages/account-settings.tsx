import { useEffect, useState } from 'react'
import { KeyRound, Loader2, Save, UserRound } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { api } from '@/lib/api'

type Settings = {
  account: string
  has_password: boolean
  created_at: string
}

type Message = { type: 'success' | 'error'; text: string } | null

function formatDate(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(
    d.getHours(),
  )}:${pad(d.getMinutes())}`
}

export function AccountSettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [currentPwd, setCurrentPwd] = useState('')
  const [newPwd, setNewPwd] = useState('')
  const [confirmPwd, setConfirmPwd] = useState('')
  const [savingPwd, setSavingPwd] = useState(false)
  const [message, setMessage] = useState<Message>(null)

  const load = async () => {
    try {
      const data = await api.query<Settings>('/user/settings')
      setSettings(data)
    } catch {
      setMessage({ type: 'error', text: '加载账号设置失败' })
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const savePassword = async () => {
    if (!newPwd) {
      setMessage({ type: 'error', text: '请输入新密码' })
      return
    }
    if (newPwd.length < 6) {
      setMessage({ type: 'error', text: '新密码长度不能少于 6 位' })
      return
    }
    if (newPwd !== confirmPwd) {
      setMessage({ type: 'error', text: '两次输入的密码不一致' })
      return
    }
    setSavingPwd(true)
    setMessage(null)
    try {
      await api.put('/user/settings', {
        current_password: currentPwd || null,
        new_password: newPwd,
      })
      setMessage({ type: 'success', text: '密码已更新' })
      setCurrentPwd('')
      setNewPwd('')
      setConfirmPwd('')
      await load()
    } catch (err) {
      setMessage({ type: 'error', text: err instanceof Error ? err.message : '保存失败' })
    } finally {
      setSavingPwd(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">账号设置</h1>
        <p className="text-sm text-muted-foreground">管理登录账号与密码。</p>
      </section>

      {message && (
        <p
          className={`rounded-md border px-3 py-2 text-sm ${
            message.type === 'success'
              ? 'border-green-200 bg-green-50 text-green-700'
              : 'border-red-200 bg-red-50 text-red-700'
          }`}
        >
          {message.text}
        </p>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm font-medium">
            <UserRound className="size-4 text-muted-foreground" />
            账号信息
          </CardTitle>
          <CardDescription>账号（不可改）</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <div className="min-w-52 flex-1 space-y-2">
              <Label htmlFor="account">账号</Label>
              <Input
                id="account"
                value={settings?.account ?? ''}
                readOnly
                disabled
                className="bg-muted text-muted-foreground"
                placeholder="登录账号不可修改"
              />
              <p className="text-xs text-muted-foreground">登录账号，注册后不可更改；昵称请在个人资料修改</p>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-sm text-muted-foreground">
            <span>注册时间：{settings ? formatDate(settings.created_at) : '—'}</span>
            <span className="flex items-center gap-1.5">
              密码状态：
              {settings?.has_password ? (
                <Badge className="bg-green-100 text-green-700">已设置</Badge>
              ) : (
                <Badge variant="outline">未设置</Badge>
              )}
            </span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm font-medium">
            <KeyRound className="size-4 text-muted-foreground" />
            修改密码
          </CardTitle>
          <CardDescription>
            {settings?.has_password
              ? '修改密码需验证当前密码'
              : '尚未设置密码，可直接设置新密码'}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-2">
            <Label htmlFor="current_pwd">
              当前密码{settings?.has_password ? <span className="text-destructive"> *</span> : null}
            </Label>
            <Input
              id="current_pwd"
              type="password"
              value={currentPwd}
              onChange={(e) => setCurrentPwd(e.target.value)}
              placeholder={settings?.has_password ? '请输入当前密码' : '未设置可留空'}
              autoComplete="current-password"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="new_pwd">
              新密码<span className="text-destructive"> *</span>
            </Label>
            <Input
              id="new_pwd"
              type="password"
              value={newPwd}
              onChange={(e) => setNewPwd(e.target.value)}
              placeholder="至少 6 位"
              autoComplete="new-password"
            />
          </div>
          <div className="flex items-end gap-3">
            <div className="min-w-0 flex-1 space-y-2">
              <Label htmlFor="confirm_pwd">
                确认新密码<span className="text-destructive"> *</span>
              </Label>
              <Input
                id="confirm_pwd"
                type="password"
                value={confirmPwd}
                onChange={(e) => setConfirmPwd(e.target.value)}
                placeholder="再次输入新密码"
                autoComplete="new-password"
              />
            </div>
            <Button onClick={savePassword} disabled={savingPwd}>
              {savingPwd ? <Loader2 className="animate-spin" /> : <Save />}
              保存
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
