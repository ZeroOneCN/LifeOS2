import type { Plugin, ProxyOptions } from 'vite'

/** 插件参数 */
interface DevBannerOptions {
  /** 横幅标题（项目名） */
  name: string
  /** 代理配置缺失时展示的后端地址兜底值 */
  apiTarget?: string
}

const BANNER_WIDTH = 58
/** 左侧标签固定宽度，保证地址列对齐 */
const LABEL_WIDTH = 10

/**
 * 判断终端是否支持 ANSI 颜色。
 *
 * 遵循 NO_COLOR 约定（存在该环境变量即关闭颜色，不论取值）；
 * 输出被重定向到文件或被 CI 捕获时 stdout 不是 TTY，同样降级为纯文本。
 *
 * @returns 允许输出 ANSI 转义序列时为 true
 */
function ansiSupported(): boolean {
  if (process.env.NO_COLOR !== undefined) return false
  return Boolean(process.stdout.isTTY)
}

/**
 * 按 ANSI 码着色。
 *
 * @param code ANSI 颜色/样式码，如 `36`
 * @param text 待着色文本
 * @param color 是否启用颜色
 * @returns 着色后的文本；未启用时原样返回
 */
function paint(code: string, text: string, color: boolean): string {
  return color ? `\u001b[${code}m${text}\u001b[0m` : text
}

/**
 * 高亮可点击地址：青色 + 下划线，便于在终端里识别为链接。
 *
 * @param url 完整地址
 * @param color 是否启用颜色
 * @returns 着色后的地址
 */
function highlightUrl(url: string, color: boolean): string {
  return paint('4;36', url, color)
}

/**
 * 渲染一行「标签 + 值」。
 *
 * @param label 左侧标签
 * @param value 右侧内容（可为已着色的文本）
 * @param color 是否启用颜色
 * @returns 对齐后的整行
 */
function row(label: string, value: string, color: boolean): string {
  return `${paint('90', `  ${label.padEnd(LABEL_WIDTH)}`, color)}${value}`
}

/**
 * 从 `/api` 代理配置中解析后端目标地址。
 *
 * @param proxy Vite 的 server.proxy 配置
 * @returns 代理目标地址；未配置或非字符串目标时返回 undefined
 */
function resolveApiTarget(proxy: Record<string, string | ProxyOptions> | undefined): string | undefined {
  const entry = proxy?.['/api']
  if (!entry) return undefined
  if (typeof entry === 'string') return entry
  const target = entry.target
  return typeof target === 'string' ? target : undefined
}

/**
 * 开发服务器启动横幅插件。
 *
 * 通过覆盖运行时 `server.printUrls()` 接管 Vite 默认的地址输出块，
 * 保留 Vite 自身的版本行、警告与错误输出（不吞异常），仅替换地址展示。
 *
 * @param options 横幅内容配置
 * @returns Vite 插件实例
 */
export function devBanner(options: DevBannerOptions): Plugin {
  return {
    name: 'lifeos:dev-banner',
    apply: 'serve',
    configureServer(server) {
      const color = ansiSupported()
      const dim = (text: string) => paint('90', text, color)
      const title = (text: string) => paint('1;36', text, color)

      server.printUrls = () => {
        const urls = server.resolvedUrls
        const local = urls?.local ?? []
        const network = urls?.network ?? []
        const https = Boolean(server.config.server.https)
        const apiTarget = resolveApiTarget(server.config.server.proxy) ?? options.apiTarget ?? '未配置'
        const demo = server.config.env.VITE_DEMO === '1'

        const lines: string[] = []
        lines.push(dim('='.repeat(BANNER_WIDTH)))
        lines.push(title(`  ${options.name}  ·  dev server`))
        lines.push(dim('-'.repeat(BANNER_WIDTH)))
        if (local.length === 0) {
          lines.push(row('Local', dim('（服务器尚未就绪）'), color))
        }
        for (const url of local) {
          lines.push(row('Local', highlightUrl(url, color), color))
        }
        for (const url of network) {
          lines.push(row('Network', highlightUrl(url, color), color))
        }
        lines.push(row('Protocol', https ? 'HTTPS（自签名开发证书）' : 'HTTP', color))
        lines.push(row('Backend', highlightUrl(apiTarget, color) + dim('  ← /api 代理'), color))
        lines.push(row('DEMO', demo ? paint('1;33', 'ENABLED（VITE_DEMO=1）', color) : dim('disabled'), color))
        lines.push(dim('='.repeat(BANNER_WIDTH)))

        // 走 Vite logger 输出，保持与 Vite 自身日志同一出口（便于日志重定向/CI 捕获）
        server.config.logger.info(lines.join('\n'))
      }
    },
  }
}
