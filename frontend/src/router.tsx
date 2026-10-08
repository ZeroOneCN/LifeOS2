import { lazy, Suspense } from 'react'
import { createBrowserRouter, Navigate } from 'react-router-dom'
import { Loader2 } from 'lucide-react'

import { RequireAuth, RequireAdmin, GuestOnly } from '@/components/auth-guard'
import { navigation } from '@/config/navigation'
import { AdminLayout } from '@/layouts/admin-layout'
import { LoginPage } from '@/pages/login'
import { RegisterPage } from '@/pages/register'

// 登录/注册页保持同步导入（首屏需立即可用），其余业务页面全部懒加载以减小首屏 JS 体积
const ActivityLogsPage = lazy(() => import('@/pages/activity-logs').then((m) => ({ default: m.ActivityLogsPage })))
const BillsPage = lazy(() => import('@/pages/finance/bills').then((m) => ({ default: m.BillsPage })))
const DebtsPage = lazy(() => import('@/pages/finance/debts').then((m) => ({ default: m.DebtsPage })))
const FinanceOverviewPage = lazy(() => import('@/pages/finance/overview').then((m) => ({ default: m.FinanceOverviewPage })))
const ForexPage = lazy(() => import('@/pages/investment/forex').then((m) => ({ default: m.ForexPage })))
const InvestmentOverviewPage = lazy(() => import('@/pages/investment/overview').then((m) => ({ default: m.InvestmentOverviewPage })))
const InvestmentReportsPage = lazy(() => import('@/pages/investment/reports').then((m) => ({ default: m.InvestmentReportsPage })))
const FinanceReportsPage = lazy(() => import('@/pages/finance/reports').then((m) => ({ default: m.FinanceReportsPage })))
const PlanningPage = lazy(() => import('@/pages/finance/planning').then((m) => ({ default: m.PlanningPage })))
const RemindersPage = lazy(() => import('@/pages/finance/reminders').then((m) => ({ default: m.RemindersPage })))
const ShoppingPage = lazy(() => import('@/pages/finance/shopping').then((m) => ({ default: m.ShoppingPage })))
const TravelPage = lazy(() => import('@/pages/finance/travel').then((m) => ({ default: m.TravelPage })))
const HomePage = lazy(() => import('@/pages/home').then((m) => ({ default: m.HomePage })))
const CheckupPage = lazy(() => import('@/pages/health/checkup').then((m) => ({ default: m.CheckupPage })))
const FitnessTabsPage = lazy(() => import('@/pages/health/fitness-tabs').then((m) => ({ default: m.FitnessTabsPage })))
const HealthOverviewPage = lazy(() => import('@/pages/health/overview').then((m) => ({ default: m.HealthOverviewPage })))
const MedicationPage = lazy(() => import('@/pages/health/medication').then((m) => ({ default: m.MedicationPage })))
const ReportsPage = lazy(() => import('@/pages/health/reports').then((m) => ({ default: m.ReportsPage })))
const StepsPage = lazy(() => import('@/pages/health/steps').then((m) => ({ default: m.StepsPage })))
const VitalsSleepPage = lazy(() => import('@/pages/health/vitals-sleep').then((m) => ({ default: m.VitalsSleepPage })))
const ItemsPage = lazy(() => import('@/pages/lifestyle/items').then((m) => ({ default: m.ItemsPage })))
const CardsPage = lazy(() => import('@/pages/lifestyle/cards').then((m) => ({ default: m.CardsPage })))
const LifestyleOverviewPage = lazy(() => import('@/pages/lifestyle/overview').then((m) => ({ default: m.LifestyleOverviewPage })))
const LifestyleReportsPage = lazy(() => import('@/pages/lifestyle/reports').then((m) => ({ default: m.LifestyleReportsPage })))
const TodosPage = lazy(() => import('@/pages/lifestyle/todos').then((m) => ({ default: m.TodosPage })))
const NotFoundPage = lazy(() => import('@/pages/not-found').then((m) => ({ default: m.NotFoundPage })))
const NotificationsPage = lazy(() => import('@/pages/notifications').then((m) => ({ default: m.NotificationsPage })))
const PlaceholderPage = lazy(() => import('@/pages/placeholder').then((m) => ({ default: m.PlaceholderPage })))
const AccountSettingsPage = lazy(() => import('@/pages/account-settings').then((m) => ({ default: m.AccountSettingsPage })))
const BackupPage = lazy(() => import('@/pages/system/backup').then((m) => ({ default: m.BackupPage })))
const SiteSettingsPage = lazy(() => import('@/pages/system/site-settings').then((m) => ({ default: m.SiteSettingsPage })))
const UserCenterPage = lazy(() => import('@/pages/user-center').then((m) => ({ default: m.UserCenterPage })))
const SessionsPage = lazy(() => import('@/pages/sessions').then((m) => ({ default: m.SessionsPage })))
const LoginAuditPage = lazy(() => import('@/pages/login-audit').then((m) => ({ default: m.LoginAuditPage })))

/** 懒加载页面的统一加载占位：居中旋转图标，避免白屏闪烁。 */
function PageLoader() {
  return (
    <div className="flex min-h-[60vh] items-center justify-center">
      <Loader2 className="size-8 animate-spin text-muted-foreground" />
    </div>
  )
}

/** 用 Suspense 包裹懒加载组件，统一加载态。 */
function withSuspense(element: React.ReactNode) {
  return <Suspense fallback={<PageLoader />}>{element}</Suspense>
}

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
  '/sessions': <SessionsPage />,
  '/login-audit': <LoginAuditPage />,
  '/notifications': <NotificationsPage />,
  '/activity-logs': <ActivityLogsPage />,
  '/backup': <BackupPage />,
  '/system-settings': <SiteSettingsPage />,
  '/user-center': <UserCenterPage />,
  '/user-center/settings': <AccountSettingsPage />,
}

// 需要管理员权限的页面路径
const ADMIN_PATHS = new Set(['/system-settings', '/backup', '/activity-logs', '/login-audit'])

const placeholderRoutes = navigation.flatMap((section) =>
  section.children
    .filter((entry) => entry.url !== '/home')
    .map((entry) => {
      const page = implementedPages[entry.url] ?? (
        <PlaceholderPage
          title={entry.title}
          description={`${entry.title} 模块规划中，具体功能将逐步实现。`}
        />
      )
      return {
        path: entry.url,
        element: ADMIN_PATHS.has(entry.url)
          ? withSuspense(<RequireAdmin>{page}</RequireAdmin>)
          : withSuspense(page),
      }
    }),
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
      { path: '/home', element: withSuspense(<HomePage />) },
      { path: '/user-center', element: withSuspense(<UserCenterPage />) },
      { path: '/user-center/settings', element: withSuspense(<AccountSettingsPage />) },
      { path: '/sessions', element: withSuspense(<SessionsPage />) },
      ...placeholderRoutes,
      { path: '*', element: withSuspense(<NotFoundPage />) },
    ],
  },
])
