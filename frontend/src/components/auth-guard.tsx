import { Navigate } from 'react-router-dom'

import { useAuth } from '@/lib/auth'

/** 认证守卫：未登录访问受保护页面时重定向到登录页。 */
export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { isAuthed } = useAuth()
  if (!isAuthed) return <Navigate to="/login" replace />
  return <>{children}</>
}

/** 游客守卫：已登录访问登录/注册页时重定向到首页。 */
export function GuestOnly({ children }: { children: React.ReactNode }) {
  const { isAuthed } = useAuth()
  if (isAuthed) return <Navigate to="/home" replace />
  return <>{children}</>
}