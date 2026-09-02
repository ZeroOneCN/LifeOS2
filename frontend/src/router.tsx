import { createBrowserRouter, Navigate } from 'react-router-dom'

import { navigation } from '@/config/navigation'
import { AdminLayout } from '@/layouts/admin-layout'
import { ActivityLogsPage } from '@/pages/activity-logs'
import { BillsPage } from '@/pages/finance/bills'
import { DebtsPage } from '@/pages/finance/debts'
import { FinanceOverviewPage } from '@/pages/finance/overview'
import { ForexPage } from '@/pages/investment/forex'
import { PlanningPage } from '@/pages/finance/planning'
import { PurchasesPage } from '@/pages/finance/purchases'
import { RemindersPage } from '@/pages/finance/reminders'
import { TravelPage } from '@/pages/finance/travel'
import { HomePage } from '@/pages/home'
import { CheckupPage } from '@/pages/health/checkup'
import { BodyPage } from '@/pages/health/body'
import { DietPage } from '@/pages/health/diet'
import { FitnessDashboardPage } from '@/pages/health/fitness-dashboard'
import { FitnessPage } from '@/pages/health/fitness'
import { MedicationPage } from '@/pages/health/medication'
import { HealthOverviewPage } from '@/pages/health/overview'
import { ReportsPage } from '@/pages/health/reports'
import { StepsPage } from '@/pages/health/steps'
import { VitalsSleepPage } from '@/pages/health/vitals-sleep'
import { ItemsPage } from '@/pages/lifestyle/items'
import { SchedulePage } from '@/pages/lifestyle/schedule'
import { SimCardsPage } from '@/pages/lifestyle/sim-cards'
import { TodosPage } from '@/pages/lifestyle/todos'
import { NotFoundPage } from '@/pages/not-found'
import { NotificationsPage } from '@/pages/notifications'
import { PlaceholderPage } from '@/pages/placeholder'
import { AccountSettingsPage } from '@/pages/account-settings'
import { UserCenterPage } from '@/pages/user-center'

// 已实现具体功能的页面，其余菜单项统一使用占位页。
const implementedPages: Record<string, React.ReactNode> = {
  '/health/overview': <HealthOverviewPage />,
  '/health/vitals-sleep': <VitalsSleepPage />,
  '/health/fitness': <FitnessPage />,
  '/health/diet': <DietPage />,
  '/health/body': <BodyPage />,
  '/health/fitness/dashboard': <FitnessDashboardPage />,
  '/health/steps': <StepsPage />,
  '/health/checkup': <CheckupPage />,
  '/health/reports': <ReportsPage />,
  '/health/medication': <MedicationPage />,
  '/finance/overview': <FinanceOverviewPage />,
  '/finance/purchases': <PurchasesPage />,
  '/finance/travel': <TravelPage />,
  '/finance/bills': <BillsPage />,
  '/finance/reminders': <RemindersPage />,
  '/finance/planning': <PlanningPage />,
  '/finance/debts': <DebtsPage />,
  '/lifestyle/items': <ItemsPage />,
  '/lifestyle/sim-cards': <SimCardsPage />,
  '/lifestyle/todos': <TodosPage />,
  '/lifestyle/schedule': <SchedulePage />,
  '/investment/forex': <ForexPage />,
  '/notifications': <NotificationsPage />,
  '/activity-logs': <ActivityLogsPage />,
  '/user-center': <UserCenterPage />,
  '/user-center/settings': <AccountSettingsPage />,
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
      { path: '/user-center', element: <UserCenterPage /> },
      { path: '/user-center/settings', element: <AccountSettingsPage /> },
      ...placeholderRoutes,
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])
