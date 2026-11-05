import { useEffect } from 'react'
import { Outlet, useLocation } from 'react-router-dom'

import { AppSidebar } from '@/components/app-sidebar'
import { ThemeToggle } from '@/components/theme-toggle'
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from '@/components/ui/breadcrumb'
import { Separator } from '@/components/ui/separator'
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from '@/components/ui/sidebar'
import { findRoute, findSection } from '@/config/routes'
import { useSiteConfig } from '@/lib/site-config'

export function AdminLayout() {
  const { pathname } = useLocation()
  const { config } = useSiteConfig()
  const route = findRoute(pathname)
  const section = findSection(route?.section)
  const sectionTitle = section?.title
  const showSection = section ? !section.system : false
  const pageTitle = route?.title ?? '404 / 页面不存在'

  // 按当前页面自动更新网页标签标题（品牌名取自系统设置）
  useEffect(() => {
    document.title = `${config.site_title}-${pageTitle}`
  }, [config.site_title, pageTitle])

  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <header className="flex h-14 shrink-0 items-center gap-2 border-b px-4">
          <SidebarTrigger className="-ml-1" />
          <Separator
            orientation="vertical"
            className="mr-2 data-[orientation=vertical]:h-4"
          />
          <Breadcrumb>
            <BreadcrumbList>
              {showSection && sectionTitle && (
                <>
                  <BreadcrumbItem className="hidden sm:block">
                    <BreadcrumbPage>{sectionTitle}</BreadcrumbPage>
                  </BreadcrumbItem>
                  <BreadcrumbSeparator className="hidden sm:block" />
                </>
              )}
              <BreadcrumbItem>
                <BreadcrumbPage>{pageTitle}</BreadcrumbPage>
              </BreadcrumbItem>
            </BreadcrumbList>
          </Breadcrumb>
          <div className="ml-auto">
            <ThemeToggle />
          </div>
        </header>
        <div key={pathname} className="page-enter flex flex-1 flex-col gap-4 p-4">
          <Outlet />
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
