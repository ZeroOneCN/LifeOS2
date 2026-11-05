import { useCallback, useEffect, useMemo, useState } from 'react'
import { KeyRound, Loader2, Quote, RotateCcw, Save, ShieldCheck, UserRound } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { DatePicker } from '@/components/ui/date-picker'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { Hint } from '@/components/ui/tip'
import { api } from '@/lib/api'
import { DASH, formatDateTime } from '@/lib/format'
import { useAuth } from '@/lib/auth'

type Profile = {
  id: number
  nickname: string
  avatar: string | null
  gender: string | null
  birthday: string | null
  phone: string | null
  email: string | null
  location: string | null
  job_title: string | null
  bio: string | null
  signature: string | null
}

type Settings = {
  account: string
  has_password: boolean
  created_at: string
}

const GENDER_NAMES: Record<string, string> = {
  male: '男',
  female: '女',
  other: '其他',
}

/**
 * 将接口返回的个人资料转换为表单字段。
 * 键顺序固定，便于用 JSON 序列化做脏检查。
 * @param profile 个人资料，未加载时为 null
 * @returns 表单字段（空值统一转为空字符串）
 */
function toForm(profile: Profile | null): Record<string, string> {
  return {
    nickname: profile?.nickname ?? '',
    avatar: profile?.avatar ?? '',
    gender: profile?.gender ?? '',
    birthday: profile?.birthday ?? '',
    phone: profile?.phone ?? '',
    email: profile?.email ?? '',
    location: profile?.location ?? '',
    job_title: profile?.job_title ?? '',
    bio: profile?.bio ?? '',
    signature: profile?.signature ?? '',
  }
}

/** 注册时间：统一走公共 formatDateTime（YYYY-MM-DD HH:mm）。 */

export function UserCenterPage() {
  const { refresh: refreshAuth } = useAuth()
  const [profile, setProfile] = useState<Profile | null>(null)
  const [settings, setSettings] = useState<Settings | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>(() => toForm(null))

  const [currentPwd, setCurrentPwd] = useState('')
  const [newPwd, setNewPwd] = useState('')
  const [confirmPwd, setConfirmPwd] = useState('')
  const [savingPwd, setSavingPwd] = useState(false)

  /** 拉取个人资料并同步表单（保存成功后也复用此逻辑）。 */
  const loadProfile = useCallback(async () => {
    try {
      const data = await api.query<Profile>('/user/profile')
      setProfile(data)
      setForm(toForm(data))
    } catch (e) {
      toast.error('加载个人资料失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }, [])

  /** 拉取登录账号与密码状态。 */
  const loadSettings = useCallback(async () => {
    try {
      setSettings(await api.query<Settings>('/user/settings'))
    } catch {
      toast.error('加载账户信息失败')
    }
  }, [])

  useEffect(() => {
    let active = true
    ;(async () => {
      setLoading(true)
      try {
        await Promise.all([loadProfile(), loadSettings()])
      } finally {
        if (active) setLoading(false)
      }
    })()
    return () => {
      active = false
    }
  }, [loadProfile, loadSettings])

  const dirty = useMemo(
    () => profile !== null && JSON.stringify(toForm(profile)) !== JSON.stringify(form),
    [profile, form],
  )
  const pwdDirty = Boolean(currentPwd || newPwd || confirmPwd)

  /** 保存个人资料：成功后刷新页面数据与全局登录用户信息。 */
  const saveProfile = async () => {
    setSaving(true)
    try {
      await api.put('/user/profile', {
        nickname: form.nickname || null,
        avatar: form.avatar || null,
        gender: form.gender || null,
        birthday: form.birthday || null,
        phone: form.phone || null,
        email: form.email || null,
        location: form.location || null,
        job_title: form.job_title || null,
        bio: form.bio || null,
        signature: form.signature || null,
      })
      await loadProfile()
      await refreshAuth()
      toast.success('个人资料已更新')
    } catch (e) {
      toast.error('保存失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  /** 保存登录密码：校验必填、长度与两次输入一致性。 */
  const savePassword = async () => {
    if (!newPwd) {
      toast.error('请输入新密码')
      return
    }
    if (newPwd.length < 6) {
      toast.error('新密码长度不能少于 6 位')
      return
    }
    if (newPwd !== confirmPwd) {
      toast.error('两次输入的密码不一致')
      return
    }
    setSavingPwd(true)
    try {
      await api.put('/user/settings', {
        current_password: currentPwd || null,
        new_password: newPwd,
      })
      toast.success('密码已更新')
      setCurrentPwd('')
      setNewPwd('')
      setConfirmPwd('')
      await loadSettings()
    } catch (err) {
      toast.error('保存失败', {
        description: err instanceof Error ? err.message : '请稍后重试',
      })
    } finally {
      setSavingPwd(false)
    }
  }

  const nickname = form.nickname?.trim() || '未命名用户'
  const avatarSrc = form.avatar?.trim()
  const avatarChar = nickname.charAt(0)
  const hasPassword = Boolean(settings?.has_password)

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">账户设置</h1>
        <p className="text-sm text-muted-foreground">
          管理个人资料、登录账号与密码，修改后点击对应卡片的保存按钮生效。
        </p>
      </section>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : profile ? (
        <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_340px]">
          <div className="flex flex-col gap-4">
            <Card>
              <CardContent className="flex items-center gap-4 py-4">
                {avatarSrc ? (
                  <img
                    src={avatarSrc}
                    alt="头像"
                    className="size-16 shrink-0 rounded-full object-cover ring-2 ring-border"
                  />
                ) : (
                  <div className="flex size-16 shrink-0 items-center justify-center rounded-full bg-primary/10 text-2xl font-semibold text-primary ring-2 ring-border">
                    {avatarChar}
                  </div>
                )}
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="truncate text-lg font-semibold" title={nickname}>
                      {nickname}
                    </h2>
                    {form.gender ? (
                      <Badge variant="secondary">
                        {GENDER_NAMES[form.gender] ?? form.gender}
                      </Badge>
                    ) : null}
                  </div>
                  <p className="flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground">
                    <Quote className="size-3.5 shrink-0" />
                    <span className="truncate" title={form.signature || '尚未填写个性签名'}>
                      {form.signature || '尚未填写个性签名'}
                    </span>
                  </p>
                  <p
                    className="truncate text-sm text-muted-foreground"
                    title={form.bio || '尚未填写个人简介'}
                  >
                    {form.bio || '尚未填写个人简介'}
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium">
                  <UserRound className="size-4 text-muted-foreground" />
                  个人资料
                </CardTitle>
                <CardDescription>用于侧边栏账号菜单与资料卡展示，除昵称外均可留空</CardDescription>
              </CardHeader>
              <CardContent className="grid gap-x-4 gap-y-3 sm:grid-cols-2 xl:grid-cols-3">
                <div className="space-y-2">
                  <Label htmlFor="nickname">
                    昵称<span className="text-destructive">*</span>
                    <Hint text="展示在侧边栏账号菜单与资料卡中，不能为空" />
                  </Label>
                  <Input
                    id="nickname"
                    value={form.nickname ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, nickname: e.target.value }))}
                    placeholder="你的昵称"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="gender">性别</Label>
                  <Select
                    value={form.gender ?? ''}
                    onValueChange={(v) => setForm((f) => ({ ...f, gender: v }))}
                  >
                    <SelectTrigger id="gender">
                      <SelectValue placeholder="未设置" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="male">男</SelectItem>
                      <SelectItem value="female">女</SelectItem>
                      <SelectItem value="other">其他</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="birthday">生日</Label>
                  <DatePicker
                    id="birthday"
                    value={form.birthday ?? ''}
                    onChange={(v) => setForm((f) => ({ ...f, birthday: v }))}
                    placeholder="选择生日"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phone">手机号</Label>
                  <Input
                    id="phone"
                    value={form.phone ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
                    placeholder="手机号"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">邮箱</Label>
                  <Input
                    id="email"
                    value={form.email ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
                    placeholder="邮箱地址"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="location">所在地区</Label>
                  <Input
                    id="location"
                    value={form.location ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, location: e.target.value }))}
                    placeholder="如 上海"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="job_title">职业</Label>
                  <Input
                    id="job_title"
                    value={form.job_title ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, job_title: e.target.value }))}
                    placeholder="职业 / 职位"
                  />
                </div>
                <div className="space-y-2 sm:col-span-2 xl:col-span-2">
                  <Label htmlFor="avatar">
                    头像地址
                    <Hint text="头像图片直链，留空时显示昵称首字" />
                  </Label>
                  <Input
                    id="avatar"
                    value={form.avatar ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, avatar: e.target.value }))}
                    placeholder="https://example.com/avatar.png"
                  />
                </div>
                <div className="space-y-2 sm:col-span-2 xl:col-span-3">
                  <Label htmlFor="signature">
                    个性签名
                    <Hint text="展示在资料卡昵称下方，过长时截断显示" />
                  </Label>
                  <Input
                    id="signature"
                    value={form.signature ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, signature: e.target.value }))}
                    placeholder="一句个性签名"
                  />
                </div>
                <div className="space-y-2 sm:col-span-2 xl:col-span-3">
                  <Label htmlFor="bio">
                    个人简介
                    <Hint text="展示在资料卡中，过长时截断显示" />
                  </Label>
                  <Textarea
                    id="bio"
                    value={form.bio ?? ''}
                    onChange={(e) => setForm((f) => ({ ...f, bio: e.target.value }))}
                    placeholder="介绍一下自己"
                    className="min-h-16"
                  />
                </div>
              </CardContent>
              <CardFooter className="justify-end gap-2">
                <Button
                  variant="outline"
                  onClick={() => setForm(toForm(profile))}
                  disabled={!dirty || saving}
                >
                  <RotateCcw />
                  重置
                </Button>
                <Button
                  onClick={saveProfile}
                  disabled={saving || !dirty || !form.nickname?.trim()}
                >
                  {saving ? <Loader2 className="animate-spin" /> : <Save />}
                  保存资料
                </Button>
              </CardFooter>
            </Card>
          </div>

          <div className="flex flex-col gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium">
                  <ShieldCheck className="size-4 text-muted-foreground" />
                  账号信息
                </CardTitle>
                <CardDescription>登录账号由注册时确定，昵称请在个人资料中调整</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="space-y-2">
                  <Label htmlFor="account">
                    登录账号
                    <Hint text="注册后不可修改；如需更换昵称请修改个人资料" />
                  </Label>
                  <Input
                    id="account"
                    value={settings?.account ?? ''}
                    readOnly
                    disabled
                    className="bg-muted text-muted-foreground"
                    placeholder="加载中"
                  />
                </div>
                <div className="flex items-center justify-between gap-2 text-sm">
                  <span className="text-muted-foreground">注册时间</span>
                  <span className="tabular-nums">
                    {settings ? formatDateTime(settings.created_at) : DASH}
                  </span>
                </div>
                <div className="flex items-center justify-between gap-2 text-sm">
                  <span className="text-muted-foreground">密码状态</span>
                  {settings ? (
                    settings.has_password ? (
                      <Badge className="bg-success-muted text-success-muted-foreground">
                        已设置
                      </Badge>
                    ) : (
                      <Badge variant="outline">未设置</Badge>
                    )
                  ) : (
                    <Badge variant="outline">—</Badge>
                  )}
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm font-medium">
                  <KeyRound className="size-4 text-muted-foreground" />
                  登录密码
                </CardTitle>
                <CardDescription>
                  {hasPassword ? '修改密码需验证当前密码' : '尚未设置密码，可直接设置新密码'}
                </CardDescription>
              </CardHeader>
              <CardContent className="grid gap-3">
                <div className="space-y-2">
                  <Label htmlFor="current_pwd">
                    当前密码
                    {hasPassword ? <span className="text-destructive">*</span> : null}
                    <Hint
                      text={
                        hasPassword
                          ? '已设置密码，修改时需验证当前密码'
                          : '尚未设置密码，可留空直接设置新密码'
                      }
                    />
                  </Label>
                  <Input
                    id="current_pwd"
                    type="password"
                    value={currentPwd}
                    onChange={(e) => setCurrentPwd(e.target.value)}
                    placeholder={hasPassword ? '请输入当前密码' : '未设置可留空'}
                    autoComplete="current-password"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="new_pwd">
                    新密码<span className="text-destructive">*</span>
                    <Hint text="长度不少于 6 位" />
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
                <div className="space-y-2">
                  <Label htmlFor="confirm_pwd">
                    确认新密码<span className="text-destructive">*</span>
                    <Hint text="需与新密码完全一致" />
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
              </CardContent>
              <CardFooter className="justify-end">
                <Button onClick={savePassword} disabled={savingPwd || !pwdDirty}>
                  {savingPwd ? <Loader2 className="animate-spin" /> : <Save />}
                  更新密码
                </Button>
              </CardFooter>
            </Card>
          </div>
        </div>
      ) : null}
    </div>
  )
}
