import { useEffect, useState } from 'react'

/** 全局数据变更事件名：写操作（增/删/改）成功后广播，页面据此无感刷新 */
export const DATA_CHANGED_EVENT = 'lifeos:data-changed'

/**
 * 无感实时刷新钩子：返回一个随"定时轮询 / 窗口重新聚焦 / 数据变更广播"递增的 tick。
 * 把 tick 加入数据请求的依赖即可让页面在不切换、不手动刷新时自动获取最新数据。
 *
 * 标签页不可见时自动暂停轮询，可见后立即恢复并触发一次刷新。
 *
 * @param intervalMs 轮询间隔（毫秒）；传 0 或省略则仅窗口聚焦与数据变更触发
 */
export function useRealtime(intervalMs = 0): number {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const bump = () => setTick((t) => t + 1)
    let timer: ReturnType<typeof setInterval> | undefined

    const startPolling = () => {
      if (intervalMs > 0 && !timer) {
        timer = setInterval(bump, intervalMs)
      }
    }
    const stopPolling = () => {
      if (timer) {
        clearInterval(timer)
        timer = undefined
      }
    }

    const onVisibilityChange = () => {
      if (document.hidden) {
        stopPolling()
      } else {
        startPolling()
        bump() // 可见时立即触发一次刷新
      }
    }

    // 初始：仅在可见时启动轮询
    if (!document.hidden) {
      startPolling()
    }

    window.addEventListener('focus', bump)
    window.addEventListener(DATA_CHANGED_EVENT, bump)
    document.addEventListener('visibilitychange', onVisibilityChange)

    return () => {
      stopPolling()
      window.removeEventListener('focus', bump)
      window.removeEventListener(DATA_CHANGED_EVENT, bump)
      document.removeEventListener('visibilitychange', onVisibilityChange)
    }
  }, [intervalMs])

  return tick
}
