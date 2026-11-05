import { Navigate } from 'react-router-dom'

import { PageSkeleton } from '@/components/page-skeleton'
import { useAuth } from '@/lib/auth'

/** 认证守卫：未登录访问受保护页面时重定向到登录页。 */
export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { isAuthed } = useAuth()
  // token 存在时立即放行，让应用外壳与页面骨架先渲染；
  // 用户信息加载（/auth/me）不再阻塞整页，避免首屏只剩居中 spinner
  if (!isAuthed) return <Navigate to="/login" replace />
  return <>{children}</>
}

/** 管理员守卫：非管理员访问系统管理页面时重定向到首页。 */
export function RequireAdmin({ children }: { children: React.ReactNode }) {
  const { isAuthed, user, userLoaded } = useAuth()
  // 用户信息未就绪时在内容区显示页面骨架，外壳（侧栏/页头）保持可见
  if (isAuthed && !userLoaded) return <PageSkeleton />
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
