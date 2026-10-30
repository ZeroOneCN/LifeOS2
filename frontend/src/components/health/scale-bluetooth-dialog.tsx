/**
 * 体重秤蓝牙连接弹窗组件。
 * 提供用户资料输入、蓝牙连接状态展示、实时测量结果显示和一键同步后端。
 */

import { useState } from 'react'
import { Bluetooth, Loader2, WifiOff, CheckCircle, Scale } from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { useScaleBluetooth, type ScaleProfile } from '@/hooks/use-web-bluetooth'

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  defaultProfile?: Partial<ScaleProfile>
  onSynced?: () => void
}

export function ScaleBluetoothDialog({ open, onOpenChange, defaultProfile, onSynced }: Props) {
  const {
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
  } = useScaleBluetooth()

  const [profile, setProfile] = useState<ScaleProfile>({
    heightCm: defaultProfile?.heightCm ?? 170,
    age: defaultProfile?.age ?? 25,
    isMale: defaultProfile?.isMale ?? true,
  })
  const [syncing, setSyncing] = useState(false)

  const handleConnect = async () => {
    try {
      await connect(profile)
    } catch {
      // 错误已在 hook 内设置
    }
  }

  const handleSync = async () => {
    setSyncing(true)
    try {
      const ok = await syncToBackend()
      if (ok) {
        toast.success('体重数据已同步')
        onSynced?.()
      } else {
        toast.error('同步失败', { description: error ?? '请稍后重试' })
      }
    } finally {
      setSyncing(false)
    }
  }

  const handleClose = () => {
    disconnect()
    onOpenChange(false)
  }

  const statusBadge = () => {
    if (!supported) return <span className="text-amber-500">⚠️ 当前浏览器不支持</span>
    if (connecting) return <span className="flex items-center gap-1 text-blue-500"><Loader2 className="size-3 animate-spin" />连接中...</span>
    if (gattConnected && !dataReady) return <span className="text-amber-500">GATT 已连接，等待数据通道...</span>
    if (dataReady) return <span className="flex items-center gap-1 text-emerald-500"><CheckCircle className="size-3" />已就绪，请上秤</span>
    return <span className="text-muted-foreground">未连接</span>
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Scale className="size-5 text-cyan-500" />
            蓝牙体重秤
          </DialogTitle>
          <DialogDescription>
            通过 Web Bluetooth 连接你的体重秤，测量完成后自动同步到健康中心。
          </DialogDescription>
        </DialogHeader>

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
          <div className="flex items-center gap-2 text-sm">
            <span className="text-muted-foreground">状态：</span>
            {statusBadge()}
          </div>

          <div className="grid grid-cols-3 gap-3 rounded-lg border bg-card/50 p-3">
            <div className="space-y-1">
              <Label className="text-xs">身高(cm)</Label>
              <Input
                type="number"
                min={100}
                max={250}
                value={profile.heightCm}
                onChange={(e) => setProfile((p) => ({ ...p, heightCm: Number(e.target.value) || 170 }))}
                disabled={gattConnected}
                className="h-8 text-sm"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">年龄</Label>
              <Input
                type="number"
                min={1}
                max={120}
                value={profile.age}
                onChange={(e) => setProfile((p) => ({ ...p, age: Number(e.target.value) || 25 }))}
                disabled={gattConnected}
                className="h-8 text-sm"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">性别</Label>
              <Select
                value={profile.isMale ? 'male' : 'female'}
                onValueChange={(v) => setProfile((p) => ({ ...p, isMale: v === 'male' }))}
                disabled={gattConnected}
              >
                <SelectTrigger className="h-8 text-sm">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="male">男</SelectItem>
                  <SelectItem value="female">女</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {error && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-2 text-xs text-destructive">
              {error}
            </div>
          )}

          {measurement && (
            <div className="rounded-lg border bg-card/80 p-3">
              <div className="flex items-center justify-between">
                <div className="text-sm text-muted-foreground">最新测量</div>
                <div className="text-xs text-muted-foreground">
                  {measurement.measuredAt.toLocaleTimeString()}
                </div>
              </div>
              <div className="mt-2 text-center">
                <div className="text-4xl font-bold tabular-nums text-cyan-600 dark:text-cyan-400">
                  {measurement.weightKg.toFixed(1)}
                  <span className="ml-1 text-base font-normal text-muted-foreground">kg</span>
                </div>
                {measurement.bodyComposition && (
                  <div className="mt-2 grid grid-cols-4 gap-2 text-xs">
                    <div>
                      <div className="text-muted-foreground">BMI</div>
                      <div className="font-semibold">{measurement.bodyComposition.bmi}</div>
                    </div>
                    <div>
                      <div className="text-muted-foreground">体脂率</div>
                      <div className="font-semibold text-rose-500">{measurement.bodyComposition.body_fat}%</div>
                    </div>
                    <div>
                      <div className="text-muted-foreground">肌肉率</div>
                      <div className="font-semibold text-emerald-500">{measurement.bodyComposition.muscle_rate}%</div>
                    </div>
                    <div>
                      <div className="text-muted-foreground">基础代谢</div>
                      <div className="font-semibold">{measurement.bodyComposition.bmr}</div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {lastSynced && (
            <div className="flex items-center gap-1 text-xs text-emerald-500">
              <CheckCircle className="size-3" />
              已同步 {lastSynced.weightKg.toFixed(1)} kg（{lastSynced.at.toLocaleTimeString()}）
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          {!gattConnected ? (
            <Button onClick={handleConnect} disabled={!supported || connecting}>
              {connecting ? <Loader2 className="mr-2 size-4 animate-spin" /> : <Bluetooth className="mr-2 size-4" />}
              {connecting ? '连接中...' : '连接体重秤'}
            </Button>
          ) : (
            <>
              <Button variant="outline" onClick={disconnect}>
                <WifiOff className="mr-2 size-4" />
                断开
              </Button>
              <Button onClick={handleSync} disabled={!measurement || syncing}>
                {syncing ? <Loader2 className="mr-2 size-4 animate-spin" /> : <CheckCircle className="mr-2 size-4" />}
                同步到健康中心
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
