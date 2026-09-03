import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Loader2, UserPlus } from 'lucide-react'

import { Button } from '@/components/ui/button'
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
import { useAuth } from '@/lib/auth'

export function RegisterPage() {
  const navigate = useNavigate()
  const { register } = useAuth()
  const [account, setAccount] = useState('')
  const [nickname, setNickname] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPwd, setConfirmPwd] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!account.trim()) {
      setError('请输入账号')
      return
    }
    if (password.length < 6) {
      setError('密码长度不能少于 6 位')
      return
    }
    if (password !== confirmPwd) {
      setError('两次输入的密码不一致')
      return
    }
    setLoading(true)
    setError('')
    try {
      await register(account.trim(), nickname.trim(), password)
      navigate('/home')
    } catch (err) {
      setError(err instanceof Error ? err.message : '注册失败')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/30 p-4">
      <Card className="w-full max-w-sm">
        <CardHeader className="text-center">
          <div className="mx-auto mb-2 flex size-10 items-center justify-center rounded-lg bg-primary text-lg font-bold text-primary-foreground">
            L
          </div>
          <CardTitle className="text-xl">注册 LifeOS 账号</CardTitle>
          <CardDescription>创建账号以使用 LifeOS 后台</CardDescription>
        </CardHeader>
        <form onSubmit={submit}>
          <CardContent className="space-y-4">
            {error && (
              <p className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {error}
              </p>
            )}
            <div className="space-y-2">
              <Label htmlFor="reg_account">账号</Label>
              <Input
                id="reg_account"
                value={account}
                onChange={(e) => setAccount(e.target.value)}
                placeholder="登录账号（注册后不可更改）"
                autoComplete="off"
                autoFocus
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="reg_nickname">昵称</Label>
              <Input
                id="reg_nickname"
                value={nickname}
                onChange={(e) => setNickname(e.target.value)}
                placeholder="显示名称（可在个人资料修改）"
                autoComplete="off"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="reg_password">密码</Label>
              <Input
                id="reg_password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="至少 6 位"
                autoComplete="new-password"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="reg_confirm">确认密码</Label>
              <Input
                id="reg_confirm"
                type="password"
                value={confirmPwd}
                onChange={(e) => setConfirmPwd(e.target.value)}
                placeholder="再次输入密码"
                autoComplete="new-password"
              />
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? <Loader2 className="animate-spin" /> : <UserPlus />}
              注册
            </Button>
          </CardContent>
        </form>
        <CardFooter className="justify-center text-sm text-muted-foreground">
          已有账号？
          <Link to="/login" className="ml-1 text-primary hover:underline">
            去登录
          </Link>
        </CardFooter>
      </Card>
    </div>
  )
}