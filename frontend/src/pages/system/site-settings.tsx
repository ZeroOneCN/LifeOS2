import { useEffect, useMemo, useRef, useState } from 'react'
import { Eye, Image, Loader2, RotateCcw, Save, ShieldAlert, Upload } from 'lucide-react'
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
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { api } from '@/lib/api'
import { useAuth } from '@/lib/auth'
import {
  DEFAULT_LOGO,
  resolveLogo,
  useSiteConfig,
  type SiteConfig,
} from '@/lib/site-config'

/** LOGO 原图体积上限，与后端校验保持一致 */
const MAX_LOGO_SIZE = 200 * 1024
/** 允许的图片类型（与后端白名单一致） */
const ALLOWED_LOGO_TYPES = ['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']

type TextFieldProps = {
  id: string
  label: string
  value: string
  placeholder?: string
  hint?: string
  maxLength: number
  disabled?: boolean
  onChange: (value: string) => void
}

/** 品牌文案输入项：标签 + 输入框 + 可选说明文字。 */
function TextField({
  id,
  label,
  value,
  placeholder,
  hint,
  maxLength,
  disabled,
  onChange,
}: TextFieldProps) {
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        value={value}
        placeholder={placeholder}
        maxLength={maxLength}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
      />
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  )
}

export function SiteSettingsPage() {
  const { user } = useAuth()
  const { config, reload } = useSiteConfig()
  const isAdmin = Boolean(user?.isAdmin)

  const [form, setForm] = useState<SiteConfig>(config)
  const [saving, setSaving] = useState(false)
  const [resetting, setResetting] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const { confirm, dialog } = useConfirm()

  // 后台配置拉到最新值后同步表单（保存成功后表单值与配置一致，不会覆盖用户未提交的编辑）
  useEffect(() => {
    setForm(config)
  }, [config])

  const dirty = useMemo(
    () => JSON.stringify(form) !== JSON.stringify(config),
    [form, config],
  )

  const patch = (key: keyof SiteConfig) => (value: string) =>
    setForm((f) => ({ ...f, [key]: value }))

  /** 选择本地图片并转为 data URL 填入表单（保存时统一提交给后端） */
  const pickLogo = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = '' // 允许重复选择同一文件
    if (!file) return
    if (!ALLOWED_LOGO_TYPES.includes(file.type)) {
      toast.error('仅支持 PNG / JPEG / WEBP / SVG 格式的图片')
      return
    }
    if (file.size > MAX_LOGO_SIZE) {
      toast.error('图片体积过大', { description: '请压缩到 200KB 以内再上传' })
      return
    }
    const reader = new FileReader()
    reader.onload = () => setForm((f) => ({ ...f, logo: String(reader.result) }))
    reader.onerror = () => toast.error('图片读取失败，请重试')
    reader.readAsDataURL(file)
  }

  /** 保存品牌配置：成功后刷新全局配置，全站与登录/注册页即时生效 */
  const save = async () => {
    setSaving(true)
    try {
      await api.put<SiteConfig>('/site-config', form)
      await reload()
      toast.success('系统设置已保存')
    } catch (err) {
      toast.error('保存失败', {
        description: err instanceof Error ? err.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  /** 恢复全部内置默认值（含 LOGO 与所有文案） */
  const resetAll = async () => {
    const ok = await confirm({
      title: '恢复默认设置',
      description: '将清空已自定义的 LOGO 与全部标题文案，恢复为系统内置默认值。',
      confirmText: '恢复默认',
      danger: false,
    })
    if (!ok) return
    setResetting(true)
    try {
      await api.post<SiteConfig>('/site-config/reset')
      await reload()
      toast.success('已恢复默认设置')
    } catch (err) {
      toast.error('恢复失败', {
        description: err instanceof Error ? err.message : '请稍后重试',
      })
    } finally {
      setResetting(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">系统设置</h1>
          <p className="text-sm text-muted-foreground">
            自定义系统 LOGO 与标题，保存后全站侧边栏、登录页、注册页与浏览器标签同步生效。
          </p>
        </div>
        <div className="flex items-center gap-2">
          {dirty ? <Badge variant="outline">有未保存的修改</Badge> : null}
          <Button
            variant="outline"
            onClick={resetAll}
            disabled={!isAdmin || resetting || saving}
            title="恢复为系统内置默认值"
          >
            {resetting ? <Loader2 className="animate-spin" /> : <RotateCcw />}
            恢复默认
          </Button>
          <Button onClick={save} disabled={!isAdmin || saving || !dirty}>
            {saving ? <Loader2 className="animate-spin" /> : <Save />}
            保存
          </Button>
        </div>
      </section>

      {!isAdmin ? (
        <div className="flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:border-amber-500/40 dark:bg-amber-500/10 dark:text-amber-300">
          <ShieldAlert className="size-4 shrink-0" />
          系统品牌配置为全局设置，仅管理员账号可修改，当前为只读查看。
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-sm font-medium">
                <Image className="size-4 text-muted-foreground" />
                品牌标识
              </CardTitle>
              <CardDescription>系统 LOGO 与系统标题，用于侧边栏与浏览器标签图标</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex flex-wrap items-start gap-4">
                <div className="flex size-20 shrink-0 items-center justify-center rounded-lg border bg-muted/40">
                  <img
                    src={resolveLogo(form.logo)}
                    alt="LOGO 预览"
                    className="size-12 object-contain"
                  />
                </div>
                <div className="min-w-56 flex-1 space-y-2">
                  <Label>系统 LOGO</Label>
                  <div className="flex flex-wrap items-center gap-2">
                    <input
                      ref={fileRef}
                      type="file"
                      accept={ALLOWED_LOGO_TYPES.join(',')}
                      className="hidden"
                      onChange={pickLogo}
                    />
                    <Button
                      variant="outline"
                      onClick={() => fileRef.current?.click()}
                      disabled={!isAdmin}
                    >
                      <Upload />
                      选择图片
                    </Button>
                    <Button
                      variant="ghost"
                      onClick={() => setForm((f) => ({ ...f, logo: null }))}
                      disabled={!isAdmin || !form.logo}
                    >
                      <RotateCcw />
                      使用默认 LOGO
                    </Button>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    支持 PNG / JPEG / WEBP / SVG，建议使用方形图片，体积不超过 200KB；
                    未设置时使用默认图标。
                  </p>
                </div>
              </div>

              <TextField
                id="site_title"
                label="系统标题"
                value={form.site_title}
                maxLength={64}
                disabled={!isAdmin}
                placeholder="数字化生活助手"
                hint="展示在侧边栏顶部与浏览器标签标题前缀"
                onChange={patch('site_title')}
              />
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">登录页文案</CardTitle>
              <CardDescription>未登录用户访问时展示的品牌信息</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <TextField
                id="login_title"
                label="登录页标题"
                value={form.login_title}
                maxLength={64}
                disabled={!isAdmin}
                hint="留空则自动使用「登录 + 系统标题」"
                onChange={patch('login_title')}
              />
              <TextField
                id="login_subtitle"
                label="登录页副标题"
                value={form.login_subtitle}
                maxLength={128}
                disabled={!isAdmin}
                onChange={patch('login_subtitle')}
              />
            </CardContent>
          </Card>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium">注册页文案</CardTitle>
              <CardDescription>新用户注册页面展示的品牌信息</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 sm:grid-cols-2">
              <TextField
                id="register_title"
                label="注册页标题"
                value={form.register_title}
                maxLength={64}
                disabled={!isAdmin}
                hint="留空则自动使用「注册 + 系统标题」"
                onChange={patch('register_title')}
              />
              <TextField
                id="register_subtitle"
                label="注册页副标题"
                value={form.register_subtitle}
                maxLength={128}
                disabled={!isAdmin}
                onChange={patch('register_subtitle')}
              />
            </CardContent>
          </Card>
        </div>

        <Card className="h-fit lg:sticky lg:top-4">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <Eye className="size-4 text-muted-foreground" />
              实时预览
            </CardTitle>
            <CardDescription>保存前即可查看实际展示效果</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <p className="text-xs text-muted-foreground">侧边栏顶部</p>
              <div className="flex items-center gap-2.5 rounded-lg border bg-sidebar p-3">
                <img
                  src={resolveLogo(form.logo)}
                  alt={form.site_title}
                  className="size-7 shrink-0 object-contain"
                />
                <span className="font-heading text-lg font-semibold leading-tight break-all">
                  {form.site_title || '数字化生活助手'}
                </span>
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-xs text-muted-foreground">登录页</p>
              <div className="rounded-lg border bg-muted/30 p-3">
                <div className="rounded-lg border bg-background p-3 text-center">
                  <img
                    src={resolveLogo(form.logo)}
                    alt={form.site_title}
                    className="mx-auto mb-1.5 size-8 object-contain"
                  />
                  <p className="text-sm font-medium break-all">
                    {form.login_title || `登录 ${form.site_title}`}
                  </p>
                  <p className="mt-0.5 text-xs text-muted-foreground break-all">
                    {form.login_subtitle}
                  </p>
                </div>
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-xs text-muted-foreground">注册页</p>
              <div className="rounded-lg border bg-muted/30 p-3">
                <div className="rounded-lg border bg-background p-3 text-center">
                  <img
                    src={resolveLogo(form.logo)}
                    alt={form.site_title}
                    className="mx-auto mb-1.5 size-8 object-contain"
                  />
                  <p className="text-sm font-medium break-all">
                    {form.register_title || `注册 ${form.site_title}`}
                  </p>
                  <p className="mt-0.5 text-xs text-muted-foreground break-all">
                    {form.register_subtitle}
                  </p>
                </div>
              </div>
            </div>

            <p className="text-xs text-muted-foreground">
              未设置 LOGO 时使用默认图标 {DEFAULT_LOGO}
            </p>
          </CardContent>
        </Card>
      </div>

      {dialog}
    </div>
  )
}