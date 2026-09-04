import { useEffect, useState } from 'react'
import {
  Briefcase,
  Cake,
  Loader2,
  Mail,
  MapPin,
  Pencil,
  Phone,
  Quote,
  VenusAndMars,
} from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { api } from '@/lib/api'
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

const GENDER_NAMES: Record<string, string> = {
  male: '男',
  female: '女',
  other: '其他',
}

function InfoRow({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Mail
  label: string
  value: string | null
}) {
  return (
    <div className="flex items-center gap-3">
      <Icon className="size-4 shrink-0 text-muted-foreground" />
      <span className="w-16 shrink-0 text-sm text-muted-foreground">{label}</span>
      <span className="min-w-0 truncate text-sm">{value || '—'}</span>
    </div>
  )
}

export function UserCenterPage() {
  const { refresh: refreshAuth } = useAuth()
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})

  const load = async () => {
    setLoading(true)
    try {
      setProfile(await api.query<Profile>('/user/profile'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const openEdit = () => {
    setForm({
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
    })
    setDialogOpen(true)
  }

  const submit = async () => {
    const payload: Record<string, unknown> = {
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
    }
    setSaving(true)
    try {
      await api.put('/user/profile', payload)
      setDialogOpen(false)
      await load()
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

  const avatarChar = (profile?.nickname?.trim() || '用').charAt(0)

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">用户中心</h1>
          <p className="text-sm text-muted-foreground">查看与编辑个人基本资料。</p>
        </div>
        <Button onClick={openEdit} disabled={!profile}>
          <Pencil /> 编辑资料
        </Button>
      </section>

      {loading ? (
        <div className="flex justify-center py-16 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
        </div>
      ) : profile ? (
        <>
          <Card>
            <CardContent className="flex flex-col items-center gap-4 py-8 sm:flex-row sm:items-start sm:gap-6">
              {profile.avatar ? (
                <img
                  src={profile.avatar}
                  alt="头像"
                  className="size-24 rounded-full object-cover ring-2 ring-border"
                />
              ) : (
                <div className="flex size-24 shrink-0 items-center justify-center rounded-full bg-primary/10 text-4xl font-semibold text-primary ring-2 ring-border">
                  {avatarChar}
                </div>
              )}
              <div className="flex min-w-0 flex-col items-center gap-1 text-center sm:items-start sm:text-left">
                <h2 className="flex items-center gap-2 text-xl font-semibold">
                  {profile.nickname || '未命名用户'}
                  {profile.gender && (
                    <Badge variant="secondary">{GENDER_NAMES[profile.gender] ?? profile.gender}</Badge>
                  )}
                </h2>
                {profile.signature && (
                  <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
                    <Quote className="size-3.5" />
                    {profile.signature}
                  </p>
                )}
                {profile.bio && (
                  <p className="mt-1 max-w-md text-sm leading-relaxed text-muted-foreground">
                    {profile.bio}
                  </p>
                )}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">基本资料</CardTitle>
              <CardDescription>联系方式与工作生活信息</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-x-8 gap-y-4 sm:grid-cols-2">
              <InfoRow icon={Mail} label="邮箱" value={profile.email} />
              <InfoRow icon={Phone} label="手机号" value={profile.phone} />
              <InfoRow icon={MapPin} label="地区" value={profile.location} />
              <InfoRow icon={Briefcase} label="职业" value={profile.job_title} />
              <InfoRow icon={Cake} label="生日" value={profile.birthday} />
              <InfoRow icon={VenusAndMars} label="性别" value={profile.gender ? (GENDER_NAMES[profile.gender] ?? profile.gender) : null} />
            </CardContent>
          </Card>
        </>
      ) : null}

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>编辑个人资料</DialogTitle>
            <DialogDescription>填写你的基本资料信息。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="col-span-2 space-y-2">
              <Label htmlFor="nickname">
                昵称<span className="text-destructive"> *</span>
              </Label>
              <Input
                id="nickname"
                value={form.nickname ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, nickname: e.target.value }))}
                placeholder="你的昵称"
              />
            </div>
            <div className="col-span-2 space-y-2">
              <Label htmlFor="avatar">头像地址</Label>
              <Input
                id="avatar"
                value={form.avatar ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, avatar: e.target.value }))}
                placeholder="https://example.com/avatar.png"
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
              <Input
                id="birthday"
                type="date"
                value={form.birthday ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, birthday: e.target.value }))}
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
                placeholder="职业/职位"
              />
            </div>
            <div className="col-span-2 space-y-2">
              <Label htmlFor="signature">个性签名</Label>
              <Input
                id="signature"
                value={form.signature ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, signature: e.target.value }))}
                placeholder="一句个性签名"
              />
            </div>
            <div className="col-span-2 space-y-2">
              <Label htmlFor="bio">个人简介</Label>
              <Textarea
                id="bio"
                value={form.bio ?? ''}
                onChange={(e) => setForm((f) => ({ ...f, bio: e.target.value }))}
                placeholder="介绍一下自己"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={submit} disabled={saving || !form.nickname?.trim()}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
