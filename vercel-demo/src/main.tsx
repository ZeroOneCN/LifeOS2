import { createRoot } from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
import { ThemeProvider } from 'next-themes'

import { installDemoFetch } from '@/demo/mock-api'
import { Toaster } from '@/components/ui/sonner'
import { TooltipProvider } from '@/components/ui/tooltip'
import { AuthProvider } from '@/lib/auth'
import { SiteConfigProvider } from '@/lib/site-config'
import { router } from '@/router'
import './index.css'

installDemoFetch()

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
