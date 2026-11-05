import path from 'node:path'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

import { devBanner } from './plugins/dev-banner.ts'
import { ensureDevCert } from './scripts/dev-cert.mjs'

// 仅开发服务器（vite / vite serve）需要 HTTPS；构建产物交给生产环境的 HTTPS 网关
const isServe = !process.argv.includes('build')
const devCert = isServe ? await ensureDevCert() : null

if (devCert?.regenerated) {
  console.log(
    `\n[dev-https] 已生成开发证书，覆盖主机：${devCert.hosts.join(', ')}` +
      `\n[dev-https] 证书路径：${devCert.certPath}` +
      `\n[dev-https] 首次访问如提示证书不受信任，可执行 npm run cert:trust 导入受信任根证书\n`,
  )
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss(), devBanner({ name: 'LifeOS Web' })],
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, './src'),
    },
  },
  build: {
    rollupOptions: {
      output: {
        /**
         * 图表库 chunk 语义化命名：rolldown 默认按 chunk 内某个共享模块名命名，
         * 会把 recharts 所在的公共 chunk 叫作 chart-theme（误导性名字）。
         * 这里按"是否包含 recharts"识别该 chunk，统一命名为 recharts-vendor。
         */
        chunkFileNames(chunkInfo: { name: string; moduleIds: string[] }) {
          const rechartsModules = chunkInfo.moduleIds.filter((m) =>
            m.includes('node_modules/recharts/'),
          ).length
          // 仅重命名 recharts 主库 chunk；零散引用 recharts 的小 chunk 保持原名
          if (rechartsModules >= 100) {
            return 'assets/recharts-vendor-[hash].js'
          }
          return 'assets/[name]-[hash].js'
        },
        /**
         * 显式切分第三方依赖，产出稳定命名的独立 chunk：
         * 版本不变时文件名不变，发布新版本不会让用户整体缓存失效。
         *
         * 注意：recharts 没有放进 manualChunks。Vite 8（rolldown）会把 manualChunk 依赖
         * 一并并入该 chunk，recharts 依赖的 clsx 同时被业务代码（cn）引用，
         * 结果整个图表库 chunk 被入口静态预加载（首屏 +430 kB）。因此图表库靠懒加载边界隔离，
         * 其 chunk 只由图表页面的动态 import 触发。
         */
        manualChunks(id: string) {
          if (!id.includes('node_modules')) return undefined
          const p = id.replace(/\\/g, '/')
          // React 全家桶与路由：所有页面都依赖，拆成稳定命名的独立 chunk 便于长期缓存
          if (
            /node_modules\/(react|react-dom|react-router|react-router-dom|scheduler|@remix-run\/router|use-sync-external-store)\//.test(
              p,
            )
          ) {
            return 'vendor-react'
          }
          // 与业务代码同用的基础工具库（cn 的实现依赖），保持独立以免被并入其他大 chunk
          if (/node_modules\/(clsx|tailwind-merge|class-variance-authority)\//.test(p)) {
            return 'vendor-utils'
          }
          return undefined
        },
      },
    },
  },
  server: {
    // 监听所有网卡，支持局域网设备访问（https://<局域网IP>:9015）
    host: '0.0.0.0',
    port: 9015,
    // Web Bluetooth 要求安全上下文：局域网 IP 也必须走 HTTPS
    https: devCert ? { key: devCert.key, cert: devCert.cert } : undefined,
    // 允许任意 Host 访问（开发模式），避免局域网 IP 访问被 Vite 拦截
    allowedHosts: true,
    // 启动时预编译全部页面/组件，避免切换路由时首次按需编译导致的长时间卡顿
    warmup: {
      clientFiles: ['./src/pages/**/*.{ts,tsx}', './src/components/**/*.{ts,tsx}', './src/layouts/**/*.{ts,tsx}', './src/lib/**/*.{ts,tsx}'],
    },
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:9515',
        changeOrigin: true,
      },
    },
  },
})
