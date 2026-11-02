import type { LucideIcon } from 'lucide-react'

import { ROUTES, SECTIONS } from './routes'

export type NavEntry = {
  title: string
  url: string
  icon: LucideIcon
  /** 仅管理员可见（系统设置/备份/活动日志/会话管理等） */
  adminOnly?: boolean
}

export type NavSection = {
  title: string
  icon: LucideIcon
  /** 系统功能区（首页/通知/日志），置顶展示且不显示分区标题 */
  system?: boolean
  children: NavEntry[]
}

/**
 * 侧边导航完全由 routes.ts 路由表派生，不再单独维护第二份菜单配置。
 * 新增页面只需在路由表中登记 inNav 与 section，路由与导航同步生效。
 */
export const navigation: NavSection[] = SECTIONS.map((section) => ({
  title: section.title,
  icon: section.icon,
  system: section.system,
  children: ROUTES.filter((route) => route.inNav && route.section === section.key).map((route) => ({
    title: route.title,
    url: route.path,
    icon: route.icon,
    adminOnly: route.adminOnly,
  })),
}))
