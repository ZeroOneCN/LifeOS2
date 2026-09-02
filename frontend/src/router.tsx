import { createBrowserRouter, Navigate } from 'react-router-dom'

import { navigation } from '@/config/navigation'
import { AdminLayout } from '@/layouts/admin-layout'
import { HomePage } from '@/pages/home'
import { NotFoundPage } from '@/pages/not-found'
import { PlaceholderPage } from '@/pages/placeholder'

// 除首页外，其余菜单项统一渲染为占位页，后续按需替换为具体功能页。
const placeholderRoutes = navigation.flatMap((section) =>
  section.children
    .filter((entry) => entry.url !== '/home')
    .map((entry) => ({
      path: entry.url,
      element: (
        <PlaceholderPage
          title={entry.title}
          description={`${entry.title} 模块规划中，具体功能将逐步实现。`}
        />
      ),
    })),
)

export const router = createBrowserRouter([
  {
    element: <AdminLayout />,
    children: [
      { path: '/', element: <Navigate to="/home" replace /> },
      { path: '/home', element: <HomePage /> },
      ...placeholderRoutes,
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])
