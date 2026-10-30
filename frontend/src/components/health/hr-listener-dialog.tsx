/**
 * 手环心率蓝牙监听弹窗组件。
 * 被动监听模式：开始后自动扫描广播，批量同步到后端。
 */

import { useEffect } from 'react'
import { Activity, Loader2, Play, Square, TrendingUp } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { useHrListener } from '@/hooks/use-web-bluetooth'

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSynced?: () => void
}

export function HrListenerDialog({ open, onOpenChange, onSynced }: Props) {
  const {
    capability,
    supported,
    listening,
    connecting,
    sampleCount,
    lastHr,
    lastSyncedCount,
    error,
    start,
    stop,
  } = useHrListener()

  // 弹窗关闭时自动停止监听
  useEffect(() => {
    if (!open && listening) stop()
  }, [open, listening, stop])

  const handleStart = async () => {
    await start()
  }

  const handleStop = () => {
    stop()
    onSynced?.()
  }

  const handleClose = () => {
    stop()
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Activity className="size-5 text-rose-500" />
            手环心率监听
          </DialogTitle>
          <DialogDescription>
            开始监听后，浏览器会持续接收手环的蓝牙广播并自动同步心率。
            选择设备时请确认手环已与手机 App 断开（被 App 占用时手环会停止广播），
            并保持本页面打开。
          </DialogDescription>
        </DialogHeader>

        <div className="rounded-lg border border-border/60 bg-muted/40 p-2.5 text-xs text-muted-foreground">
          设备列表里可能只显示手环的 MAC 地址或英文型号，按名称或信号强度选择你手环对应的那一个即可。
        </div>

        {!supported && (
          <div className="rounded-lg border border-amber-300/50 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300">
            <div className="font-medium mb-1">⚠️ {capability.reason}</div>
            {capability.suggestion && (
              <pre className="mt-1 whitespace-pre-wrap text-xs leading-relaxed font-mono">
{capability.suggestion}
              </pre>
            )}
          </div>
        )}

        <div className="space-y-3">
          {/* 状态卡片 */}
          <div className="grid grid-cols-3 gap-3">
            <div className="rounded-lg border p-3 text-center">
              <div className="text-xs text-muted-foreground">今日样本</div>
              <div className="mt-1 text-2xl font-semibold tabular-nums">{sampleCount}</div>
            </div>
            <div className="rounded-lg border p-3 text-center">
              <div className="text-xs text-muted-foreground">最新心率</div>
              <div className="mt-1 text-2xl font-semibold tabular-nums text-rose-500">
                {lastHr ? `${lastHr.bpm}` : '—'}
                {lastHr && <span className="ml-0.5 text-xs font-normal text-muted-foreground">bpm</span>}
              </div>
            </div>
            <div className="rounded-lg border p-3 text-center">
              <div className="text-xs text-muted-foreground">已同步</div>
              <div className="mt-1 text-2xl font-semibold tabular-nums text-emerald-500">
                {lastSyncedCount}
              </div>
            </div>
          </div>

          {/* 实时心率条 */}
          {lastHr && (
            <div className="rounded-lg border bg-card/80 p-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <TrendingUp className="size-4 text-rose-500" />
                  实时心率
                </div>
                <div className="text-xs text-muted-foreground">
                  {lastHr.at.toLocaleTimeString()} · {lastHr.source === 'xiaomi' ? '小米手环' : lastHr.source}
                </div>
              </div>
              <div className="mt-2 h-2 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-gradient-to-r from-rose-400 to-rose-600 transition-all duration-300"
                  style={{ width: `${Math.min(100, (lastHr.bpm / 200) * 100)}%` }}
                />
              </div>
              <div className="mt-1 flex justify-between text-xs text-muted-foreground">
                <span>20</span>
                <span>100</span>
                <span>180</span>
                <span>250</span>
              </div>
            </div>
          )}

          {/* 监听状态指示 */}
          {listening && (
            <div className="flex items-center gap-2 rounded-lg border border-emerald-300/50 bg-emerald-50 p-2 text-sm text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-300">
              <span className="relative flex size-2">
                <span className="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-75" />
                <span className="relative inline-flex size-2 rounded-full bg-emerald-500" />
              </span>
              正在监听蓝牙广播，请保持页面打开
            </div>
          )}

          {connecting && (
            <div className="flex items-center gap-2 rounded-lg border border-blue-300/50 bg-blue-50 p-2 text-sm text-blue-700 dark:border-blue-500/30 dark:bg-blue-500/10 dark:text-blue-300">
              <Loader2 className="size-4 animate-spin" />
              等待浏览器授权...
            </div>
          )}

          {error && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-2 text-xs text-destructive">
              {error}
            </div>
          )}
        </div>

        <DialogFooter>
          {!listening ? (
            <Button onClick={handleStart} disabled={!supported || connecting}>
              {connecting ? <Loader2 className="mr-2 size-4 animate-spin" /> : <Play className="mr-2 size-4" />}
              开始监听
            </Button>
          ) : (
            <Button variant="destructive" onClick={handleStop}>
              <Square className="mr-2 size-4" />
              停止并同步
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
