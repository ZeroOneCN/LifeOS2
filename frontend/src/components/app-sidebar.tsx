import { NavLink, useLocation } from 'react-router-dom'

import { NavUser } from '@/components/nav-user'
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
} from '@/components/ui/sidebar'
import { navigation, type NavSection } from '@/config/navigation'

function SidebarSection({ section }: { section: NavSection }) {
  const { pathname } = useLocation()

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
