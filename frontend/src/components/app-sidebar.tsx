import { useState } from 'react'
import { ChevronRight } from 'lucide-react'
import { NavLink, useLocation, useNavigate } from 'react-router-dom'

import { NavUser } from '@/components/nav-user'
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from '@/components/ui/collapsible'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  useSidebar,
} from '@/components/ui/sidebar'
import { navigation, type NavSection } from '@/config/navigation'

/** 业务中心分区渲染为可折叠子菜单；系统区保持平铺。 */
function SidebarSection({ section }: { section: NavSection }) {
  const { pathname } = useLocation()
  const navigate = useNavigate()
  const { state } = useSidebar()
  const [open, setOpen] = useState(() =>
    section.children.some((item) => item.url === pathname),
  )

  const collapsible = !section.system

  if (!collapsible) {
    return (
      <SidebarGroup>
        {!section.system && (
          <SidebarGroupLabel>{section.title}</SidebarGroupLabel>
        )}
        <SidebarGroupContent>
          <SidebarMenu>
            {section.children.map((item) => (
              <SidebarMenuItem key={item.url}>
                <SidebarMenuButton
                  asChild
                  isActive={pathname === item.url}
                  tooltip={item.title}
                >
                  <NavLink to={item.url}>
                    <item.icon />
                    <span>{item.title}</span>
                  </NavLink>
                </SidebarMenuButton>
              </SidebarMenuItem>
            ))}
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    )
  }

  return (
    <Collapsible open={open} onOpenChange={setOpen} className="group/collapsible">
      <SidebarGroup>
        <SidebarGroupContent>
          <SidebarMenu>
            <SidebarMenuItem>
              <CollapsibleTrigger asChild>
                <SidebarMenuButton
                  tooltip={section.title}
                  onClick={() => {
                    // 图标收缩模式下无法展开子菜单，点击标题跳转到该中心首页
                    if (state === 'collapsed') navigate(section.children[0].url)
                  }}
                >
                  <section.icon />
                  <span>{section.title}</span>
                  <ChevronRight className="ml-auto transition-transform duration-100 group-data-[state=open]/collapsible:rotate-90" />
                </SidebarMenuButton>
              </CollapsibleTrigger>
              <CollapsibleContent>
                <SidebarMenuSub>
                  {section.children.map((item) => (
                    <SidebarMenuSubItem key={item.url}>
                      <SidebarMenuSubButton
                        asChild
                        isActive={pathname === item.url}
                      >
                        <NavLink to={item.url}>
                          <span>{item.title}</span>
                        </NavLink>
                      </SidebarMenuSubButton>
                    </SidebarMenuSubItem>
                  ))}
                </SidebarMenuSub>
              </CollapsibleContent>
            </SidebarMenuItem>
          </SidebarMenu>
        </SidebarGroupContent>
      </SidebarGroup>
    </Collapsible>
  )
}

export function AppSidebar() {
  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <div className="flex h-8 items-center gap-2 px-2">
          <span className="flex size-5 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-bold text-primary-foreground">
            L
          </span>
          <span className="font-heading text-base font-semibold group-data-[collapsible=icon]:hidden">
            LifeOS 后台
          </span>
        </div>
      </SidebarHeader>
      <SidebarContent>
        {navigation.map((section) => (
          <SidebarSection key={section.title} section={section} />
        ))}
      </SidebarContent>
      <SidebarFooter>
        <NavUser />
      </SidebarFooter>
    </Sidebar>
  )
}
