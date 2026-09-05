import { createBrowserRouter, Navigate } from 'react-router-dom'

import { RequireAuth, GuestOnly } from '@/components/auth-guard'
import { navigation } from '@/config/navigation'
import { AdminLayout } from '@/layouts/admin-layout'
import { ActivityLogsPage } from '@/pages/activity-logs'
import { BillsPage } from '@/pages/finance/bills'
import { DebtsPage } from '@/pages/finance/debts'
import { FinanceOverviewPage } from '@/pages/finance/overview'
import { ForexPage } from '@/pages/investment/forex'
import { InvestmentOverviewPage } from '@/pages/investment/overview'
import { InvestmentReportsPage } from '@/pages/investment/reports'
import { FinanceReportsPage } from '@/pages/finance/reports'
import { PlanningPage } from '@/pages/finance/planning'
import { RemindersPage } from '@/pages/finance/reminders'
import { ShoppingPage } from '@/pages/finance/shopping'
import { TravelPage } from '@/pages/finance/travel'
import { HomePage } from '@/pages/home'
import { CheckupPage } from '@/pages/health/checkup'
import { FitnessTabsPage } from '@/pages/health/fitness-tabs'
import { HealthOverviewPage } from '@/pages/health/overview'
import { MedicationPage } from '@/pages/health/medication'
import { ReportsPage } from '@/pages/health/reports'
import { StepsPage } from '@/pages/health/steps'
import { VitalsSleepPage } from '@/pages/health/vitals-sleep'
import { ItemsPage } from '@/pages/lifestyle/items'
import { CardsPage } from '@/pages/lifestyle/cards'
import { LifestyleOverviewPage } from '@/pages/lifestyle/overview'
import { LifestyleReportsPage } from '@/pages/lifestyle/reports'
import { TodosPage } from '@/pages/lifestyle/todos'
import { NotFoundPage } from '@/pages/not-found'
import { NotificationsPage } from '@/pages/notifications'
import { PlaceholderPage } from '@/pages/placeholder'
import { AccountSettingsPage } from '@/pages/account-settings'
import { BackupPage } from '@/pages/system/backup'
import { UserCenterPage } from '@/pages/user-center'
import { LoginPage } from '@/pages/login'
import { RegisterPage } from '@/pages/register'

// 已实现具体功能的页面，其余菜单项统一使用占位页。
const implementedPages: Record<string, React.ReactNode> = {
  '/health/overview': <HealthOverviewPage />,
  '/health/vitals-sleep': <VitalsSleepPage />,
  '/health/fitness': <FitnessTabsPage />,
  '/health/diet': <FitnessTabsPage />,
  '/health/body': <FitnessTabsPage />,
  '/health/fitness/dashboard': <FitnessTabsPage />,
  '/health/steps': <StepsPage />,
  '/health/checkup': <CheckupPage />,
  '/health/reports': <ReportsPage />,
  '/health/medication': <MedicationPage />,
  '/finance/overview': <FinanceOverviewPage />,
  '/finance/shopping': <ShoppingPage />,
  '/finance/travel': <TravelPage />,
  '/finance/bills': <BillsPage />,
  '/finance/reminders': <RemindersPage />,
  '/finance/planning': <PlanningPage />,
  '/finance/debts': <DebtsPage />,
  '/finance/reports': <FinanceReportsPage />,
  '/lifestyle/overview': <LifestyleOverviewPage />,
  '/lifestyle/items': <ItemsPage />,
  '/lifestyle/cards': <CardsPage />,
  '/lifestyle/todos': <TodosPage />,
  '/lifestyle/reports': <LifestyleReportsPage />,
  '/investment/overview': <InvestmentOverviewPage />,
  '/investment/forex': <ForexPage />,
  '/investment/reports': <InvestmentReportsPage />,
  '/notifications': <NotificationsPage />,
  '/activity-logs': <ActivityLogsPage />,
  '/backup': <BackupPage />,
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
  { path: '/login', element: <GuestOnly><LoginPage /></GuestOnly> },
  { path: '/register', element: <GuestOnly><RegisterPage /></GuestOnly> },
  {
    element: (
      <RequireAuth>
        <AdminLayout />
      </RequireAuth>
    ),
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
