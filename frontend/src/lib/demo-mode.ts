/**
 * 演示模式开关。
 *
 * 构建时注入 `VITE_DEMO=1` 即为在线演示版：启动阶段安装内置 mock 请求拦截，
 * 登录页预填演示账号，并隐藏依赖后端自动化任务的入口。
 */
export const IS_DEMO = import.meta.env.VITE_DEMO === '1'
