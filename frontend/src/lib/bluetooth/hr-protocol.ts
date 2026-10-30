/**
 * Web Bluetooth 工具集合：心率广播解析 + 通用连接 Hook。
 *
 * 小米手环通过厂商广播包（Company ID 0x0157）传递心率，
 * 也兼容标准心率服务（0x180D）的 service data。
 */

/** 标准心率服务 UUID */
export const HR_SERVICE_UUID = '0000180d-0000-1000-8000-00805f9b34fb'
export const HR_MEASUREMENT_CHAR = '00002a37-0000-1000-8000-00805f9b34fb'

/** 小米厂商 Company ID */
const XIAOMI_COMPANY_ID = 0x0157

/** 心率有效区间（bpm） */
export const HR_MIN_VALID = 20
export const HR_MAX_VALID = 250

/** 广播数据中解析心率所需的最小字段集合（BluetoothAdvertisingEvent 可直接传入） */
export interface AdvertPayload {
  manufacturerData?: BluetoothManufacturerData
  serviceData?: BluetoothServiceData
}

/** 解析 BLE 广播中的心率 */
export function decodeHeartRate(
  adv: AdvertPayload,
  offset = 3,
): { bpm: number | null; source: string | null } {
  // 优先读取小米厂商数据
  const manufacturer = adv.manufacturerData
  if (manufacturer) {
    const xiaomiData = manufacturer.get(XIAOMI_COMPANY_ID)
    if (xiaomiData && xiaomiData.byteLength > offset) {
      const bpm = xiaomiData.getUint8(offset)
      if (bpm >= HR_MIN_VALID && bpm <= HR_MAX_VALID) {
        return { bpm, source: 'xiaomi' }
      }
      return { bpm: null, source: 'xiaomi' }
    }
  }

  // 其次兼容标准心率服务
  const serviceData = adv.serviceData
  if (serviceData) {
    for (const [uuid, raw] of serviceData.entries()) {
      if (String(uuid).toLowerCase() !== HR_SERVICE_UUID || !raw) continue
      const flags = raw.getUint8(0)
      let bpm: number
      if (flags & 0x01 && raw.byteLength >= 3) {
        bpm = raw.getUint16(1, true) // 小端 16 位
      } else if (raw.byteLength >= 2) {
        bpm = raw.getUint8(1)
      } else {
        continue
      }
      if (bpm >= HR_MIN_VALID && bpm <= HR_MAX_VALID) {
        return { bpm, source: 'standard' }
      }
    }
  }

  return { bpm: null, source: null }
}

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
