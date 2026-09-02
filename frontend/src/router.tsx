import { createBrowserRouter, Navigate } from 'react-router-dom'

import { AdminLayout } from '@/layouts/admin-layout'
import { DashboardPage } from '@/pages/dashboard'
import { NotFoundPage } from '@/pages/not-found'
import { PlaceholderPage } from '@/pages/placeholder'
import { SettingsPage } from '@/pages/settings'

export const router = createBrowserRouter([
  {
    element: <AdminLayout />,
    children: [
      { path: '/', element: <Navigate to="/dashboard" replace /> },
      { path: '/dashboard', element: <DashboardPage /> },
      {
        path: '/system/users',
        element: (
          <PlaceholderPage
            title="用户管理"
            description="管理平台用户账号与权限分配。"
          />
        ),
      },
      {
        path: '/system/roles',
        element: (
          <PlaceholderPage
            title="角色管理"
            description="配置角色及其对应的权限集合。"
          />
        ),
      },
      { path: '/settings', element: <SettingsPage /> },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])
