import path from 'node:path'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

import { ensureDevCert } from './scripts/dev-cert.mjs'

export default defineConfig(async ({ command }) => {
  // 仅开发服务器需要 HTTPS；构建产物交给生产环境的 Nginx / HTTPS 网关
  const devCert = command === 'serve' ? await ensureDevCert() : null
  if (devCert?.regenerated) {
    console.log(
      `\n[dev-https] 已生成开发证书，覆盖主机：${devCert.hosts.join(', ')}` +
        `\n[dev-https] 证书路径：${devCert.certPath}` +
        `\n[dev-https] 首次访问如提示证书不受信任，可导入上述证书到「受信任的根证书颁发机构」\n`,
    )
  }

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: {
        '@': path.resolve(import.meta.dirname, './src'),
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
  }
})
