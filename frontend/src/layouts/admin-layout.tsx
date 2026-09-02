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

const breadcrumbMap: Record<string, { parent: string; title: string }> = {
  '/dashboard': { parent: '', title: '工作台' },
  '/system/users': { parent: '系统管理', title: '用户管理' },
  '/system/roles': { parent: '系统管理', title: '角色管理' },
  '/settings': { parent: '', title: '系统设置' },
}

export function AdminLayout() {
  const { pathname } = useLocation()
  const crumb = breadcrumbMap[pathname] ?? { parent: '', title: '页面' }

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
              {crumb.parent && (
                <>
                  <BreadcrumbItem className="hidden sm:block">
                    <BreadcrumbPage>{crumb.parent}</BreadcrumbPage>
                  </BreadcrumbItem>
                  <BreadcrumbSeparator className="hidden sm:block" />
                </>
              )}
              <BreadcrumbItem>
                <BreadcrumbPage>{crumb.title}</BreadcrumbPage>
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
