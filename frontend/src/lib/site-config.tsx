import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { api } from '@/lib/api'

/** 系统品牌配置（后端 /site-config 归一化后的最终值） */
export type SiteConfig = {
  site_title: string
  logo: string | null
  login_title: string
  login_subtitle: string
  register_title: string
  register_subtitle: string
}

/** 内置兜底默认值：仅在首次请求失败/离线且无本地快照时使用，需与后端默认值保持一致 */
export const DEFAULT_SITE_CONFIG: SiteConfig = {
  site_title: '数字化生活助手',
  logo: null,
  login_title: '登录 数字化生活助手',
  login_subtitle: '使用你的账号登录以继续',
  register_title: '注册 数字化生活助手',
  register_subtitle: '创建账号以使用数字化生活助手',
}

/** 默认 LOGO 资源（与 index.html 中引用的图标一致） */
export const DEFAULT_LOGO = '/favicon.svg'

/** 本地快照键：首屏直接用快照渲染，避免自定义 LOGO 出现前先闪一下默认值 */
const CACHE_KEY = 'lifeos_site_config'

/** 取 LOGO 实际展示地址，未配置时回落默认资源。 */
export function resolveLogo(logo: string | null | undefined): string {
  return logo || DEFAULT_LOGO
}

/** 读取本地缓存快照并补全缺失字段。 */
function readCache(): SiteConfig {
  try {
    const raw = localStorage.getItem(CACHE_KEY)
    if (!raw) return DEFAULT_SITE_CONFIG
    return { ...DEFAULT_SITE_CONFIG, ...(JSON.parse(raw) as Partial<SiteConfig>) }
  } catch {
    return DEFAULT_SITE_CONFIG
  }
}

/** 同步网页标签图标（favicon），配置变更后无需刷新页面即可生效。 */
function applyFavicon(logo: string | null) {
  if (typeof document === 'undefined') return
  const href = resolveLogo(logo)
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]')
  if (!link) {
    link = document.createElement('link')
    link.rel = 'icon'
    document.head.appendChild(link)
  }
  link.href = href
  const mime = href.startsWith('data:') ? href.slice(5, href.indexOf(';')) : ''
  link.type = mime || 'image/svg+xml'
}

type SiteConfigContextValue = {
  /** 当前生效的品牌配置 */
  config: SiteConfig
  /** 重新拉取后端配置（保存成功后调用即可全站即时生效） */
  reload: () => Promise<void>
}

const SiteConfigContext = createContext<SiteConfigContextValue | null>(null)

export function SiteConfigProvider({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = useState<SiteConfig>(readCache)

  const reload = useCallback(async () => {
    try {
      const data = await api.query<SiteConfig>('/site-config')
      setConfig(data)
      localStorage.setItem(CACHE_KEY, JSON.stringify(data))
    } catch {
      // 拉取失败时保留本地快照/默认值，不影响页面正常使用
    }
  }, [])

  useEffect(() => {
    reload()
  }, [reload])

  useEffect(() => {
    applyFavicon(config.logo)
  }, [config.logo])

  const value = useMemo(() => ({ config, reload }), [config, reload])

  return (
    <SiteConfigContext.Provider value={value}>{children}</SiteConfigContext.Provider>
  )
}

export function useSiteConfig() {
  const ctx = useContext(SiteConfigContext)
  if (!ctx) throw new Error('useSiteConfig 必须在 SiteConfigProvider 内使用')
  return ctx
}