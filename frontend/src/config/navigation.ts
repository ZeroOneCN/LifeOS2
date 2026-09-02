import {
  Bell,
  Calendar,
  CandlestickChart,
  ClipboardList,
  Compass,
  CreditCard,
  Dumbbell,
  FileText,
  Footprints,
  HeartPulse,
  History,
  Home,
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
  User,
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
  collapsible: boolean
  children: NavEntry[]
}

export const navigation: NavSection[] = [
  {
    title: '系统',
    icon: Home,
    collapsible: false,
    children: [
      { title: '系统首页', url: '/home', icon: Home },
      { title: '通知中心', url: '/notifications', icon: Bell },
      { title: '活动日志', url: '/activity-logs', icon: History },
      { title: '用户资料', url: '/profile', icon: User },
    ],
  },
  {
    title: '健康中心',
    icon: HeartPulse,
    collapsible: true,
    children: [
      { title: '健康总览', url: '/health/overview', icon: HeartPulse },
      { title: '生命体征与睡眠', url: '/health/vitals-sleep', icon: MoonStar },
      { title: '健身与运动', url: '/health/fitness', icon: Dumbbell },
      { title: '步数统计', url: '/health/steps', icon: Footprints },
      { title: '体检指标', url: '/health/checkup', icon: ClipboardList },
      { title: '健康报告', url: '/health/reports', icon: FileText },
      { title: '用药跟踪', url: '/health/medication', icon: Pill },
    ],
  },
  {
    title: '财务中心',
    icon: Wallet,
    collapsible: true,
    children: [
      { title: '财务总览', url: '/finance/overview', icon: PieChart },
      { title: '购买记录', url: '/finance/purchases', icon: ShoppingCart },
      { title: '旅行开支', url: '/finance/travel', icon: Plane },
      { title: '账单管理', url: '/finance/bills', icon: Receipt },
      { title: '账单提醒', url: '/finance/reminders', icon: Bell },
      { title: '财务规划', url: '/finance/planning', icon: Target },
    ],
  },
  {
    title: '生活中心',
    icon: Compass,
    collapsible: true,
    children: [
      { title: '物品追踪', url: '/lifestyle/items', icon: Package },
      { title: 'SIM/卡服务', url: '/lifestyle/sim-cards', icon: CreditCard },
      { title: '待办清单', url: '/lifestyle/todos', icon: ListTodo },
      { title: '日程管理', url: '/lifestyle/schedule', icon: Calendar },
    ],
  },
  {
    title: '投资中心',
    icon: TrendingUp,
    collapsible: true,
    children: [
      { title: '外汇交易', url: '/investment/forex', icon: CandlestickChart },
    ],
  },
]

/** 根据路径查找对应的菜单项及其所属分组，用于面包屑与页面标题。 */
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
