import {
  Bell,
  CandlestickChart,
  ClipboardList,
  Compass,
  CreditCard,
  Dumbbell,
  FileText,
  Footprints,
  HandCoins,
  HeartPulse,
  History,
  Home,
  LayoutDashboard,
  ListTodo,
  MoonStar,
  Package,
  PieChart,
  Pill,
  Plane,
  Receipt,
  ShoppingCart,
  Target,
  TrendingUp,
  Wallet,
  type LucideIcon,
} from 'lucide-react'

export type NavEntry = {
  title: string
  url: string
  icon: LucideIcon
}

export type NavSection = {
  title: string
  icon: LucideIcon
  /** 系统功能区（首页/通知/日志），置顶展示且不显示分区标题 */
  system?: boolean
  children: NavEntry[]
}

export const navigation: NavSection[] = [
  {
    title: '系统',
    icon: Home,
    system: true,
    children: [
      { title: '系统首页', url: '/home', icon: Home },
      { title: '通知中心', url: '/notifications', icon: Bell },
      { title: '活动日志', url: '/activity-logs', icon: History },
    ],
  },
  {
    title: '健康中心',
    icon: HeartPulse,
    children: [
      { title: '健康总览', url: '/health/overview', icon: HeartPulse },
      { title: '睡眠体征', url: '/health/vitals-sleep', icon: MoonStar },
      { title: '健身运动', url: '/health/fitness', icon: Dumbbell },
      { title: '步数统计', url: '/health/steps', icon: Footprints },
      { title: '体检指标', url: '/health/checkup', icon: ClipboardList },
      { title: '用药跟踪', url: '/health/medication', icon: Pill },
      { title: '健康报告', url: '/health/reports', icon: FileText },
    ],
  },
  {
    title: '财务中心',
    icon: Wallet,
    children: [
      { title: '财务总览', url: '/finance/overview', icon: PieChart },
      { title: '购物记录', url: '/finance/shopping', icon: ShoppingCart },
      { title: '旅行开支', url: '/finance/travel', icon: Plane },
      { title: '账单管理', url: '/finance/bills', icon: Receipt },
      { title: '账单提醒', url: '/finance/reminders', icon: Bell },
      { title: '财务规划', url: '/finance/planning', icon: Target },
      { title: '债务管理', url: '/finance/debts', icon: HandCoins },
      { title: '财务报告', url: '/finance/reports', icon: FileText },
    ],
  },
  {
    title: '生活中心',
    icon: Compass,
    children: [
      { title: '生活总览', url: '/lifestyle/overview', icon: LayoutDashboard },
      { title: '物品追踪', url: '/lifestyle/items', icon: Package },
      { title: '卡片管理', url: '/lifestyle/cards', icon: CreditCard },
      { title: '待办清单', url: '/lifestyle/todos', icon: ListTodo },
      { title: '生活报告', url: '/lifestyle/reports', icon: FileText },
    ],
  },
  {
    title: '投资中心',
    icon: TrendingUp,
    children: [
      { title: '投资总览', url: '/investment/overview', icon: LayoutDashboard },
      { title: '外汇交易', url: '/investment/forex', icon: CandlestickChart },
      { title: '投资报告', url: '/investment/reports', icon: FileText },
    ],
  },
]

/** 根据路径查找对应的菜单项及其所属分区，用于面包屑与页面标题。 */
export function findNavEntry(
  pathname: string,
): { section: NavSection; entry: NavEntry } | null {
  for (const section of navigation) {
    const entry = section.children.find((c) => c.url === pathname)
    if (entry) {
      return { section, entry }
    }
  }
  return null
}
