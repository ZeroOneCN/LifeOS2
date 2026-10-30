/**
 * Web Bluetooth React Hook：体重秤连接与数据采集。
 *
 * 关键设计（经验教训）：
 *  1. requestDevice() 必须严格在按钮点击等用户手势中触发，自动重连只能用 getDevices()
 *  2. 连接状态拆为 gattConnected（GATT 层）和 dataReady（数据通道就绪）两个独立状态
 *  3. 订阅通知采用白名单策略，只订阅目标特征，避免全量扫描导致设备断连
 */

import { useCallback, useEffect, useRef, useState } from 'react'
import { FFB0_SERVICE, FFB1_WRITE, FFB2_NOTIFY, parseFrame, buildUserInfoPacket, isValidGrams, type ScaleMeasurement } from '@/lib/bluetooth/scale-protocol'
import { calculateBodyComposition } from '@/lib/bluetooth/body-composition'
import { classifyBluetoothError, detectBluetoothCapability, type BluetoothCapability } from '@/lib/bluetooth/capability'
import { api } from '@/lib/api'

/** 体重秤用户资料 */
export interface ScaleProfile {
  heightCm: number
  age: number
  isMale: boolean
}

/** 采集到的完整测量结果（含体成分） */
export interface CompleteMeasurement {
  weightKg: number
  impedanceOhm?: number
  bodyComposition: ReturnType<typeof calculateBodyComposition> | null
  measuredAt: Date
}

/** Hook 返回的状态 */
export interface UseScaleBluetooth {
  capability: BluetoothCapability
  supported: boolean
  /** GATT 层已连接 */
  gattConnected: boolean
  /** 数据通道已就绪（通知订阅成功） */
  dataReady: boolean
  /** 是否正在连接 */
  connecting: boolean
  /** 最新测量结果 */
  measurement: CompleteMeasurement | null
  /** 最近一次错误信息 */
  error: string | null
  /** 等待数据时的温和提示（非错误，例如尚未上秤） */
  hint: string | null
  /** 最近一次同步到后端的结果 */
  lastSynced: { weightKg: number; at: Date } | null
  /** 连接体重秤（必须在用户点击中调用） */
  connect: (profile: ScaleProfile) => Promise<void>
  /** 断开连接 */
  disconnect: () => void
  /** 把当前测量同步到后端 */
  syncToBackend: () => Promise<boolean>
}

/**
 * 体重秤 Web Bluetooth Hook。
 * 封装设备选择 → GATT 连接 → 发送资料包 → 订阅通知 → 解析数据 → 同步后端的完整流程。
 */
export function useScaleBluetooth(): UseScaleBluetooth {
  const capability = detectBluetoothCapability()
  const supported = capability.available
  const [gattConnected, setGattConnected] = useState(false)
  const [dataReady, setDataReady] = useState(false)
  const [connecting, setConnecting] = useState(false)
  const [measurement, setMeasurement] = useState<CompleteMeasurement | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [hint, setHint] = useState<string | null>(null)
  const [lastSynced, setLastSynced] = useState<{ weightKg: number; at: Date } | null>(null)

  const deviceRef = useRef<BluetoothDevice | null>(null)
  const serverRef = useRef<BluetoothRemoteGATTServer | null>(null)
  const notifyRef = useRef<BluetoothRemoteGATTCharacteristic | null>(null)
  const profileRef = useRef<ScaleProfile>({ heightCm: 170, age: 25, isMale: true })
  const stableTimerRef = useRef<number | null>(null)
  const pendingStableRef = useRef<ScaleMeasurement | null>(null)
  const deviceTypeRef = useRef(0x29)
  const profileResendRef = useRef<number | null>(null)
  const receivedRef = useRef(false)
  const waitTimerRef = useRef<number | null>(null)

  /** 清理所有资源 */
  const cleanup = useCallback(() => {
    if (stableTimerRef.current !== null) {
      window.clearTimeout(stableTimerRef.current)
      stableTimerRef.current = null
    }
    if (profileResendRef.current !== null) {
      window.clearInterval(profileResendRef.current)
      profileResendRef.current = null
    }
    if (waitTimerRef.current !== null) {
      window.clearTimeout(waitTimerRef.current)
      waitTimerRef.current = null
    }
    setHint(null)
    notifyRef.current = null
    serverRef.current = null
    deviceRef.current = null
    setDataReady(false)
    setGattConnected(false)
  }, [])

  /** 发送用户资料包（使能阻抗测量） */
  const sendProfile = useCallback(async () => {
    const server = serverRef.current
    if (!server || !server.connected) return
    try {
      const service = await server.getPrimaryService(FFB0_SERVICE)
      const writeChar = await service.getCharacteristic(FFB1_WRITE)
      const packet = buildUserInfoPacket(deviceTypeRef.current, profileRef.current)
      await writeChar.writeValue(packet.buffer as ArrayBuffer)
    } catch {
      /* 发送失败不致命，秤可能只称体重 */
    }
  }, [])

  /** 处理一条稳定的体重/阻抗数据 */
  const handleStableMeasurement = useCallback(
    (meas: ScaleMeasurement) => {
      if (meas.type !== 'weight' && meas.type !== 'impedance') return
      if (!meas.stable) return
      if (!isValidGrams(meas.grams)) return

      // 体重先到，阻抗可能晚 1-3 秒，延迟合并
      if (stableTimerRef.current !== null) {
        window.clearTimeout(stableTimerRef.current)
      }
      pendingStableRef.current = meas
      stableTimerRef.current = window.setTimeout(() => {
        stableTimerRef.current = null
        const final = pendingStableRef.current
        pendingStableRef.current = null
        if (!final) return

        const weightKg = Math.round(final.kg * 100) / 100
        let impedanceOhm: number | undefined
        let bodyComp = null

        if (final.type === 'impedance' && final.impedances && final.impedances[0] > 0) {
          impedanceOhm = Math.round(final.impedances[0] * 10) / 10
          bodyComp = calculateBodyComposition(
            weightKg,
            impedanceOhm,
            profileRef.current.heightCm,
            profileRef.current.age,
            profileRef.current.isMale,
          )
        }

        setMeasurement({
          weightKg,
          impedanceOhm,
          bodyComposition: bodyComp,
          measuredAt: new Date(),
        })
        receivedRef.current = true
        setHint(null)
        setError(null)
      }, 3000) // 等待阻抗包
    },
    [],
  )

  /** 主连接流程 */
  const connect = useCallback(
    async (profile: ScaleProfile) => {
      if (!supported) {
        setError('当前浏览器不支持 Web Bluetooth，请使用 Chrome 或 Edge')
        return
      }
      profileRef.current = profile
      receivedRef.current = false
      setHint(null)
      setError(null)
      setConnecting(true)

      try {
        // ① requestDevice 必须在用户手势中触发（按钮点击）
        const device = await navigator.bluetooth.requestDevice({
          filters: [{ services: [FFB0_SERVICE] }, { namePrefix: 'AFU' }],
          optionalServices: [FFB0_SERVICE],
        })
        deviceRef.current = device

        // ② 连接 GATT
        const server = await device.gatt!.connect()
        serverRef.current = server
        setGattConnected(true)

        device.addEventListener('gattserverdisconnected', () => {
          cleanup()
          setError('蓝牙设备已断开')
        })

        // ③ 发现服务与特征（白名单，只订阅 FFB2）
        const service = await server.getPrimaryService(FFB0_SERVICE)
        const notifyChar = await service.getCharacteristic(FFB2_NOTIFY)
        notifyRef.current = notifyChar

        // ④ 开始订阅通知（核心数据通道）
        await notifyChar.startNotifications()
        notifyChar.addEventListener('characteristicvaluechanged', (ev) => {
          const target = ev.target as BluetoothRemoteGATTCharacteristic
          const value = target.value
          if (!value) return
          deviceTypeRef.current = value.getUint8(1)
          const parsed = parseFrame(value)
          if (parsed && parsed.type !== 'ack') {
            handleStableMeasurement(parsed)
          }
        })

        setDataReady(true)

        // ⑤ 发送用户资料包（使能阻抗测量），每 15 秒重发确保秤不丢失
        await sendProfile()
        profileResendRef.current = window.setInterval(() => {
          if (serverRef.current?.connected) sendProfile()
        }, 15000)

        // 连接成功后立即返回，数据由通知异步推送。
        // 30 秒内没有任何数据时给出提示（不断开连接）：多数秤在连接后会先休眠，上秤唤醒才开始推数。
        waitTimerRef.current = window.setTimeout(() => {
          waitTimerRef.current = null
          if (!receivedRef.current && serverRef.current?.connected) {
            setHint(
              '还没有收到称重数据。请站上秤并保持双脚覆盖电极 5~8 秒；' +
                '若刚连上时秤处于休眠，上秤唤醒后才会开始推送。' +
                '若反复如此，请确认后端采集器（ENABLE_SCALE_COLLECTOR）已改为 false 且后端已重启。',
            )
          }
        }, 30000)
      } catch (err) {
        const { code, message } = classifyBluetoothError(err)
        setError(message)
        cleanup()
        throw { code, message }
      } finally {
        setConnecting(false)
      }
    },
    [supported, cleanup, sendProfile, handleStableMeasurement],
  )

  const disconnect = useCallback(() => {
    if (serverRef.current?.connected) {
      try {
        serverRef.current.disconnect()
      } catch {
        /* ignore */
      }
    }
    cleanup()
  }, [cleanup])

  /** 把测量结果同步到后端 */
  const syncToBackend = useCallback(async (): Promise<boolean> => {
    if (!measurement) {
      setError('还没有测量数据')
      return false
    }
    try {
      await api.create('/health/body/blesync', {
        weight_kg: measurement.weightKg,
        height_cm: profileRef.current.heightCm,
        gender: profileRef.current.isMale ? 'male' : 'female',
        impedance_ohm: measurement.impedanceOhm ?? null,
        body_composition: measurement.bodyComposition,
        measured_at: measurement.measuredAt.toISOString(),
      })
      setLastSynced({ weightKg: measurement.weightKg, at: new Date() })
      setError(null)
      return true
    } catch (err) {
      setError(err instanceof Error ? err.message : '同步失败')
      return false
    }
  }, [measurement])

  useEffect(() => {
    return () => {
      cleanup()
    }
  }, [cleanup])

  return {
    capability,
    supported,
    gattConnected,
    dataReady,
    connecting,
    measurement,
    error,
    hint,
    lastSynced,
    connect,
    disconnect,
    syncToBackend,
  }
}
