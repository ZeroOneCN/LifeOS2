/**
 * 蚂蚁阿福体重秤（AFU-WL-TZ-A1）BLE 协议解析。
 *
 * 移植自 backend/app/services/scale/reader.py
 * 私有服务 FFb0（FFB1 写入 / FFB2 通知），无需配对与认证。
 *
 * 帧格式（20 字节，包头 0xAC，包类型在 data[18]）：
 *   体重包(0xD5)  ac 29 <稳定位|00> | <32 位体重编码> | 02 00 | 05 40 | … | 29 d5 | 序号
 *   阻抗包(0xD6)  ac 29 02 | <通道数> | <2 字节×通道数> | <mode> | <32 位体重编码> | … | 29 d6 | 序号
 *   资料应答(0xD8) ac 29 01 | … | … | 29 d8 | 序号
 *
 * 体重编码为 32 位大端，低 18 位是克数，bit31 是稳定标志，bit18-20 是刻度精度。
 */

// 体重秤私有服务 UUID
export const FFB0_SERVICE = '0000ffb0-0000-1000-8000-00805f9b34fb'
export const FFB1_WRITE = '0000ffb1-0000-1000-8000-00805f9b34fb'
export const FFB2_NOTIFY = '0000ffb2-0000-1000-8000-00805f9b34fb'

// 包类型
const TYPE_WEIGHT = 0xd5
const TYPE_IMPEDANCE = 0xd6

// 合理克数范围
const MIN_GRAMS = -800
const MAX_GRAMS = 250000

/** 体重秤测量结果 */
export interface ScaleMeasurement {
  type: 'weight' | 'impedance' | 'ack'
  /** 体重 kg */
  kg: number
  /** 是否稳定 */
  stable: boolean
  /** 克数 */
  grams: number
  /** 阻抗通道值（仅阻抗包） */
  impedances?: number[]
  /** 阻抗 mode（仅阻抗包） */
  mode?: number
}

/** 复刻 Python _get_int_round 取整修正 */
function getIntRound(value: number): number {
  return Math.floor(value + 1.0)
}

/** 按刻度精度把公斤值换算成秤的显示值 */
function gunit(valueKg: number, division: number): number {
  switch (division) {
    case 0:
      return ((getIntRound(valueKg * 1000) + 5) / 10) / 100
    case 1: {
      let raw = getIntRound(valueKg * 1000)
      if (raw % 10 === 9) raw += 10
      const scaled = raw / 10
      if (scaled % 2) raw += 10
      return (scaled % 2 ? scaled + 1 : scaled) / 100
    }
    case 2: {
      const raw = (getIntRound(valueKg * 1000) + 20) / 10
      const scaled = raw % 10 >= 5 ? Math.floor(raw / 10) * 10 + 5 : Math.floor(raw / 10) * 10
      return scaled / 100
    }
    case 3:
      return ((getIntRound(valueKg * 100) + 5) / 10) / 10
    case 4: {
      let raw = getIntRound(valueKg * 100)
      if (raw % 10 === 9) raw += 10
      const scaled = raw / 10
      if (scaled % 2) raw += 10
      return (scaled % 2 ? scaled + 1 : scaled) / 10
    }
    default:
      return Math.round(valueKg * 100) / 100
  }
}

/** 从 32 位体重编码解出体重、稳定标志与克数 */
export function decodeWeight(encoded: number): { kg: number; stable: boolean; grams: number } {
  const grams = encoded & 0x3ffff
  const division = (encoded & 0x1c0000) >> 18
  return {
    kg: gunit(grams / 1000, division),
    stable: Boolean(encoded & (1 << 31)),
    grams,
  }
}

/** 大端 16 位整数 */
function be16(data: DataView, offset: number): number {
  return data.getUint16(offset, false)
}

/** 大端 32 位整数 */
function be32(data: DataView, offset: number): number {
  return data.getUint32(offset, false)
}

/** 解析一帧 FFB2 通知 */
export function parseFrame(raw: DataView): ScaleMeasurement | null {
  if (raw.byteLength < 20 || raw.getUint8(0) !== 0xac) return null

  const packetType = raw.getUint8(18)

  if (packetType === TYPE_WEIGHT) {
    const { kg, stable, grams } = decodeWeight(be32(raw, 2))
    return { type: 'weight', kg, stable, grams }
  }

  if (packetType === TYPE_IMPEDANCE) {
    const count = raw.getUint8(2)
    if (count <= 0 || 5 + count * 2 + 4 > raw.byteLength) return null
    const impedances: number[] = []
    for (let i = 0; i < count; i++) {
      impedances.push(be16(raw, 4 + i * 2))
    }
    const mode = raw.getUint8(4 + count * 2)
    const { kg, stable, grams } = decodeWeight(be32(raw, 5 + count * 2))
    return { type: 'impedance', kg, stable, grams, impedances, mode }
  }

  return null
}

/** 构造「设置时间 + 用户资料」包（0xD0），使能阻抗测量 */
export function buildUserInfoPacket(
  deviceType: number,
  profile: { heightCm: number; age: number; isMale: boolean },
): Uint8Array {
  const packet: number[] = []
  packet.push(0xac, deviceType & 0xff)

  const now = Math.floor(Date.now() / 1000)
  packet.push((now >> 24) & 0xff, (now >> 16) & 0xff, (now >> 8) & 0xff, now & 0xff)

  // 时区，以 15 分钟为单位
  const tzOffset = -new Date().getTimezoneOffset()
  packet.push(Math.round(tzOffset / 15) & 0xff)

  packet.push(0) // 单位 0 = kg
  packet.push(1) // 用户编号
  packet.push(profile.heightCm & 0xff)
  packet.push(0, 0) // 档案体重
  packet.push(profile.age & 0xff)
  packet.push(profile.isMale ? 1 : 2)
  packet.push(0, 0) // 目标体重
  packet.push(0x03) // 功能位：bit0 使能阻抗测量
  packet.push(0)
  packet.push(0xd0) // 包类型

  // 校验和
  let sum = 0
  for (let i = 2; i <= 18; i++) sum += packet[i]
  packet.push(sum & 0xff)

  return new Uint8Array(packet)
}

/** 验证克数范围 */
export function isValidGrams(grams: number): boolean {
  return grams >= MIN_GRAMS && grams <= MAX_GRAMS
}
