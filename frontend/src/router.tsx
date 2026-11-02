import { lazy, Suspense } from 'react'
import { createBrowserRouter, Navigate } from 'react-router-dom'
import { Loader2 } from 'lucide-react'

import { RequireAuth, RequireAdmin, GuestOnly } from '@/components/auth-guard'
import { ErrorBoundary } from '@/components/error-boundary'
import { DEFAULT_ROUTE, ROUTES } from '@/config/routes'
import { AdminLayout } from '@/layouts/admin-layout'
import { LoginPage } from '@/pages/login'
import { RegisterPage } from '@/pages/register'

const NotFoundPage = lazy(() => import('@/pages/not-found').then((m) => ({ default: m.NotFoundPage })))

/** 懒加载页面的统一加载占位：居中旋转图标，避免白屏闪烁。 */
function PageLoader() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <Loader2 className="size-8 animate-spin text-muted-foreground" />
    </div>
  )
}

/** 用 ErrorBoundary + Suspense 包裹懒加载组件，统一加载态与异常兜底。 */
function withSuspense(element: React.ReactNode) {
  return (
    <ErrorBoundary>
      <Suspense fallback={<PageLoader />}>{element}</Suspense>
    </ErrorBoundary>
  )
}

/**
 * 按 routes.ts 的路由表生成业务路由。
 * 管理员守卫由 adminOnly 自动派生，避免手工维护路径集合造成漏配。
 */
const businessRoutes = ROUTES.map((route) => {
  const Page = route.component
  return {
    path: route.path,
    element: route.adminOnly
      ? withSuspense(<RequireAdmin>{<Page />}</RequireAdmin>)
      : withSuspense(<Page />),
  }
})

export const router = createBrowserRouter([
  {
    path: '/login',
    element: (
      <GuestOnly>
        <LoginPage />
      </GuestOnly>
    ),
  },
  {
    path: '/register',
    element: (
      <GuestOnly>
        <RegisterPage />
      </GuestOnly>
    ),
  },
  {
    element: (
      <RequireAuth>
        <AdminLayout />
      </RequireAuth>
    ),
    children: [
      { path: '/', element: <Navigate to={DEFAULT_ROUTE} replace /> },
      ...businessRoutes,
      { path: '*', element: withSuspense(<NotFoundPage />) },
    ],
  },
])
