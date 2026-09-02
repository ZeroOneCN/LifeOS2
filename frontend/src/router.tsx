import { createBrowserRouter, Navigate } from 'react-router-dom'

import { navigation } from '@/config/navigation'
import { AdminLayout } from '@/layouts/admin-layout'
import { HomePage } from '@/pages/home'
import { CheckupPage } from '@/pages/health/checkup'
import { FitnessPage } from '@/pages/health/fitness'
import { MedicationPage } from '@/pages/health/medication'
import { HealthOverviewPage } from '@/pages/health/overview'
import { ReportsPage } from '@/pages/health/reports'
import { StepsPage } from '@/pages/health/steps'
import { VitalsSleepPage } from '@/pages/health/vitals-sleep'
import { NotFoundPage } from '@/pages/not-found'
import { PlaceholderPage } from '@/pages/placeholder'

// 已实现具体功能的页面，其余菜单项统一使用占位页。
const implementedPages: Record<string, React.ReactNode> = {
  '/health/overview': <HealthOverviewPage />,
  '/health/vitals-sleep': <VitalsSleepPage />,
  '/health/fitness': <FitnessPage />,
  '/health/steps': <StepsPage />,
  '/health/checkup': <CheckupPage />,
  '/health/reports': <ReportsPage />,
  '/health/medication': <MedicationPage />,
}

const placeholderRoutes = navigation.flatMap((section) =>
  section.children
    .filter((entry) => entry.url !== '/home')
    .map((entry) => ({
      path: entry.url,
      element:
        implementedPages[entry.url] ?? (
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
