import { ChevronRight } from 'lucide-react'
import { NavLink, useLocation } from 'react-router-dom'

import { NavUser } from '@/components/nav-user'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
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
} from '@/components/ui/sidebar'
import { navigation, type NavSection } from '@/config/navigation'

function SectionLinks({ section }: { section: NavSection }) {
  const { pathname } = useLocation()

  return (
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
  )
}

function SectionCollapsible({ section }: { section: NavSection }) {
  const { pathname } = useLocation()

  return (
    <SidebarMenu>
      <Collapsible
        asChild
        defaultOpen
        className="group/collapsible"
      >
        <SidebarMenuItem>
          <CollapsibleTrigger asChild>
            <SidebarMenuButton tooltip={section.title}>
              <section.icon />
              <span>{section.title}</span>
              <ChevronRight className="ml-auto transition-transform duration-200 group-data-[state=open]/collapsible:rotate-90" />
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
      </Collapsible>
    </SidebarMenu>
  )
}

function SidebarSection({ section }: { section: NavSection }) {
  return (
    <SidebarGroup>
      <SidebarGroupLabel>{section.title}</SidebarGroupLabel>
      <SidebarGroupContent>
        {section.collapsible ? (
          <SectionCollapsible section={section} />
        ) : (
          <SectionLinks section={section} />
        )}
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
