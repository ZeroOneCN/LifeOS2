import { useEffect, useState } from 'react'

/** 全局数据变更事件名：写操作（增/删/改）成功后广播，页面据此无感刷新 */
export const DATA_CHANGED_EVENT = 'lifeos:data-changed'

/**
 * 无感实时刷新钩子：返回一个随"定时轮询 / 窗口重新聚焦 / 数据变更广播"递增的 tick。
 * 把 tick 加入数据请求的依赖即可让页面在不切换、不手动刷新时自动获取最新数据。
 *
 * @param intervalMs 轮询间隔（毫秒）；传 0 或省略则仅窗口聚焦与数据变更触发
 */
export function useRealtime(intervalMs = 0): number {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const bump = () => setTick((t) => t + 1)
    const timer = intervalMs > 0 ? setInterval(bump, intervalMs) : undefined
    window.addEventListener('focus', bump)
    window.addEventListener(DATA_CHANGED_EVENT, bump)
    return () => {
      if (timer) clearInterval(timer)
      window.removeEventListener('focus', bump)
      window.removeEventListener(DATA_CHANGED_EVENT, bump)
    }
  }, [intervalMs])

  return tick
}
