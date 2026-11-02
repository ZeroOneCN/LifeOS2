import { createRoot } from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
import { ThemeProvider } from 'next-themes'

import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AuthProvider } from '@/lib/auth'
import { SiteConfigProvider } from '@/lib/site-config'
import { router } from '@/router'
import './index.css'

/**
 * 挂载应用。
 * 演示构建（VITE_DEMO=1）先安装 mock 请求拦截再渲染，确保首屏接口即命中快照。
 */
async function bootstrap() {
  if (import.meta.env.VITE_DEMO === '1') {
    const { installDemoFetch } = await import('./demo/mock-api')
    installDemoFetch()
  }

  createRoot(document.getElementById('root')!).render(
    <TooltipProvider>
      <ThemeProvider
        attribute="class"
        defaultTheme="system"
        enableSystem
        disableTransitionOnChange
      >
        <SiteConfigProvider>
          <AuthProvider>
            <RouterProvider router={router} />
            <Toaster />
          </AuthProvider>
        </SiteConfigProvider>
      </ThemeProvider>
    </TooltipProvider>,
  )
}

void bootstrap()
