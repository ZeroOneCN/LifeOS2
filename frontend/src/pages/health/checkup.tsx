import { useEffect, useMemo, useState, type ReactNode } from 'react'
import {
  Activity,
  AlertTriangle,
  ArrowDownRight,
  ArrowUpRight,
  CheckCircle2,
  Library,
  Loader2,
  Minus,
  Pencil,
  Plus,
  Trash2,
  X,
} from 'lucide-react'
import { toast } from 'sonner'

import { useRealtime } from '@/hooks/use-realtime'
import { Badge } from '@/components/ui/badge'
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
import { StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import { api } from '@/lib/api'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'

type CheckupRecord = {
  id: number
  check_date: string
  item_name: string
  value?: number
  unit?: string
  ref_low?: number
  ref_high?: number
  reference_range?: string
  result?: string
  note?: string
}

type TrendPoint = { check_date: string; value?: number | null; result?: string | null }

type CheckupStats = {
  items: {
    item_name: string
    unit?: string
    reference_range?: string
    ref_low?: number | null
    ref_high?: number | null
    latest: { check_date: string; value?: number; result?: string } | null
    count: number
    trend?: TrendPoint[]
  }[]
  total_count?: number
  abnormal_count: number
  status_counts: { normal: number; high: number; low: number }
  abnormal_items: { check_date: string; value?: number; result?: string }[]
}

type Template = { id: number; item_name: string; category?: string; unit?: string; ref_low?: number; ref_high?: number }

type PanelItem = { item_name: string; unit?: string; ref_low?: number | null; ref_high?: number | null; reference_range?: string }
type Panel = { id: number; panel_name: string; note?: string; items: PanelItem[] }

type RecordItemForm = {
  item_name: string
  value: string
  unit?: string
  ref_low?: number | null
  ref_high?: number | null
  reference_range?: string
}

const resultMeta: Record<string, { label: string; className: string }> = {
  normal: { label: '正常', className: 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300' },
  high: { label: '偏高', className: 'bg-red-100 text-red-700 dark:bg-red-500/15 dark:text-red-300' },
  low: { label: '偏低', className: 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300' },
}

function judge(value: string, lo?: number | null, hi?: number | null): string {
  const v = Number(value)
  if (Number.isNaN(v)) return ''
  if (hi != null && v > hi) return 'high'
  if (lo != null && v < lo) return 'low'
  return 'normal'
}

function fmtRange(lo?: number | null, hi?: number | null): string {
  if (lo == null && hi == null) return ''
  if (lo != null && hi != null) return `${lo}~${hi}`
  if (lo != null) return `≥${lo}`
  return `≤${hi}`
}

/** 结果严重度排序：偏高/偏低（异常）优先，正常次之，未判定最后。 */
const RESULT_RANK: Record<string, number> = { high: 0, low: 1, normal: 2 }

/** 概览筛选维度。 */
const OVERVIEW_FILTERS = [
  { key: 'all', label: '全部' },
  { key: 'abnormal', label: '异常' },
  { key: 'normal', label: '正常' },
] as const

type OverviewFilter = (typeof OVERVIEW_FILTERS)[number]['key']

const STAT_TONE: Record<'danger' | 'success' | 'warn' | 'neutral', string> = {
  danger: 'text-red-600 dark:text-red-400',
  success: 'text-green-600 dark:text-green-400',
  warn: 'text-amber-500',
  neutral: 'text-foreground',
}

/** 计算最新一次相对上一次的数值变化；数据不足两次返回 null。 */
function deltaOf(trend?: TrendPoint[]): number | null {
  if (!trend || trend.length < 2) return null
  const cur = trend[trend.length - 1]?.value
  const prev = trend[trend.length - 2]?.value
  if (cur == null || prev == null) return null
  return Number((cur - prev).toFixed(2))
}

/** 顶部概览统计卡：点击可按该状态筛选下方指标概览。 */
function StatCard({
  label,
  value,
  tone = 'neutral',
  icon,
  active,
  onClick,
}: {
  label: string
  value: number
  tone?: 'danger' | 'success' | 'warn' | 'neutral'
  icon: ReactNode
  active?: boolean
  onClick?: () => void
}) {
  return (
    <Card
      onClick={onClick}
      className={`transition-colors ${onClick ? 'cursor-pointer hover:border-foreground/25' : ''} ${
        active ? 'border-primary/60 ring-1 ring-primary/30' : ''
      }`}
    >
      <CardContent className="flex items-center justify-between py-4">
        <div>
          <div className="text-sm text-muted-foreground">{label}</div>
          <div className={`mt-1 text-2xl font-semibold tabular-nums ${STAT_TONE[tone]}`}>
            {value}
            <span className="ml-1 text-sm font-normal text-muted-foreground">项</span>
          </div>
        </div>
        <span className={`${STAT_TONE[tone]} opacity-70`}>{icon}</span>
      </CardContent>
    </Card>
  )
}

/** 趋势提示：展示最新值相较上一次的变化方向与幅度。 */
function TrendHint({ delta }: { delta: number | null }) {
  if (delta == null) {
    return <div className="mt-0.5 text-xs text-muted-foreground">首次记录</div>
  }
  if (delta === 0) {
    return (
      <div className="mt-0.5 flex items-center justify-end gap-0.5 text-xs text-muted-foreground">
        <Minus className="size-3" /> 持平
      </div>
    )
  }
  const up = delta > 0
  return (
    <div className="mt-0.5 flex items-center justify-end gap-0.5 text-xs text-muted-foreground">
      {up ? <ArrowUpRight className="size-3" /> : <ArrowDownRight className="size-3" />}
      {up ? '+' : ''}
      {delta}
    </div>
  )
}

/** 指标概览卡：展示单个指标的最新值、参考范围、判定结果与较上次变化。 */
function IndicatorCard({ item }: { item: CheckupStats['items'][number] }) {
  const meta = item.latest?.result ? resultMeta[item.latest.result] : undefined
  const delta = deltaOf(item.trend)
  const range = item.reference_range || fmtRange(item.ref_low, item.ref_high) || '—'
  return (
    <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium" title={item.item_name}>
            {item.item_name}
          </span>
          {meta && <Badge className={meta.className}>{meta.label}</Badge>}
        </div>
        <div className="mt-1 truncate text-xs text-muted-foreground" title={`参考 ${range} · 共 ${item.count} 次`}>
          参考 {range} · {item.count} 次
        </div>
      </div>
      <div className="shrink-0 text-right">
        <div className="text-lg font-semibold tabular-nums">
          {item.latest?.value != null ? item.latest.value : '—'}
          <span className="ml-1 text-xs font-normal text-muted-foreground">{item.unit ?? ''}</span>
        </div>
        <TrendHint delta={delta} />
      </div>
    </div>
  )
}

export function CheckupPage() {
  const [items, setItems] = useState<CheckupRecord[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<CheckupRecord | null>(null)
  const [saving, setSaving] = useState(false)
  const [checkDate, setCheckDate] = useState(new Date().toISOString().slice(0, 10))
  const [recordItems, setRecordItems] = useState<RecordItemForm[]>([])
  const [templates, setTemplates] = useState<Template[]>([])
  const [panels, setPanels] = useState<Panel[]>([])
  const [presets, setPresets] = useState<{ panel_name: string; note?: string; items: PanelItem[] }[]>([])
  const [templateDialogOpen, setTemplateDialogOpen] = useState(false)
  const [libTab, setLibTab] = useState<'single' | 'panel'>('single')
  const [templateFormOpen, setTemplateFormOpen] = useState(false)
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null)
  const [savingTemplate, setSavingTemplate] = useState(false)
  const [tplForm, setTplForm] = useState({ item_name: '', category: '', unit: '', ref_low: '', ref_high: '' })
  // 组合模板编辑
  const [panelFormOpen, setPanelFormOpen] = useState(false)
  const [editingPanel, setEditingPanel] = useState<Panel | null>(null)
  const [savingPanel, setSavingPanel] = useState(false)
  const [panelName, setPanelName] = useState('')
  const [panelNote, setPanelNote] = useState('')
  const [panelItems, setPanelItems] = useState<PanelItem[]>([])
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除',
    description: '确定删除这条体检记录吗？此操作不可恢复。',
  })

  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const [overviewFilter, setOverviewFilter] = useState<OverviewFilter>('all')
  const [refresh, setRefresh] = useState(0)
  const realtimeTick = useRealtime(30_000)
  const { data: stats } = useStats<CheckupStats>('/health/checkup', days, refresh)
  const PAGE_SIZE = 10
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.list<CheckupRecord>('/health/checkup', { page, page_size: PAGE_SIZE })
      setItems(res.items)
      setTotal(res.total)
    } finally {
      setLoading(false)
    }
  }

  const loadTemplates = async () => {
    const res = await api.list<Template>('/health/checkup/templates', { page: 1, page_size: 100 })
    setTemplates(res.items)
  }

  const loadPanels = async () => {
    setPanels(await api.query<Panel[]>('/health/checkup/panels').catch(() => []))
  }

  const loadPresets = async () => {
    setPresets(await api.query<{ panel_name: string; note?: string; items: PanelItem[] }[]>('/health/checkup/panels/presets').catch(() => []))
  }

  useEffect(() => {
    load()
    loadTemplates()
    loadPanels()
    loadPresets()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, realtimeTick])

  const openCreate = () => {
    setEditing(null)
    setCheckDate(new Date().toISOString().slice(0, 10))
    setRecordItems([])
    setDialogOpen(true)
  }

  const openEdit = (row: CheckupRecord) => {
    setEditing(row)
    setCheckDate(row.check_date)
    setRecordItems([
      {
        item_name: row.item_name,
        value: String(row.value ?? ''),
        unit: row.unit ?? '',
        ref_low: row.ref_low ?? null,
        ref_high: row.ref_high ?? null,
        reference_range: row.reference_range ?? fmtRange(row.ref_low ?? null, row.ref_high ?? null),
      },
    ])
    setDialogOpen(true)
  }

  // 选择套餐/组合：把组合内尚未添加的指标加入录入列表
  const applyPanel = (panel: { panel_name: string; note?: string; items: PanelItem[] }) => {
    setRecordItems((prev) => {
      const names = new Set(prev.map((r) => r.item_name))
      const added = panel.items
        .filter((it) => it.item_name && !names.has(it.item_name))
        .map((it) => ({
          item_name: it.item_name,
          value: '',
          unit: it.unit ?? '',
          ref_low: it.ref_low ?? null,
          ref_high: it.ref_high ?? null,
          reference_range: it.reference_range ?? fmtRange(it.ref_low ?? null, it.ref_high ?? null),
        }))
      return [...prev, ...added]
    })
  }

  // 自由组合：切换单个指标模板
  const toggleTemplate = (tpl: Template) => {
    setRecordItems((prev) => {
      if (prev.some((r) => r.item_name === tpl.item_name)) {
        return prev.filter((r) => r.item_name !== tpl.item_name)
      }
      return [
        ...prev,
        {
          item_name: tpl.item_name,
          value: '',
          unit: tpl.unit ?? '',
          ref_low: tpl.ref_low ?? null,
          ref_high: tpl.ref_high ?? null,
          reference_range: fmtRange(tpl.ref_low ?? null, tpl.ref_high ?? null),
        },
      ]
    })
  }

  const updateRecordItem = (idx: number, patch: Partial<RecordItemForm>) => {
    setRecordItems((prev) => prev.map((r, i) => (i === idx ? { ...r, ...patch } : r)))
  }

  const removeRecordItem = (idx: number) => {
    setRecordItems((prev) => prev.filter((_, i) => i !== idx))
  }

  const submit = async () => {
    setSaving(true)
    try {
      if (editing) {
        const row = recordItems[0]
        await api.update('/health/checkup', editing.id, {
          check_date: checkDate,
          item_name: row.item_name,
          value: row.value === '' ? null : Number(row.value),
          unit: row.unit === '' ? null : row.unit,
          ref_low: row.ref_low ?? null,
          ref_high: row.ref_high ?? null,
          reference_range: row.reference_range === '' ? null : row.reference_range,
          result: (row.value !== '' && judge(row.value, row.ref_low, row.ref_high)) || null,
        })
      } else {
        const valid = recordItems.filter((r) => r.value !== '')
        for (const r of valid) {
          await api.create('/health/checkup', {
            check_date: checkDate,
            item_name: r.item_name,
            value: Number(r.value),
            unit: r.unit === '' ? null : r.unit,
            ref_low: r.ref_low ?? null,
            ref_high: r.ref_high ?? null,
            reference_range: r.reference_range === '' ? null : r.reference_range,
            result: judge(r.value, r.ref_low, r.ref_high) || null,
          })
        }
      }
      setDialogOpen(false)
      setPage(1)
      await load()
      setRefresh((v) => v + 1)
      toast.success(editing ? '体检记录已更新' : '体检记录已添加')
    } catch (e) {
      toast.error(editing ? '更新失败' : '添加失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSaving(false)
    }
  }

  const remove = async (row: CheckupRecord) => {
    if (!(await confirm())) return
    try {
      await api.remove('/health/checkup', row.id)
      if (items.length === 1 && page > 1) setPage(page - 1)
      else await load()
      setRefresh((v) => v + 1)
      toast.success('体检记录已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  // ---- 单指标模板 ----
  const openTemplateDialog = () => {
    setTemplateDialogOpen(true)
  }
  const openTemplateCreate = () => {
    setEditingTemplate(null)
    setTplForm({ item_name: '', category: '', unit: '', ref_low: '', ref_high: '' })
    setTemplateFormOpen(true)
  }
  const openTemplateEdit = (t: Template) => {
    setEditingTemplate(t)
    setTplForm({
      item_name: t.item_name,
      category: t.category ?? '',
      unit: t.unit ?? '',
      ref_low: String(t.ref_low ?? ''),
      ref_high: String(t.ref_high ?? ''),
    })
    setTemplateFormOpen(true)
  }
  const setTpl = (key: keyof typeof tplForm, value: string) => setTplForm((f) => ({ ...f, [key]: value }))
  const saveTemplate = async () => {
    if (!tplForm.item_name.trim()) return
    const num = (v: string) => (v === '' ? null : Number(v))
    const payload = {
      item_name: tplForm.item_name.trim(),
      category: tplForm.category === '' ? null : tplForm.category,
      unit: tplForm.unit === '' ? null : tplForm.unit,
      ref_low: num(tplForm.ref_low),
      ref_high: num(tplForm.ref_high),
    }
    setSavingTemplate(true)
    try {
      if (editingTemplate) await api.update('/health/checkup/templates', editingTemplate.id, payload)
      else await api.create('/health/checkup/templates', payload)
      setTemplateFormOpen(false)
      await loadTemplates()
      toast.success(editingTemplate ? '模板已更新' : '模板已添加')
    } catch (e) {
      toast.error('模板保存失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSavingTemplate(false)
    }
  }
  const removeTemplate = async (t: Template) => {
    if (!(await confirm({ title: '确认删除模板', description: `确定删除指标模板「${t.item_name}」吗？` }))) return
    try {
      await api.remove('/health/checkup/templates', t.id)
      await loadTemplates()
      toast.success('模板已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  // ---- 组合模板（套餐） ----
  const openPanelCreate = () => {
    setEditingPanel(null)
    setPanelName('')
    setPanelNote('')
    setPanelItems([])
    setPanelFormOpen(true)
  }
  const openPanelEdit = (p: Panel) => {
    setEditingPanel(p)
    setPanelName(p.panel_name)
    setPanelNote(p.note ?? '')
    setPanelItems(p.items.map((it) => ({ ...it })))
    setPanelFormOpen(true)
  }
  const setPanelItem = (idx: number, patch: Partial<PanelItem>) => {
    setPanelItems((prev) => prev.map((it, i) => (i === idx ? { ...it, ...patch } : it)))
  }
  const addPanelItem = () => {
    setPanelItems((prev) => [...prev, { item_name: '' }])
  }
  const removePanelItem = (idx: number) => {
    setPanelItems((prev) => prev.filter((_, i) => i !== idx))
  }
  const savePanel = async () => {
    if (!panelName.trim()) return
    const valid = panelItems
      .filter((it) => it.item_name.trim())
      .map((it) => ({
        item_name: it.item_name.trim(),
        unit: it.unit || null,
        ref_low: it.ref_low ?? null,
        ref_high: it.ref_high ?? null,
        reference_range: it.reference_range ?? fmtRange(it.ref_low ?? null, it.ref_high ?? null),
      }))
    setSavingPanel(true)
    try {
      const payload = { panel_name: panelName.trim(), note: panelNote || null, items: valid }
      if (editingPanel) await api.put('/health/checkup/panels/' + editingPanel.id, payload)
      else await api.post('/health/checkup/panels', payload)
      setPanelFormOpen(false)
      await loadPanels()
      toast.success(editingPanel ? '组合已更新' : '组合已添加')
    } catch (e) {
      toast.error('组合保存失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    } finally {
      setSavingPanel(false)
    }
  }
  const removePanel = async (p: Panel) => {
    if (!(await confirm({ title: '确认删除组合', description: `确定删除组合「${p.panel_name}」吗？` }))) return
    try {
      await api.remove('/health/checkup/panels', p.id)
      await loadPanels()
      toast.success('组合已删除')
    } catch (e) {
      toast.error('删除失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }

  const sc = stats?.status_counts
  const selectableTemplates = templates.filter((t) => t.item_name)
  const mergedPanelOptions = [
    ...presets.map((p, i) => ({ key: `preset-${i}`, panel_name: p.panel_name, items: p.items, builtIn: true as const })),
    ...panels.map((p) => ({ key: `panel-${p.id}`, panel_name: p.panel_name, items: p.items, builtIn: false as const })),
  ]

  // 指标概览：异常优先排序，支持按状态筛选
  const overviewItems = useMemo(() => {
    return [...(stats?.items ?? [])].sort((a, b) => {
      const ra = RESULT_RANK[a.latest?.result ?? ''] ?? 3
      const rb = RESULT_RANK[b.latest?.result ?? ''] ?? 3
      if (ra !== rb) return ra - rb
      return a.item_name.localeCompare(b.item_name, 'zh-Hans-CN')
    })
  }, [stats])

  const filteredOverview = overviewItems.filter((it) => {
    if (overviewFilter === 'all') return true
    const r = it.latest?.result
    if (overviewFilter === 'abnormal') return r === 'high' || r === 'low'
    return r === 'normal'
  })

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">体检指标</h1>
          <p className="text-sm text-muted-foreground">使用组合模板或自由选择指标批量录入，依据参考范围自动判断正常/异常。</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <StatsPeriodPicker
            value={days}
            onChange={(d) => {
              setDays(d)
              setGlobalStatsDays(d)
            }}
          />
          <Button variant="outline" onClick={openTemplateDialog}>
            <Library /> 模板库({templates.length})
          </Button>
          <Button onClick={openCreate}>
            <Plus /> 新增体检记录
          </Button>
        </div>
      </section>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="异常指标"
          value={stats?.abnormal_count ?? 0}
          tone="danger"
          icon={<AlertTriangle className="size-6" />}
          active={overviewFilter === 'abnormal'}
          onClick={() => setOverviewFilter((v) => (v === 'abnormal' ? 'all' : 'abnormal'))}
        />
        <StatCard
          label="正常"
          value={sc?.normal ?? 0}
          tone="success"
          icon={<CheckCircle2 className="size-6" />}
          active={overviewFilter === 'normal'}
          onClick={() => setOverviewFilter((v) => (v === 'normal' ? 'all' : 'normal'))}
        />
        <StatCard
          label="偏高"
          value={sc?.high ?? 0}
          tone="danger"
          icon={<ArrowUpRight className="size-6" />}
        />
        <StatCard
          label="偏低"
          value={sc?.low ?? 0}
          tone="warn"
          icon={<ArrowDownRight className="size-6" />}
        />
      </div>

      <Card>
        <CardContent className="py-4">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Activity className="size-4 text-muted-foreground" />
              <span className="text-sm font-medium">指标概览</span>
              <span className="text-xs text-muted-foreground">共 {overviewItems.length} 项 · 异常优先</span>
            </div>
            <div className="flex w-fit gap-1 rounded-lg border bg-muted/40 p-1">
              {OVERVIEW_FILTERS.map((f) => (
                <button
                  key={f.key}
                  type="button"
                  onClick={() => setOverviewFilter(f.key)}
                  className={`rounded-md px-3 py-1 text-xs transition-colors ${
                    overviewFilter === f.key
                      ? 'bg-background font-medium shadow-sm'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>
          {filteredOverview.length === 0 ? (
            <p className="rounded-lg border border-dashed py-8 text-center text-sm text-muted-foreground">
              {overviewItems.length === 0 ? '暂无体检数据，点击"新增体检记录"开始录入。' : '当前筛选下暂无指标。'}
            </p>
          ) : (
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {filteredOverview.map((item) => (
                <IndicatorCard key={item.item_name} item={item} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          <div className="flex items-center justify-between px-4 pt-4 pb-2">
            <div className="text-sm font-medium">检查明细</div>
            <div className="text-xs text-muted-foreground">共 {total} 条记录</div>
          </div>
          <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>检查日期</TableHead>
                <TableHead>指标</TableHead>
                <TableHead>数值</TableHead>
                <TableHead>单位</TableHead>
                <TableHead>参考范围</TableHead>
                <TableHead>结果</TableHead>
                <TableHead className="w-24 text-right">操作</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody className={`transition-opacity duration-200 ${loading && items.length > 0 ? 'pointer-events-none opacity-60' : ''}`}>
              {items.length === 0 ? (
                loading ? (
                  <TableRow>
                    <TableCell colSpan={7} className="h-24 text-center text-muted-foreground">
                      <Loader2 className="mx-auto size-5 animate-spin" />
                    </TableCell>
                  </TableRow>
                ) : (
                  <TableRow>
                    <TableCell colSpan={7} className="h-24 text-center text-muted-foreground">
                      暂无记录，点击"新增体检记录"添加第一条数据
                    </TableCell>
                  </TableRow>
                )
              ) : (
                items.map((row) => (
                  <TableRow key={row.id}>
                    <TableCell>{row.check_date}</TableCell>
                    <TableCell>{row.item_name}</TableCell>
                    <TableCell>{row.value != null ? row.value : '—'}</TableCell>
                    <TableCell>{row.unit ?? '—'}</TableCell>
                    <TableCell>{row.reference_range ?? '—'}</TableCell>
                    <TableCell>
                      {row.result ? (
                        <Badge className={resultMeta[row.result]?.className}>
                          {resultMeta[row.result]?.label ?? row.result}
                        </Badge>
                      ) : (
                        '—'
                      )}
                    </TableCell>
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
          </div>
        </CardContent>
      </Card>

      <PaginationBar page={page} totalPages={totalPages} total={total} onPageChange={setPage} />

      {/* 新增/编辑体检记录：支持套餐批量录入与自由组合 */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>{editing ? '编辑体检记录' : '新增体检记录'}</DialogTitle>
            <DialogDescription>
              选择组合（血常规/肝肾功能等）一键带入多个指标，或自由勾选单个指标，批量录入后自动判断结果。
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>
                检查日期 <span className="text-destructive">*</span>
              </Label>
              <DatePicker value={checkDate} onChange={(v) => setCheckDate(v)} />
            </div>

            {!editing && (
              <>
                <div className="space-y-2">
                  <Label>选择组合（套餐）</Label>
                  <Select onValueChange={(v) => {
                    const opt = mergedPanelOptions.find((o) => o.key === v)
                    if (opt) applyPanel(opt)
                  }}>
                    <SelectTrigger>
                      <SelectValue placeholder="点击选择组合，自动带入多个指标" />
                    </SelectTrigger>
                    <SelectContent>
                      {mergedPanelOptions.length === 0 && (
                        <div className="px-2 py-1.5 text-sm text-muted-foreground">暂无组合，可在「模板库」中添加</div>
                      )}
                      {mergedPanelOptions.map((o) => (
                        <SelectItem key={o.key} value={o.key}>
                          {o.builtIn ? `[内置] ${o.panel_name}` : o.panel_name}
                          <span className="text-muted-foreground">（{o.items.length} 项）</span>
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label>自由勾选指标（可多选）</Label>
                  {selectableTemplates.length === 0 ? (
                    <p className="text-sm text-muted-foreground">暂无单指标模板，可在「模板库」中添加或直接在下方手动录入。</p>
                  ) : (
                    <div className="flex flex-wrap gap-1.5">
                      {selectableTemplates.map((t) => {
                        const active = recordItems.some((r) => r.item_name === t.item_name)
                        return (
                          <button
                            key={t.id}
                            type="button"
                            onClick={() => toggleTemplate(t)}
                            className={`rounded-full border px-2.5 py-1 text-xs transition-colors ${
                              active
                                ? 'border-primary bg-primary/10 text-primary'
                                : 'hover:border-foreground/25 hover:bg-muted/50'
                            }`}
                          >
                            {t.item_name}
                          </button>
                        )
                      })}
                    </div>
                  )}
                </div>
              </>
            )}

            <div className="space-y-2">
              <Label>
                待录入指标 <span className="text-destructive">*</span>
                <span className="ml-2 text-xs font-normal text-muted-foreground">
                  {recordItems.length} 项{editing ? '' : '（未填数值的自动跳过）'}
                </span>
              </Label>
              {recordItems.length === 0 ? (
                <p className="rounded-lg border border-dashed py-6 text-center text-sm text-muted-foreground">
                  请选择组合或勾选指标，开始批量录入
                </p>
              ) : (
                <div className="space-y-2">
                  {recordItems.map((r, idx) => (
                    <div key={r.item_name + idx} className="flex items-start gap-2 rounded-lg border p-2.5">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <span className="truncate text-sm font-medium">{r.item_name}</span>
                          {!editing && (
                            <button
                              type="button"
                              className="text-muted-foreground hover:text-destructive"
                              onClick={() => removeRecordItem(idx)}
                            >
                              <X className="size-4" />
                            </button>
                          )}
                        </div>
                        <div className="mt-1.5 flex items-center gap-2">
                          <Input
                            type="number"
                            step="0.01"
                            value={r.value}
                            placeholder="数值"
                            onChange={(e) => updateRecordItem(idx, { value: e.target.value })}
                            className="h-8 w-28"
                            disabled={!!editing}
                          />
                          {r.unit && <span className="text-xs text-muted-foreground">{r.unit}</span>}
                          {r.reference_range && (
                            <span className="text-xs text-muted-foreground">参考 {r.reference_range}</span>
                          )}
                          {r.value !== '' && judge(r.value, r.ref_low, r.ref_high) && (
                            <Badge className={resultMeta[judge(r.value, r.ref_low, r.ref_high)]?.className}>
                              {resultMeta[judge(r.value, r.ref_low, r.ref_high)]?.label}
                            </Badge>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>
              取消
            </Button>
            <Button
              onClick={submit}
              disabled={
                saving ||
                !checkDate ||
                recordItems.length === 0 ||
                (!editing && recordItems.every((r) => r.value === ''))
              }
            >
              {saving && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 模板库：单指标模板 + 组合模板 */}
      <Dialog open={templateDialogOpen} onOpenChange={setTemplateDialogOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>指标模板库</DialogTitle>
            <DialogDescription>
              单指标模板用于自由勾选；组合模板（套餐）可一次带入多个指标（如血常规、肝肾功能）。
            </DialogDescription>
          </DialogHeader>
          <div className="flex w-fit gap-1 rounded-lg border bg-muted/40 p-1">
            {(
              [
                ['single', '单指标'],
                ['panel', '组合套餐'],
              ] as const
            ).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setLibTab(key)}
                className={`rounded-md px-3 py-1 text-sm transition-colors ${
                  libTab === key ? 'bg-background font-medium shadow-sm' : 'text-muted-foreground hover:text-foreground'
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          {libTab === 'single' ? (
            <div className="max-h-64 space-y-2 overflow-y-auto pr-1">
              {templates.length === 0 ? (
                <div className="py-8 text-center text-sm text-muted-foreground">暂无单指标模板，点击"新增指标"开始添加。</div>
              ) : (
                templates.map((t) => (
                  <div key={t.id} className="flex items-center justify-between rounded-lg border p-2.5">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="truncate text-sm font-medium">{t.item_name}</span>
                        {t.category && <Badge variant="secondary">{t.category}</Badge>}
                      </div>
                      <div className="mt-0.5 text-xs text-muted-foreground">
                        参考范围 {t.ref_low != null || t.ref_high != null ? fmtRange(t.ref_low ?? null, t.ref_high ?? null) : '—'}
                        {t.unit ? ` · ${t.unit}` : ''}
                      </div>
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                      <Button variant="ghost" size="icon" onClick={() => openTemplateEdit(t)}>
                        <Pencil />
                      </Button>
                      <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removeTemplate(t)}>
                        <Trash2 />
                      </Button>
                    </div>
                  </div>
                ))
              )}
            </div>
          ) : (
            <div className="max-h-64 space-y-2 overflow-y-auto pr-1">
              {panels.length === 0 ? (
                <div className="py-8 text-center text-sm text-muted-foreground">
                  暂无组合模板。可从右下角内置套餐参考，点击"新增组合"自由编排多个指标。
                </div>
              ) : (
                panels.map((p) => (
                  <div key={p.id} className="space-y-1 rounded-lg border p-2.5">
                    <div className="flex items-center justify-between">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="truncate text-sm font-medium">{p.panel_name}</span>
                          <Badge variant="secondary">{p.items.length} 项</Badge>
                        </div>
                        {p.note && <div className="mt-0.5 text-xs text-muted-foreground">{p.note}</div>}
                      </div>
                      <div className="flex shrink-0 items-center gap-1">
                        <Button variant="ghost" size="icon" onClick={() => openPanelEdit(p)}>
                          <Pencil />
                        </Button>
                        <Button variant="ghost" size="icon" className="text-destructive" onClick={() => removePanel(p)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {p.items.slice(0, 6).map((it) => (
                        <span key={it.item_name} className="rounded bg-muted px-1.5 py-0.5 text-xs text-muted-foreground">
                          {it.item_name}
                        </span>
                      ))}
                      {p.items.length > 6 && (
                        <span className="text-xs text-muted-foreground">+{p.items.length - 6}</span>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          <div className="space-y-2">
            <div className="text-sm font-medium text-muted-foreground">内置参考（血常规 / 肝肾功能 / 血脂 / 血糖）</div>
            <div className="flex max-h-40 flex-col gap-1 overflow-y-auto pr-1">
              {presets.map((p) => (
                <div key={p.panel_name} className="flex items-center justify-between rounded-lg border px-2.5 py-2 text-sm">
                  <span className="font-medium">{p.panel_name}</span>
                  <span className="text-xs text-muted-foreground">{p.items.map((i) => i.item_name).join('、')}</span>
                </div>
              ))}
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setTemplateDialogOpen(false)}>
              关闭
            </Button>
            {libTab === 'single' ? (
              <Button onClick={openTemplateCreate}>
                <Plus /> 新增指标
              </Button>
            ) : (
              <Button onClick={openPanelCreate}>
                <Plus /> 新增组合
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 新增/编辑单指标模板 */}
      <Dialog open={templateFormOpen} onOpenChange={setTemplateFormOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editingTemplate ? '编辑指标模板' : '新增指标模板'}</DialogTitle>
            <DialogDescription>配置体检指标的类别、单位与参考范围，用于快速录入。</DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2 col-span-2">
              <Label>
                指标名称 <span className="text-destructive">*</span>
              </Label>
              <Input value={tplForm.item_name} onChange={(e) => setTpl('item_name', e.target.value)} placeholder="如：空腹血糖" />
            </div>
            <div className="space-y-2">
              <Label>类别</Label>
              <Input value={tplForm.category} onChange={(e) => setTpl('category', e.target.value)} placeholder="如：血糖" />
            </div>
            <div className="space-y-2">
              <Label>单位</Label>
              <Input value={tplForm.unit} onChange={(e) => setTpl('unit', e.target.value)} placeholder="如：mmol/L" />
            </div>
            <div className="space-y-2">
              <Label>参考下限</Label>
              <Input type="number" step="0.01" value={tplForm.ref_low} onChange={(e) => setTpl('ref_low', e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>参考上限</Label>
              <Input type="number" step="0.01" value={tplForm.ref_high} onChange={(e) => setTpl('ref_high', e.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setTemplateFormOpen(false)}>
              取消
            </Button>
            <Button onClick={saveTemplate} disabled={savingTemplate || !tplForm.item_name.trim()}>
              {savingTemplate && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 新增/编辑组合模板（套餐） */}
      <Dialog open={panelFormOpen} onOpenChange={setPanelFormOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>{editingPanel ? '编辑组合模板' : '新增组合模板'}</DialogTitle>
            <DialogDescription>
              给组合命名，并编排它包含的多个体检指标（如血常规、肝肾功能）。可随手从上方单指标模板与内置套餐组合编排。
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>
                  组合名称 <span className="text-destructive">*</span>
                </Label>
                <Input value={panelName} onChange={(e) => setPanelName(e.target.value)} placeholder="如：血常规、肝肾功能" />
              </div>
              <div className="space-y-2">
                <Label>说明</Label>
                <Input value={panelNote} onChange={(e) => setPanelNote(e.target.value)} placeholder="可选" />
              </div>
            </div>

            <div className="space-y-2">
              <Label>快速添加单指标模板</Label>
              {templates.length === 0 ? (
                <p className="text-sm text-muted-foreground">暂无单指标模板，可直接在下方手动添加。</p>
              ) : (
                <Select onValueChange={(v) => {
                  const id = Number(v)
                  const t = templates.find((x) => x.id === id)
                  if (t && !panelItems.some((it) => it.item_name === t.item_name)) {
                    setPanelItems((prev) => [
                      ...prev,
                      {
                        item_name: t.item_name,
                        unit: t.unit ?? '',
                        ref_low: t.ref_low ?? null,
                        ref_high: t.ref_high ?? null,
                        reference_range: fmtRange(t.ref_low ?? null, t.ref_high ?? null),
                      },
                    ])
                  }
                }}>
                  <SelectTrigger>
                    <SelectValue placeholder="选择模板加入组合" />
                  </SelectTrigger>
                  <SelectContent>
                    {templates.map((t) => (
                      <SelectItem key={t.id} value={String(t.id)}>
                        {t.category ? `[${t.category}] ` : ''}
                        {t.item_name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label>
                  组合指标（{panelItems.length} 项）
                </Label>
                <Button variant="outline" size="sm" onClick={addPanelItem}>
                  <Plus /> 手动添加
                </Button>
              </div>
              {panelItems.length === 0 ? (
                <p className="rounded-lg border border-dashed py-6 text-center text-sm text-muted-foreground">
                  通过上方模板选择或"手动添加"来编排组合指标
                </p>
              ) : (
                <div className="max-h-56 space-y-2 overflow-y-auto pr-1">
                  {panelItems.map((it, idx) => (
                    <div key={idx} className="flex items-center gap-2 rounded-lg border p-2">
                      <button type="button" className="text-muted-foreground hover:text-destructive" onClick={() => removePanelItem(idx)}>
                        <X className="size-4" />
                      </button>
                      <Input
                        value={it.item_name}
                        placeholder="指标名"
                        onChange={(e) => setPanelItem(idx, { item_name: e.target.value })}
                        className="h-8 flex-1"
                      />
                      <Input
                        value={it.unit ?? ''}
                        placeholder="单位"
                        onChange={(e) => setPanelItem(idx, { unit: e.target.value })}
                        className="h-8 w-24"
                      />
                      <Input
                        type="number"
                        step="0.01"
                        value={it.ref_low ?? ''}
                        placeholder="下限"
                        onChange={(e) => setPanelItem(idx, { ref_low: e.target.value === '' ? null : Number(e.target.value) })}
                        className="h-8 w-20"
                      />
                      <Input
                        type="number"
                        step="0.01"
                        value={it.ref_high ?? ''}
                        placeholder="上限"
                        onChange={(e) => setPanelItem(idx, { ref_high: e.target.value === '' ? null : Number(e.target.value) })}
                        className="h-8 w-20"
                      />
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPanelFormOpen(false)}>
              取消
            </Button>
            <Button
              onClick={savePanel}
              disabled={savingPanel || !panelName.trim() || panelItems.length === 0}
            >
              {savingPanel && <Loader2 className="animate-spin" />}
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}