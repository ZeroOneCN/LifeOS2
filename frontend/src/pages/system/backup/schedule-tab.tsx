import { useState } from 'react'
import { Clock, Loader2, Pause, Pencil, Play, Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardHeaderActions,
  CardTitle,
} from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Switch } from '@/components/ui/switch'
import { Tip } from '@/components/ui/tip'
import { api } from '@/lib/api'

import { formatTime, type CronOption, type ScheduleItem } from './shared'

const CRON_PRESETS = [
  { label: '每天 00:00', value: '0 0 * * *' },
  { label: '每天 03:00', value: '0 3 * * *' },
  { label: '每天 06:00', value: '0 6 * * *' },
  { label: '每天 12:00', value: '0 12 * * *' },
  { label: '每 6 小时', value: '0 */6 * * *' },
  { label: '每 12 小时', value: '0 */12 * * *' },
  { label: '每周一 03:00', value: '0 3 * * 1' },
  { label: '每月1日 03:00', value: '0 3 1 * *' },
  { label: '自定义', value: '__custom__' },
] as const

type ScheduleTabProps = {
  selectedTables: Set<string>
  // 列表数据由页面层的统一轮询提供，未挂载时也保持刷新
  schedules: ScheduleItem[]
  loadingSchedules: boolean
  reloadSchedules: () => Promise<void>
}

export function ScheduleTab({
  selectedTables,
  schedules,
  loadingSchedules,
  reloadSchedules,
}: ScheduleTabProps) {
  // 新增/编辑定时备份弹窗
  const [showScheduleDialog, setShowScheduleDialog] = useState(false)
  const [editingSchedule, setEditingSchedule] = useState<ScheduleItem | null>(null)
  const [cronMode, setCronMode] = useState<CronOption>('preset')
  const [cronCustom, setCronCustom] = useState('0 3 * * *')
  const [newSchedule, setNewSchedule] = useState({
    name: '',
    cron_expression: '0 3 * * *',
    export_format: 'json',
    compress: false,
    table_selection: 'all',
  })
  const [savingSchedule, setSavingSchedule] = useState(false)

  // ── 定时备份 ──

  function isValidCron(expr: string): boolean {
    const parts = expr.trim().split(/\s+/)
    if (parts.length !== 5) return false
    const cronField = /^(\*|\d+|\*\/\d+|\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)$/
    return parts.every((p) => cronField.test(p))
  }

  const handleEditSchedule = (s: ScheduleItem) => {
    setEditingSchedule(s)
    setNewSchedule({
      name: s.name,
      cron_expression: s.cron_expression,
      export_format: s.export_format,
      compress: s.compress,
      table_selection: s.table_selection,
    })
    // 判断当前 cron 是否在预设中
    const isPreset = CRON_PRESETS.some((p) => p.value === s.cron_expression)
    if (isPreset) {
      setCronMode('preset')
    } else {
      setCronMode('custom')
      setCronCustom(s.cron_expression)
    }
    setShowScheduleDialog(true)
  }

  const handleCreateSchedule = async () => {
    if (!newSchedule.name.trim()) {
      toast.error('请输入任务名称')
      return
    }
    const cronExpr = cronMode === 'custom' ? cronCustom.trim() : newSchedule.cron_expression
    if (!cronExpr) {
      toast.error('请输入 cron 表达式')
      return
    }
    if (!isValidCron(cronExpr)) {
      toast.error('cron 表达式格式错误，标准格式为：分 时 日 月 周（5个字段，如 0 3 * * *）')
      return
    }
    setSavingSchedule(true)
    try {
      const body = {
        ...newSchedule,
        cron_expression: cronExpr,
        selected_tables:
          newSchedule.table_selection === 'selected'
            ? Array.from(selectedTables)
            : null,
      }
      if (editingSchedule) {
        await api.put<ScheduleItem>(`/backup/schedules/${editingSchedule.id}`, body)
        toast.success('定时备份任务已更新')
      } else {
        await api.post<ScheduleItem>('/backup/schedules', body)
        toast.success('定时备份任务已创建')
      }
      setShowScheduleDialog(false)
      setEditingSchedule(null)
      setCronMode('preset')
      setCronCustom('0 3 * * *')
      setNewSchedule({
        name: '',
        cron_expression: '0 3 * * *',
        export_format: 'json',
        compress: false,
        table_selection: 'all',
      })
      reloadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '操作失败')
    } finally {
      setSavingSchedule(false)
    }
  }

  const handleToggleSchedule = async (id: number) => {
    try {
      const result = await api.post<ScheduleItem>(`/backup/schedules/${id}/toggle`)
      toast.success(result.enabled ? '定时备份已启用' : '定时备份已暂停')
      reloadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '操作失败')
    }
  }

  const handleDeleteSchedule = async (id: number) => {
    try {
      await api.del(`/backup/schedules/${id}`)
      toast.success('定时备份任务已删除')
      reloadSchedules()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '删除失败')
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <div>
            <CardTitle className="flex items-center gap-2 text-lg min-w-0 max-w-[55%] truncate">
              <Clock className="h-5 w-5" />
              定时备份任务
            </CardTitle>
            <CardDescription>
              设置自动备份计划，系统将按 cron 表达式定时执行数据导出
            </CardDescription>
          </div>
          <CardHeaderActions>
            <Dialog open={showScheduleDialog} onOpenChange={(v) => {
              setShowScheduleDialog(v)
              if (!v) setEditingSchedule(null)
            }}>
              <DialogTrigger asChild>
                <Button onClick={() => { setEditingSchedule(null); setNewSchedule({ name: '', cron_expression: '0 3 * * *', export_format: 'json', compress: false, table_selection: 'all' }); setCronMode('preset'); setCronCustom('0 3 * * *') }}>
                  <Plus className="mr-1 h-4 w-4" />
                  新建任务
                </Button>
              </DialogTrigger>
              <DialogContent
                onPointerDownOutside={(e) => e.preventDefault()}
                onEscapeKeyDown={(e) => e.preventDefault()}
              >
                <DialogHeader>
                  <DialogTitle>{editingSchedule ? '编辑定时备份任务' : '新建定时备份任务'}</DialogTitle>
                  <DialogDescription>
                    {editingSchedule ? '修改定时备份的计划和参数' : '设置自动备份的计划和参数'}
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-4 py-2">
                  <div className="space-y-1">
                    <Label>任务名称</Label>
                    <Input
                      value={newSchedule.name}
                      onChange={(e) =>
                        setNewSchedule({ ...newSchedule, name: e.target.value })
                      }
                      placeholder="例如：每日凌晨备份"
                    />
                  </div>
                  <div className="space-y-1">
                    <Label>执行计划</Label>
                    <div className="space-y-2">
                      <Select
                        value={cronMode === 'custom' ? '__custom__' : newSchedule.cron_expression}
                        onValueChange={(v) => {
                          if (v === '__custom__') {
                            setCronMode('custom')
                          } else {
                            setCronMode('preset')
                            setNewSchedule({ ...newSchedule, cron_expression: v })
                          }
                        }}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {CRON_PRESETS.map((p) => (
                            <SelectItem key={p.value} value={p.value}>
                              {p.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      {cronMode === 'custom' && (
                        <Input
                          value={cronCustom}
                          onChange={(e) => setCronCustom(e.target.value)}
                          placeholder="5-field cron, e.g. 0 3 * * *"
                          className="font-mono text-xs"
                        />
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      cron 格式：分 时 日 月 周（例如 <code className="rounded bg-muted px-1">0 3 * * *</code> 表示每天 03:00）
                    </p>
                  </div>
                  <div className="space-y-1">
                    <Label>导出格式</Label>
                    <Select
                      value={newSchedule.export_format}
                      onValueChange={(v) =>
                        setNewSchedule({ ...newSchedule, export_format: v })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="json">JSON</SelectItem>
                        <SelectItem value="sql">SQL</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  {newSchedule.export_format === 'json' && (
                    <div className="flex items-center gap-2">
                      <Switch
                        id="schedule-compress"
                        checked={newSchedule.compress}
                        onCheckedChange={(v) =>
                          setNewSchedule({ ...newSchedule, compress: v })
                        }
                      />
                      <Label htmlFor="schedule-compress" className="cursor-pointer">
                        压缩为 ZIP
                      </Label>
                    </div>
                  )}
                  <div className="space-y-1">
                    <Label>导出范围</Label>
                    <Select
                      value={newSchedule.table_selection}
                      onValueChange={(v) =>
                        setNewSchedule({ ...newSchedule, table_selection: v })
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">全部数据表</SelectItem>
                        <SelectItem value="selected">选中的数据表</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setShowScheduleDialog(false)}>
                    取消
                  </Button>
                  <Button onClick={handleCreateSchedule} disabled={savingSchedule}>
                    {savingSchedule ? (
                      <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                    ) : null}
                    保存
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </CardHeaderActions>
        </CardHeader>
        <CardContent>
          {loadingSchedules ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : schedules.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
              <Clock className="mb-2 h-10 w-10" />
              <p>暂无定时备份任务</p>
              <p className="text-xs">点击"新建任务"按钮创建自动备份计划</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>任务名称</TableHead>
                    <TableHead>执行计划</TableHead>
                    <TableHead>格式</TableHead>
                    <TableHead>范围</TableHead>
                    <TableHead>上次执行</TableHead>
                    <TableHead>状态</TableHead>
                    <TableHead className="w-24 text-right">操作</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {schedules.map((s) => (
                    <TableRow key={s.id}>
                      <TableCell className="font-medium">{s.name}</TableCell>
                      <TableCell className="font-mono text-xs">{s.cron_expression}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className="font-mono text-xs uppercase">
                          {s.export_format}
                          {s.compress && ' ZIP'}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {s.table_selection === 'all' ? '全部' : '部分'}
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {s.last_run_at ? formatTime(s.last_run_at) : '未执行'}
                      </TableCell>
                      <TableCell>
                        {s.last_status === 'success' ? (
                          <Badge className="bg-success-muted text-success-muted-foreground">
                            成功
                          </Badge>
                        ) : s.last_status === 'failed' ? (
                          <Badge variant="destructive">失败</Badge>
                        ) : s.enabled ? (
                          <Badge variant="secondary" className="bg-info-muted text-info-muted-foreground">
                            等待中
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="text-muted-foreground">
                            已停止
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Tip label="编辑">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8"
                              onClick={() => handleEditSchedule(s)}
                            >
                              <Pencil className="h-4 w-4" />
                            </Button>
                          </Tip>
                          <Tip label={s.enabled ? '暂停' : '启用'}>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8"
                              onClick={() => handleToggleSchedule(s.id)}
                            >
                              {s.enabled ? (
                                <Pause className="h-4 w-4" />
                              ) : (
                                <Play className="h-4 w-4" />
                              )}
                            </Button>
                          </Tip>
                          <Tip label="删除">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-destructive hover:text-destructive"
                              onClick={() => handleDeleteSchedule(s.id)}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </Tip>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
