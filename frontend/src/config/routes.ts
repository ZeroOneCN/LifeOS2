import { lazy } from 'react'
import type { ComponentType } from 'react'
import {
  BadgeCheck,
  Bell,
  CandlestickChart,
  ClipboardList,
  Compass,
  CreditCard,
  Database,
  Dumbbell,
  FileText,
  Footprints,
  HandCoins,
  HeartPulse,
  History,
  Home,
  LayoutDashboard,
  Monitor,
  MoonStar,
  Package,
  PieChart,
  Pill,
  Plane,
  Receipt,
  Settings,
  Shield,
  ShoppingCart,
  Target,
  TrendingUp,
  Wallet,
  type LucideIcon,
} from 'lucide-react'

/** 侧边导航分区元数据。key 供路由表引用，避免标题与图标出现第二份来源。 */
export type NavSectionMeta = {
  key: string
  title: string
  icon: LucideIcon
  /** 系统功能区（首页/通知/日志），置顶展示且不显示分区标题 */
  system?: boolean
}

/** 单个页面的路由元数据，是路由、导航、面包屑的唯一真源。 */
export type RouteEntry = {
  /** 路由路径，同时作为导航跳转地址 */
  path: string
  /** 页面标题，供侧边导航与面包屑共用 */
  title: string
  /** 所属分区 key；未归属分区（如用户中心）时为空 */
  section?: string
  /** 仅管理员可访问，路由守卫据此自动包裹 RequireAdmin */
  adminOnly?: boolean
  /** 是否在侧边导航中展示 */
  inNav: boolean
  icon: LucideIcon
  component: ComponentType
}

/** 导航分区顺序：系统分区置顶，其后为四大业务中心。 */
export const SECTIONS: NavSectionMeta[] = [
  { key: 'system', title: '系统', icon: Home, system: true },
  { key: 'health', title: '健康中心', icon: HeartPulse },
  { key: 'finance', title: '财务中心', icon: Wallet },
  { key: 'lifestyle', title: '生活中心', icon: Compass },
  { key: 'investment', title: '投资中心', icon: TrendingUp },
]

/** 默认登录后跳转路径。 */
export const DEFAULT_ROUTE = '/home'

/**
 * 全量路由表。顺序即导航展示顺序，同时决定路由注册顺序。
 * 健康模块的饮食、身体、健身仪表盘三个页面由 FitnessTabsPage 内部 tab 承载，
 * 不再单独注册路由。
 */
export const ROUTES: RouteEntry[] = [
  {
    path: '/home',
    title: '系统首页',
    section: 'system',
    inNav: true,
    icon: Home,
    component: lazy(() => import('@/pages/home').then((m) => ({ default: m.HomePage }))),
  },
  {
    path: '/notifications',
    title: '通知中心',
    section: 'system',
    inNav: true,
    icon: Bell,
    component: lazy(() =>
      import('@/pages/notifications').then((m) => ({ default: m.NotificationsPage })),
    ),
  },
  {
    path: '/activity-logs',
    title: '活动日志',
    section: 'system',
    adminOnly: true,
    inNav: true,
    icon: History,
    component: lazy(() =>
      import('@/pages/activity-logs').then((m) => ({ default: m.ActivityLogsPage })),
    ),
  },
  {
    path: '/login-audit',
    title: '安全审计',
    section: 'system',
    adminOnly: true,
    inNav: true,
    icon: Shield,
    component: lazy(() =>
      import('@/pages/login-audit').then((m) => ({ default: m.LoginAuditPage })),
    ),
  },
  {
    path: '/sessions',
    title: '会话管理',
    section: 'system',
    adminOnly: true,
    inNav: true,
    icon: Monitor,
    component: lazy(() => import('@/pages/sessions').then((m) => ({ default: m.SessionsPage }))),
  },
  {
    path: '/backup',
    title: '数据备份',
    section: 'system',
    adminOnly: true,
    inNav: true,
    icon: Database,
    component: lazy(() => import('@/pages/system/backup').then((m) => ({ default: m.BackupPage }))),
  },
  {
    path: '/system-settings',
    title: '系统设置',
    section: 'system',
    adminOnly: true,
    inNav: true,
    icon: Settings,
    component: lazy(() =>
      import('@/pages/system/site-settings').then((m) => ({ default: m.SiteSettingsPage })),
    ),
  },
  {
    path: '/health/overview',
    title: '健康总览',
    section: 'health',
    inNav: true,
    icon: HeartPulse,
    component: lazy(() =>
      import('@/pages/health/overview').then((m) => ({ default: m.HealthOverviewPage })),
    ),
  },
  {
    path: '/health/vitals-sleep',
    title: '睡眠体征',
    section: 'health',
    inNav: true,
    icon: MoonStar,
    component: lazy(() =>
      import('@/pages/health/vitals-sleep').then((m) => ({ default: m.VitalsSleepPage })),
    ),
  },
  {
    path: '/health/fitness',
    title: '健身运动',
    section: 'health',
    inNav: true,
    icon: Dumbbell,
    component: lazy(() =>
      import('@/pages/health/fitness-tabs').then((m) => ({ default: m.FitnessTabsPage })),
    ),
  },
  {
    path: '/health/steps',
    title: '步数统计',
    section: 'health',
    inNav: true,
    icon: Footprints,
    component: lazy(() => import('@/pages/health/steps').then((m) => ({ default: m.StepsPage }))),
  },
  {
    path: '/health/checkup',
    title: '体检指标',
    section: 'health',
    inNav: true,
    icon: ClipboardList,
    component: lazy(() => import('@/pages/health/checkup').then((m) => ({ default: m.CheckupPage }))),
  },
  {
    path: '/health/medication',
    title: '用药跟踪',
    section: 'health',
    inNav: true,
    icon: Pill,
    component: lazy(() =>
      import('@/pages/health/medication').then((m) => ({ default: m.MedicationPage })),
    ),
  },
  {
    path: '/health/reports',
    title: '健康报告',
    section: 'health',
    inNav: true,
    icon: FileText,
    component: lazy(() => import('@/pages/health/reports').then((m) => ({ default: m.ReportsPage }))),
  },
  {
    path: '/finance/overview',
    title: '财务总览',
    section: 'finance',
    inNav: true,
    icon: PieChart,
    component: lazy(() =>
      import('@/pages/finance/overview').then((m) => ({ default: m.FinanceOverviewPage })),
    ),
  },
  {
    path: '/finance/shopping',
    title: '购物记录',
    section: 'finance',
    inNav: true,
    icon: ShoppingCart,
    component: lazy(() =>
      import('@/pages/finance/shopping').then((m) => ({ default: m.ShoppingPage })),
    ),
  },
  {
    path: '/finance/travel',
    title: '旅行开支',
    section: 'finance',
    inNav: true,
    icon: Plane,
    component: lazy(() => import('@/pages/finance/travel').then((m) => ({ default: m.TravelPage }))),
  },
  {
    path: '/finance/bills',
    title: '账单管理',
    section: 'finance',
    inNav: true,
    icon: Receipt,
    component: lazy(() => import('@/pages/finance/bills').then((m) => ({ default: m.BillsPage }))),
  },
  {
    path: '/finance/planning',
    title: '财务规划',
    section: 'finance',
    inNav: true,
    icon: Target,
    component: lazy(() =>
      import('@/pages/finance/planning').then((m) => ({ default: m.PlanningPage })),
    ),
  },
  {
    path: '/finance/debts',
    title: '债务管理',
    section: 'finance',
    inNav: true,
    icon: HandCoins,
    component: lazy(() => import('@/pages/finance/debts').then((m) => ({ default: m.DebtsPage }))),
  },
  {
    path: '/finance/reports',
    title: '财务报告',
    section: 'finance',
    inNav: true,
    icon: FileText,
    component: lazy(() =>
      import('@/pages/finance/reports').then((m) => ({ default: m.FinanceReportsPage })),
    ),
  },
  {
    path: '/lifestyle/overview',
    title: '生活总览',
    section: 'lifestyle',
    inNav: true,
    icon: LayoutDashboard,
    component: lazy(() =>
      import('@/pages/lifestyle/overview').then((m) => ({ default: m.LifestyleOverviewPage })),
    ),
  },
  {
    path: '/lifestyle/items',
    title: '物品追踪',
    section: 'lifestyle',
    inNav: true,
    icon: Package,
    component: lazy(() => import('@/pages/lifestyle/items').then((m) => ({ default: m.ItemsPage }))),
  },
  {
    path: '/lifestyle/cards',
    title: '卡片管理',
    section: 'lifestyle',
    inNav: true,
    icon: CreditCard,
    component: lazy(() => import('@/pages/lifestyle/cards').then((m) => ({ default: m.CardsPage }))),
  },
  {
    path: '/lifestyle/reports',
    title: '生活报告',
    section: 'lifestyle',
    inNav: true,
    icon: FileText,
    component: lazy(() =>
      import('@/pages/lifestyle/reports').then((m) => ({ default: m.LifestyleReportsPage })),
    ),
  },
  {
    path: '/investment/overview',
    title: '投资总览',
    section: 'investment',
    inNav: true,
    icon: LayoutDashboard,
    component: lazy(() =>
      import('@/pages/investment/overview').then((m) => ({ default: m.InvestmentOverviewPage })),
    ),
  },
  {
    path: '/investment/forex',
    title: '外汇交易',
    section: 'investment',
    inNav: true,
    icon: CandlestickChart,
    component: lazy(() => import('@/pages/investment/forex').then((m) => ({ default: m.ForexPage }))),
  },
  {
    path: '/investment/reports',
    title: '投资报告',
    section: 'investment',
    inNav: true,
    icon: FileText,
    component: lazy(() =>
      import('@/pages/investment/reports').then((m) => ({ default: m.InvestmentReportsPage })),
    ),
  },
  {
    path: '/user-center',
    title: '用户中心',
    inNav: false,
    icon: BadgeCheck,
    component: lazy(() =>
      import('@/pages/user-center').then((m) => ({ default: m.UserCenterPage })),
    ),
  },
  {
    path: '/user-center/settings',
    title: '账号设置',
    inNav: false,
    icon: Settings,
    component: lazy(() =>
      import('@/pages/account-settings').then((m) => ({ default: m.AccountSettingsPage })),
    ),
  },
]

/** 根据路径查找路由元数据，供面包屑与页面标题使用。 */
export function findRoute(pathname: string): RouteEntry | undefined {
  return ROUTES.find((route) => route.path === pathname)
}

/** 根据分区 key 查找分区元数据。 */
export function findSection(key?: string): NavSectionMeta | undefined {
  if (!key) return undefined
  return SECTIONS.find((section) => section.key === key)
}
