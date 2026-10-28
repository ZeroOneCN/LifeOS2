import { Navigate } from 'react-router-dom'
import { Loader2 } from 'lucide-react'

import { useAuth } from '@/lib/auth'

/** 认证守卫：未登录访问受保护页面时重定向到登录页。 */
export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { isAuthed, userLoaded } = useAuth()
  // token 存在但用户信息尚未拉取完成时，显示加载占位避免闪烁到登录页
  if (isAuthed && !userLoaded) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Loader2 className="size-8 animate-spin text-muted-foreground" />
      </div>
    )
  }
  if (!isAuthed) return <Navigate to="/login" replace />
  return <>{children}</>
}

/** 管理员守卫：非管理员访问系统管理页面时重定向到首页。 */
export function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { isAuthed, user, userLoaded } = useAuth()
  if (isAuthed && !userLoaded) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Loader2 className="size-8 animate-spin text-muted-foreground" />
      </div>
    )
  }
  if (!isAuthed) return <Navigate to="/login" replace />
  if (!user?.isAdmin) return <Navigate to="/home" replace />
  return <>{children}</>
}

/** 游客守卫：已登录访问登录/注册页时重定向到首页。 */
export function GuestOnly({ children }: { children: React.ReactNode }) {
  const { isAuthed } = useAuth()
  if (isAuthed) return <Navigate to="/home" replace />
  return <>{children}</>
}
