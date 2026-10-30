/**
 * Web Bluetooth React Hook：体重秤 + 手环心率的统一管理。
 *
 * 关键设计（经验教训）：
 *  1. requestDevice() 必须严格在按钮点击等用户手势中触发，自动重连只能用 getDevices()
 *  2. 连接状态拆为 gattConnected（GATT 层）和 dataReady（数据通道就绪）两个独立状态
 *  3. 订阅通知采用白名单策略，只订阅目标特征，避免全量扫描导致设备断连
 */

import { useCallback, useEffect, useRef, useState } from 'react'
import { FFB0_SERVICE, FFB1_WRITE, FFB2_NOTIFY, parseFrame, buildUserInfoPacket, isValidGrams, type ScaleMeasurement } from '@/lib/bluetooth/scale-protocol'
import { calculateBodyComposition } from '@/lib/bluetooth/body-composition'
import { decodeHeartRate, classifyBluetoothError, detectBluetoothCapability, HR_SERVICE_UUID, type BluetoothCapability } from '@/lib/bluetooth/hr-protocol'
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
        // 25 秒内没有任何数据时给出可操作提示，但不主动断开连接（用户可能还没上秤）。
        waitTimerRef.current = window.setTimeout(() => {
          waitTimerRef.current = null
          if (!receivedRef.current && serverRef.current?.connected) {
            setError(
              '已连接但 25 秒内未收到称重数据：请站上秤并保持 3~5 秒。' +
                '若后端采集器（ENABLE_SCALE_COLLECTOR=true）正在运行，会独占体重秤的通知通道，请先关闭后端采集再重试。',
            )
          }
        }, 25000)
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
    lastSynced,
    connect,
    disconnect,
    syncToBackend,
  }
}

/* ────────────────────────────────────────────────────────
 * 手环心率广播监听 Hook
 * ──────────────────────────────────────────────────────── */

/** 心率监听状态 */
export interface UseHrListener {
  capability: BluetoothCapability
  supported: boolean
  listening: boolean
  connecting: boolean
  /** 今天已采集的样本数 */
  sampleCount: number
  /** 最新一条心率 */
  lastHr: { bpm: number; at: Date; source: string } | null
  /** 最近一次批量同步的样本数 */
  lastSyncedCount: number
  error: string | null
  /** 开始监听（必须在用户点击中触发） */
  start: () => Promise<void>
  stop: () => void
}

export function useHrListener(): UseHrListener {
  const capability = detectBluetoothCapability()
  const supported = capability.available
  const [listening, setListening] = useState(false)
  const [connecting, setConnecting] = useState(false)
  const [sampleCount, setSampleCount] = useState(0)
  const [lastHr, setLastHr] = useState<{ bpm: number; at: Date; source: string } | null>(null)
  const [lastSyncedCount, setLastSyncedCount] = useState(0)
  const [error, setError] = useState<string | null>(null)

  const samplesRef = useRef<number[]>([])
  const lastSampleAtRef = useRef<number>(0)
  const freezeValueRef = useRef<{ bpm: number; since: number } | null>(null)
  const syncTimerRef = useRef<number | null>(null)
  const abortRef = useRef(false)

  const SAMPLE_INTERVAL_MS = 60_000 // 1 分钟采样间隔，避免广播高频污染
  const FREEZE_MS = 15 * 60_000 // 15 分钟不变视为冻结
  const BATCH_SYNC_MS = 30_000 // 每 30 秒批量同步一次

  const flushToBackend = useCallback(async () => {
    if (samplesRef.current.length === 0) return
    const batch = samplesRef.current
    samplesRef.current = []
    try {
      await api.create('/health/vitals-sleep/blesync', {
        samples: batch,
        source: 'xiaomi',
      })
      setLastSyncedCount((prev) => prev + batch.length)
    } catch {
      // 静默失败，下次再试
      samplesRef.current.unshift(...batch)
    }
  }, [])

  const start = useCallback(async () => {
    if (!supported) {
      setError('当前浏览器不支持 Web Bluetooth，请使用 Chrome 或 Edge')
      return
    }
    setError(null)
    setConnecting(true)

    try {
      // 桌面端通过 requestDevice + watchAdvertisements 监听广播。
      // 不能用 services/namePrefix 过滤：小米手环的广播包几乎不含标准服务 UUID，
      // 且设备名常为空，过滤会导致选择框里根本看不到手环。
      // 因此放开为 acceptAllDevices，由用户在列表中选择自己的设备。
      const device = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: [HR_SERVICE_UUID],
      })

      // watchAdvertisements 是接收广播的前提，不可用则无法采集心率
      if (typeof device.watchAdvertisements !== 'function') {
        setError('当前浏览器不支持广播监听（watchAdvertisements），无法采集手环心率')
        setConnecting(false)
        return
      }

      await device.watchAdvertisements()
      device.addEventListener('advertisementreceived', (ev) => {
        const { bpm, source } = decodeHeartRate(ev)
        if (bpm === null) return

        const now = Date.now()
        // 节流
        if (now - lastSampleAtRef.current < SAMPLE_INTERVAL_MS) return
        // 冻结检测
        if (freezeValueRef.current) {
          if (freezeValueRef.current.bpm === bpm && now - freezeValueRef.current.since > FREEZE_MS) return
          if (freezeValueRef.current.bpm !== bpm) freezeValueRef.current = { bpm, since: now }
        } else {
          freezeValueRef.current = { bpm, since: now }
        }

        lastSampleAtRef.current = now
        samplesRef.current.push(bpm)
        setSampleCount((c) => c + 1)
        setLastHr({ bpm, at: new Date(), source: source || 'xiaomi' })
      })

      abortRef.current = false
      setListening(true)

      // 定时批量同步
      syncTimerRef.current = window.setInterval(() => {
        if (!abortRef.current) flushToBackend()
      }, BATCH_SYNC_MS)
    } catch (err) {
      const { message } = classifyBluetoothError(err)
      setError(message)
    } finally {
      setConnecting(false)
    }
  }, [supported, flushToBackend])

  const stop = useCallback(() => {
    abortRef.current = true
    if (syncTimerRef.current !== null) {
      window.clearInterval(syncTimerRef.current)
      syncTimerRef.current = null
    }
    flushToBackend() // 停止前把剩余样本同步上去
    setListening(false)
  }, [flushToBackend])

  useEffect(() => {
    return () => {
      stop()
    }
  }, [stop])

  return { capability, supported, listening, connecting, sampleCount, lastHr, lastSyncedCount, error, start, stop }
}
