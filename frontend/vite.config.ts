import path from 'path'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, './src'),
    },
  },
  server: {
    // 监听所有网卡，支持局域网设备访问（http://<局域网IP>:5173）
    host: '0.0.0.0',
    // 允许任意 Host 访问（开发模式），避免局域网 IP 访问被 Vite 拦截
    allowedHosts: true,
    // 启动时预编译全部页面/组件，避免切换路由时首次按需编译导致的长时间卡顿
    warmup: {
      clientFiles: ['./src/pages/**/*.{ts,tsx}', './src/components/**/*.{ts,tsx}', './src/layouts/**/*.{ts,tsx}', './src/lib/**/*.{ts,tsx}'],
    },
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
})
