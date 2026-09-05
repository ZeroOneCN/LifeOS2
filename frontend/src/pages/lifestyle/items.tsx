import { useState } from 'react'
import { Loader2, ShoppingCart } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { BarChartCard, StatsPeriodPicker, getDefaultStatsDays, setGlobalStatsDays, useStats, type StatsDays } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'
import { api } from '@/lib/api'

type ItemRecord = {
  id: number
  item_name: string
  category: string
  location?: string
  status: 'in_use' | 'lost' | 'loaned' | 'recycled'
  purchase_date?: string
  price?: number
  expire_date?: string
  end_date?: string
  source: 'manual' | 'shopping'
  shopping_record_id?: number
  note?: string
}

type ItemStats = {
  total: number
  in_use: number
  total_value: number
  total_usage_days: number
  avg_daily_cost: number
  expiring: number
  expired: number
  by_category: { category: string; count: number }[]
  by_status: { status: string; count: number }[]
  by_source: { source: string; count: number }[]
}

const categories = ['电子', '服饰', '书籍', '家居', '数码配件', '购物', '其他']

const fields: FieldDef[] = [
  { key: 'item_name', label: '物品名称', type: 'text', required: true },
  {
    key: 'category',
    label: '分类',
    type: 'select',
    required: true,
    options: categories.map((c) => ({ value: c, label: c })),
  },
  { key: 'location', label: '存放位置', type: 'text', placeholder: '如 书房 / 卧室' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: [
      { value: 'in_use', label: '使用中' },
      { value: 'loaned', label: '借出' },
      { value: 'lost', label: '丢失' },
      { value: 'recycled', label: '已淘汰' },
    ],
  },
  { key: 'purchase_date', label: '购买日期', type: 'date' },
  { key: 'price', label: '价格', type: 'number', step: '0.01', min: 0 },
  { key: 'expire_date', label: '过期时间', type: 'date' },
  { key: 'end_date', label: '使用结束日期', type: 'date' },
  {
    key: 'source',
    label: '来源',
    type: 'select',
    options: [
      { value: 'manual', label: '手动' },
      { value: 'shopping', label: '购物同步' },
    ],
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const statusMeta: Record<string, { label: string; className: string }> = {
  in_use: { label: '使用中', className: 'bg-green-100 text-green-700' },
  loaned: { label: '借出', className: 'bg-blue-100 text-blue-700' },
  lost: { label: '丢失', className: 'bg-red-100 text-red-700' },
  recycled: { label: '已淘汰', className: 'bg-gray-100 text-gray-500' },
}

function usageDays(r: ItemRecord): number {
  if (!r.purchase_date) return 0
  const end = r.end_date ? new Date(r.end_date) : new Date()
  const start = new Date(r.purchase_date)
  const days = Math.floor((end.getTime() - start.getTime()) / 86400000)
  return days > 0 ? days : 0
}

function dailyCost(r: ItemRecord): number | null {
  const days = usageDays(r)
  if ((r.price ?? 0) > 0 && days > 0) return r.price! / days
  return null
}

const fmt = (n?: number | null) =>
  `¥${(n ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const columns: ColumnDef<ItemRecord>[] = [
  { key: 'item_name', label: '物品' },
  { key: 'category', label: '分类' },
  { key: 'location', label: '位置', render: (r) => r.location ?? '—' },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={statusMeta[r.status]?.className}>{statusMeta[r.status]?.label ?? r.status}</Badge>
    ),
  },
  {
    key: 'source',
    label: '来源',
    render: (r) =>
      r.source === 'shopping' ? (
        <Badge className="bg-purple-100 text-purple-700">购物同步</Badge>
      ) : (
        <Badge className="bg-slate-100 text-slate-600">手动</Badge>
      ),
  },
  {
    key: 'usage_days',
    label: '已用天数',
    render: (r) =>
      r.purchase_date ? `${usageDays(r)} 天${r.end_date ? '（已使用完）' : ''}` : '—',
  },
  {
    key: 'daily_cost',
    label: '日均成本',
    render: (r) => {
      const c = dailyCost(r)
      return c != null ? `¥${c.toFixed(2)}/天` : '—'
    },
  },
  { key: 'expire_date', label: '过期时间', render: (r) => r.expire_date ?? '—' },
  {
    key: 'price',
    label: '价格',
    render: (r) => (r.price != null ? fmt(r.price) : '—'),
  },
]

export function ItemsPage() {
  // refresh 用于同步后重新拉取统计
  const [refresh, setRefresh] = useState(0)
  const [days, setDays] = useState<StatsDays>(getDefaultStatsDays())
  const stats = useStats<ItemStats>('/lifestyle/items', days, refresh)
  const byCategory = stats?.by_category ?? []
  const byStatus = stats?.by_status ?? []
  const bySource = stats?.by_source ?? []

  const [syncing, setSyncing] = useState(false)

  const doSync = async () => {
    if (syncing) return
    setSyncing(true)
    try {
      const res = await api.create<{ created: number; skipped: number }>('/lifestyle/items/sync', {
        record_ids: [],
      })
      toast.success(
        res.created > 0 ? `已同步 ${res.created} 条物品` : '没有可同步的购物记录',
        { description: res.created > 0 ? `跳过 ${res.skipped} 条重复记录` : '购物记录已全部同步过' },
      )
      setRefresh((v) => v + 1)
    } catch (e) {
      toast.error('同步失败', { description: (e as Error).message })
    } finally {
      setSyncing(false)
    }
  }

  const chartStats =
    stats ?? {
      total: 0,
      in_use: 0,
      total_value: 0,
      total_usage_days: 0,
      avg_daily_cost: 0,
      expiring: 0,
      expired: 0,
      by_category: [],
      by_status: [],
      by_source: [],
    }

  return (
    <>
      <RecordManager<ItemRecord>
        title="物品追踪"
        description="登记个人物品，计算使用时长与分摊费用损耗，支持一键从购物记录同步。"
        apiPath="/lifestyle/items"
        fields={fields}
        columns={columns}
        refreshKey={refresh}
        onMutate={() => setRefresh((v) => v + 1)}
        headerExtra={
          <Button variant="outline" onClick={doSync} disabled={syncing}>
            {syncing ? <Loader2 className="size-4 animate-spin" /> : <ShoppingCart className="size-4" />}
            同步购物记录
          </Button>
        }
        extra={
          <>
            <div className="flex justify-end">
              <StatsPeriodPicker
                value={days}
                onChange={(d) => {
                  setDays(d)
                  setGlobalStatsDays(d)
                }}
              />
            </div>
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <MiniStat label="物品总数" value={String(chartStats.total)} />
                <MiniStat label="使用中" value={String(chartStats.in_use)} />
                <MiniStat label="过期/临期" value={`${chartStats.expired} 已过 / ${chartStats.expiring} 临期`} />
                <MiniStat label="日均成本(有效)" value={chartStats.avg_daily_cost ? fmt(chartStats.avg_daily_cost) + '/天' : '—'} />
              </div>
            <div className="grid grid-cols-2 gap-4 xl:grid-cols-3">
              <BarChartCard
                title={`物品分类统计（共 ${stats?.total ?? 0} 件 · 总值 ${stats ? fmt(stats.total_value) : ''}）`}
                data={byCategory}
                xKey="category"
                series={[{ key: 'count', name: '数量', color: '#6366f1' }]}
              />
              <BarChartCard
                title="物品状态分布"
                data={byStatus}
                xKey="status"
                series={[{ key: 'count', name: '数量', color: '#f59e0b' }]}
              />
              <BarChartCard
                title="来源分布"
                data={bySource}
                xKey="source"
                series={[{ key: 'count', name: '数量', color: '#a855f7' }]}
              />
            </div>
          </>
        }
      />
    </>
  )
}

function MiniStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border bg-card px-4 py-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="mt-1 text-lg font-semibold">{value}</div>
    </div>
  )
}