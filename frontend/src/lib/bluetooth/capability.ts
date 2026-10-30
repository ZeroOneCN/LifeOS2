/**
 * Web Bluetooth 通用能力探测与错误分类。
 * 体重秤等设备共用；仅依赖浏览器 API，不涉及任何厂商协议。
 */

/** Web Bluetooth 错误名称分层输出 */
export function classifyBluetoothError(err: unknown): { code: string; message: string } {
  const name = (err as { name?: string })?.name || ''
  const msg = (err as { message?: string })?.message || String(err)

  if (name === 'SecurityError' || name === 'NotAllowedError') {
    return {
      code: 'NOT_ALLOWED',
      message: '必须在 HTTPS 环境下，且由用户点击按钮触发连接（安全策略限制）',
    }
  }
  if (name === 'NotFoundError') {
    return { code: 'NOT_FOUND', message: '未找到匹配的蓝牙设备' }
  }
  if (name === 'NetworkError') {
    return { code: 'NETWORK', message: 'GATT 连接失败或设备主动断开' }
  }
  if (name === 'AbortError') {
    return { code: 'ABORTED', message: '操作被中断' }
  }
  return { code: 'UNKNOWN', message: msg || '未知蓝牙错误' }
}

/** Web Bluetooth 能力探测结果 */
export interface BluetoothCapability {
  /** 是否完全可用（安全上下文 + 浏览器支持） */
  available: boolean
  /** 浏览器本身是否支持 Web Bluetooth API */
  browserSupported: boolean
  /** 当前页面是否处于安全上下文 */
  isSecureContext: boolean
  /** 不可用时的原因描述 */
  reason: string | null
  /** 建议的解决方案 */
  suggestion: string | null
}

/** 细粒度的 Web Bluetooth 能力探测 */
export function detectBluetoothCapability(): BluetoothCapability {
  if (typeof navigator === 'undefined') {
    return {
      available: false,
      browserSupported: false,
      isSecureContext: false,
      reason: '非浏览器环境',
      suggestion: '请在浏览器中打开此页面',
    }
  }

  const isSecure = window.isSecureContext === true
  const hasApi = 'bluetooth' in navigator

  if (!hasApi) {
    return {
      available: false,
      browserSupported: false,
      isSecureContext: isSecure,
      reason: '当前浏览器不支持 Web Bluetooth API',
      suggestion: '请使用 Chrome 或 Edge 浏览器',
    }
  }

  if (!isSecure) {
    const host = window.location.hostname
    return {
      available: false,
      browserSupported: true,
      isSecureContext: false,
      reason: '当前页面不是安全上下文（需要 HTTPS 或 localhost）',
      suggestion: [
        '方案 A：改用 localhost 访问（推荐）',
        `  http://localhost:${window.location.port}`,
        '',
        '方案 B：Chrome 强制允许不安全来源',
        '  打开 chrome://flags/#unsafely-treat-insecure-origin-as-secure',
        `  添加 http://${host}:${window.location.port}`,
        '',
        '方案 C：配 HTTPS（生产部署）',
      ].join('\n'),
    }
  }

  return {
    available: true,
    browserSupported: true,
    isSecureContext: true,
    reason: null,
    suggestion: null,
  }
}

/** 检查浏览器是否支持 Web Bluetooth（简单版，兼容旧调用） */
export function isWebBluetoothSupported(): boolean {
  return detectBluetoothCapability().available
}
