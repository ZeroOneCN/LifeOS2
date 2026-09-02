import { Outlet, useLocation } from 'react-router-dom'

import { AppSidebar } from '@/components/app-sidebar'
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
import { findNavEntry } from '@/config/navigation'

// 底部用户入口等不在侧边栏导航中的页面标题
const PAGE_TITLES: Record<string, string> = {
  '/user-center': '用户中心',
  '/user-center/settings': '账号设置',
}

export function AdminLayout() {
  const { pathname } = useLocation()
  const found = findNavEntry(pathname)
  const sectionTitle = found?.section.title
  const showSection = found ? !found.section.system : false
  const pageTitle = found?.entry.title ?? PAGE_TITLES[pathname] ?? '页面'

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
        </header>
        <div className="flex flex-1 flex-col gap-4 p-4">
          <Outlet />
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
