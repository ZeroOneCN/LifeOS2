import { useEffect, useState } from 'react'
import { Loader2, Pencil, Plus, Settings, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { DatePicker } from '@/components/ui/date-picker'
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
import { BarChartCard, LineChartCard } from '@/components/health/charts'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
import { api } from '@/lib/api'

type StepsRecord = {
  id: number
  record_date: string
  period: string
  steps: number
  distance_km?: number
  calories?: number
}

type MonthlyStats = { months: { month: string; steps: number; distance_km: number; calories: number; days: number }[] }

type DaySummary = {
  month: string
  items: { record_date: string; steps: number; distance_km?: number; calories?: number }[]
  total: number
  page: number
  page_size: number
}

type MonthDetail = {
  month: string
  days: { record_date: string; period: string; steps: number }[]
}

type SeriesPoint = { record_date: string; steps: number }
type PeriodPoint = { period: string; label: string; steps: number }

const DAILY_PAGE_SIZE = 8

// 逐小时时段：08-09 … 22-23，末段 full（全天最终累计）
const PERIODS = [
  { value: '08-09', label: '08:00-09:00' },
  { value: '09-10', label: '09:00-10:00' },
  { value: '10-11', label: '10:00-11:00' },
  { value: '11-12', label: '11:00-12:00' },
  { value: '12-13', label: '12:00-13:00' },
  { value: '13-14', label: '13:00-14:00' },
  { value: '14-15', label: '14:00-15:00' },
  { value: '15-16', label: '15:00-16:00' },
  { value: '16-17', label: '16:00-17:00' },
  { value: '17-18', label: '17:00-18:00' },
  { value: '18-19', label: '18:00-19:00' },
  { value: '19-20', label: '19:00-20:00' },
  { value: '20-21', label: '20:00-21:00' },
  { value: '21-22', label: '21:00-22:00' },
  { value: '22-23', label: '22:00-23:00' },
  { value: '23-24', label: '23:00-23:59' },
  { value: 'full', label: '23:59（全天最终）' },
]

const periodLabel = (p: string) => PERIODS.find((x) => x.value === p)?.label ?? p
const periodOrder = PERIODS.map((p) => p.value)

const EMPTY = {
  record_date: new Date().toISOString().slice(0, 10),
  period: 'full',
  steps: '',
}

export function StepsPage() {
  const [items, setItems] = useState<StepsRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<StepsRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(EMPTY)
  const [settingDialogOpen, setSettingDialogOpen] = useState(false)
  const [stride, setStride] = useState('70')
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条步数记录吗？此操作不可恢复。',
  })

  const [refresh, setRefresh] = useState(0)
  const [year, setYear] = useState<number>(new Date().getFullYear())
  const [selMonth, setSelMonth] = useState<number>(new Date().getMonth() + 1)
  const [months, setMonths] = useState<MonthlyStats['months']>([])
  const [daySum, setDaySum] = useState<DaySummary | null>(null)
  const [dailyPage, setDailyPage] = useState(1)
  const [detail, setDetail] = useState<MonthDetail | null>(null)
  const [activePeriod, setActivePeriod] = useState<string | null>(null)

  const DAILY_TOTAL_PAGES = Math.max(1, Math.ceil((daySum?.total ?? 0) / DAILY_PAGE_SIZE))

  // 可用年份（从每月聚合数据派生）
  const years = [...new Set([...months.map((m) => Number(m.month.slice(0, 4))), new Date().getFullYear()])]
    .filter((v) => Number.isFinite(v))
    .sort((a, b) => b - a)

  const loadDaySummary = async () => {
    const res = await api.query<DaySummary>(
      `/health/steps/daily-summary?year=${year}&month=${selMonth}&page=${dailyPage}&page_size=${DAILY_PAGE_SIZE}`,
    )
    setDaySum(res)
  }

  const loadMonthDetail = async () => {
    const res = await api.query<MonthDetail>(`/health/steps/month-detail?year=${year}&month=${selMonth}`)
    setDetail(res)
  }

  useEffect(() => {
    loadDaySummary()
    loadMonthDetail()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh, dailyPage, year, selMonth])

  useEffect(() => {
    api.query<{ stride_cm: number }>('/health/steps/settings').then((r) => setStride(String(r.stride_cm)))
  }, [])

  useEffect(() => {
    api.query<MonthlyStats>('/health/steps/monthly').then((r) => setMonths(r.months))
  }, [refresh])

  const PAGE_SIZE = 10
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<StepsRecord>('/health/steps', { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page])

  const openCreate = () => {
    setEditing(null)
    setForm(EMPTY)
    setDialogOpen(true)
  }

  const openEdit = (row: StepsRecord) => {
    setEditing(row)
    setForm({
      record_date: row.record_date,
      period: row.period,
      steps: String(row.steps),
    })
    setDialogOpen(true)
  }

  const set = (key: keyof typeof EMPTY, value: string) => setForm((f) => ({ ...f, [key]: value }))

  const submit = async () => {
    const payload = {
      record_date: form.record_date,
      period: form.period,
      steps: Number(form.steps),
    }
    setSaving(true)
    try {
      if (editing) await api.update('/health/steps', editing.id, payload)
      else await api.create('/health/steps', payload)
      setDialogOpen(false)
      setPage(1)
      await load()
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: StepsRecord) => {
    if (!(await confirm())) return
    await api.remove('/health/steps', row.id)
    if (items.length === 1 && page > 1) setPage(page - 1)
    else await load()
  }

  const saveSetting = async () => {
    await api.put('/health/steps/settings', { stride_cm: Number(stride) || 70 })
    setSettingDialogOpen(false)
    setRefresh((r) => r + 1)
    await load()
  }

  // ---- 派生可视化数据（基于 month-detail） ----
  // 每日趋势：同一天取最大 steps
  const dailyTrend: SeriesPoint[] = []
  {
    const byDate = new Map<string, number>()
    for (const d of detail?.days ?? []) {
      const cur = byDate.get(d.record_date)
      if (cur === undefined || d.steps > cur) byDate.set(d.record_date, d.steps)
    }
    for (const [dt, steps] of [...byDate.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
      dailyTrend.push({ record_date: dt, steps })
    }
  }

  // 时段分布：各时间段的"当日贡献"。由于同一时段在同一天有且只有一条，直接求和即可代表当月该时段累计
  const periodDist: PeriodPoint[] = []
  {
    const byPeriod = new Map<string, number>()
    for (const d of detail?.days ?? []) {
      byPeriod.set(d.period, (byPeriod.get(d.period) ?? 0) + d.steps)
    }
    for (const p of PERIODS) {
      const v = byPeriod.get(p.value)
      if (v !== undefined) periodDist.push({ period: p.value, label: p.label, steps: v })
    }
    // 补漏（若 DB 有 PERIODS 外的 period）
    for (const [p, v] of byPeriod) {
      if (!PERIODS.some((x) => x.value === p)) periodDist.push({ period: p, label: p, steps: v })
    }
  }

  // 选中时段的每日对比
  const periodCompare: SeriesPoint[] = activePeriod
    ? (detail?.days ?? [])
        .filter((d) => d.period === activePeriod)
        .sort((a, b) => a.record_date.localeCompare(b.record_date))
        .map((d) => ({ record_date: d.record_date, steps: d.steps }))
    : []

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">步数统计</h1>
          <p className="text-sm text-muted-foreground">按时间段录入每日步数，自动按步幅计算距离，支持按月查看汇总与时间段对比。</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setSettingDialogOpen(true)}>
            <Settings /> 步幅({stride}cm)
          </Button>
          <Button onClick={openCreate}>
            <Plus /> 新增步数
          </Button>
        </div>
      </section>

      <div className="flex flex-wrap items-center gap-2">
        <Select value={String(year)} onValueChange={(v) => setYear(Number(v))}>
          <SelectTrigger className="w-32">
            <SelectValue placeholder="选择年份" />
          </SelectTrigger>
          <SelectContent>
            {years.map((y) => (
              <SelectItem key={y} value={String(y)}>
                {y} 年
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={String(selMonth)} onValueChange={(v) => setSelMonth(Number(v))}>
          <SelectTrigger className="w-28">
            <SelectValue placeholder="选择月份" />
          </SelectTrigger>
          <SelectContent>
            {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
              <SelectItem key={m} value={String(m)}>
                {m} 月
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <span className="text-sm text-muted-foreground">
          {year} 年 {selMonth} 月
        </span>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <LineChartCard
          title="本月每日步数趋势（取每日最大值）"
          data={dailyTrend}
          xKey="record_date"
          series={[{ key: 'steps', name: '步数', color: '#10b981' }]}
          height={260}
          intTick
        />
        <BarChartCard
          title="时间段分布（当月累计）"
          data={periodDist}
          xKey="label"
          series={[{ key: 'steps', name: '步数', color: '#3b82f6' }]}
          height={260}
          intTick
          onBarClick={(payload) => {
            const p = periodOrder.find((x) => periodLabel(x) === payload?.label)
            if (p) setActivePeriod((prev) => (prev === p ? null : p))
          }}
          selectedKey={activePeriod ? periodLabel(activePeriod) : undefined}
        />
      </div>

      {activePeriod && (
        <LineChartCard
          title={`每天 ${periodLabel(activePeriod)} 步数对比（当月）`}
          data={periodCompare}
          xKey="record_date"
          series={[{ key: 'steps', name: '步数', color: '#f59e0b' }]}
          height={240}
          intTick
        />
      )}

      <Card>
        <CardContent className="p-0">
          <div className="flex items-center justify-between px-4 pt-4 pb-2">
            <div className="text-sm font-medium">
              每日步数汇总{daySum?.month ? `（${daySum.month}）` : ''}
            </div>
          </div>
          {daySum && daySum.items.length === 0 ? (
            <div className="px-4 pb-4 text-center text-sm text-muted-foreground">当月暂无步数数据</div>
          ) : (
            <>
              <div className="grid gap-3 px-4 pb-4 sm:grid-cols-2 xl:grid-cols-4">
                {daySum?.items.map((d) => (
                  <Card key={d.record_date} className="border-dashed">
                    <CardContent className="py-3">
                      <div className="text-sm font-medium text-foreground">{d.record_date}</div>
                      <div className="mt-1 text-2xl font-semibold">{d.steps.toLocaleString()}</div>
                      <div className="mt-2 flex gap-3 text-xs text-muted-foreground">
                        <span>距离 {d.distance_km != null ? `${d.distance_km} km` : '—'}</span>
                        <span>消耗 {d.calories != null ? `${d.calories} kcal` : '—'}</span>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
              <div className="px-4 pb-4">
                <PaginationBar
                  page={dailyPage}
                  totalPages={DAILY_TOTAL_PAGES}
                  total={daySum?.total ?? 0}
                  onPageChange={setDailyPage}
                />
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {months.length > 0 && (
        <Card>
          <CardContent className="p-0">
            <div className="px-4 pt-4 pb-2 text-sm font-medium">每月步数汇总（每月 = 每天最大值之和）</div>
            <div className="grid gap-3 px-4 pb-4 sm:grid-cols-2 xl:grid-cols-4">
              {[...months]
                .sort((a, b) => b.month.localeCompare(a.month))
                .map((m) => (
                  <Card key={m.month} className="border-dashed">
                    <CardContent className="py-3">
                      <div className="text-sm font-medium text-foreground">{m.month}</div>
                      <div className="mt-1 text-2xl font-semibold">{m.steps.toLocaleString()}</div>
                      <div className="mt-2 flex gap-3 text-xs text-muted-foreground">
                        <span>距离 {m.distance_km} km</span>
                        <span>活动 {m.days} 天</span>
                      </div>
                    </CardContent>
                  </Card>
                ))}
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardContent className="p-0">
          <div className="px-4 pt-4 pb-1 text-sm font-medium">时间段明细（每时间段步数记录，最新在前）</div>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>日期</TableHead>
                <TableHead>时间段</TableHead>
                <TableHead>步数</TableHead>
                <TableHead>距离</TableHead>
                <TableHead>消耗</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                      <Loader2 className="mx-auto size-5 animate-spin" />
                    </TableCell>
                  </TableRow>
                ) : (
                  <TableRow>
                    <TableCell colSpan={6} className="h-24 text-center text-muted-foreground">
                      暂无记录，点击"新增步数"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.record_date}</TableCell>
                    <TableCell>{periodLabel(row.period)}</TableCell>
                    <TableCell>{row.steps.toLocaleString()}</TableCell>
                    <TableCell>{row.distance_km != null ? `${row.distance_km} km` : '—'}</TableCell>
                    <TableCell>{row.calories != null ? `${row.calories} kcal` : '—'}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => openEdit(row)}>
                          <Pencil />
                        </Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => remove(row)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑步数记录' : '新增步数记录'}</DialogTitle>
            <DialogDescription>选择时间段录入步数，距离按步幅自动计算。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>
                日期 <span className="text-destructive">*</span>
              </Label>
              <DatePicker value={form.record_date} onChange={(v) => set('record_date', v)} />
            </div>
            <div className="space-y-2">
              <Label>
                时间段 <span className="text-destructive">*</span>
              </Label>
              <Select value={form.period} onValueChange={(v) => set('period', v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {PERIODS.map((p) => (
                    <SelectItem key={p.value} value={p.value}>
                      {p.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>
                步数 <span className="text-destructive">*</span>
              </Label>
              <Input type="number" min="0" value={form.steps} onChange={(e) => set('steps', e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>消耗(kcal)</Label>
              <Input
                type="number"
                min="0"
                step="0.1"
                value={((Number(form.steps) || 0) * 0.04).toFixed(1)}
                readOnly
                placeholder="自动≈步数*0.04"
              />
              <p className="text-xs text-muted-foreground">消耗随步数自动计算（步数×0.04），不可手动修改</p>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={submit} disabled={saving || !form.record_date || !form.steps}>
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={settingDialogOpen} onOpenChange={setSettingDialogOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>步幅设置</DialogTitle>
            <DialogDescription>设置每步步幅（cm），用于自动计算步行距离。</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>每步步幅（cm）</Label>
            <Input type="number" step="0.1" value={stride} onChange={(e) => setStride(e.target.value)} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSettingDialogOpen(false)}>
              取消
            </Button>
            <Button onClick={saveSetting}>保存</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}