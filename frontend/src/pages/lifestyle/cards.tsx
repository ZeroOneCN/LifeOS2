import { useEffect, useState, type ReactNode } from 'react'
import { BadgeCheck, Banknote, CreditCard, Landmark, ListChecks, Package, Smartphone } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { BarChartCard, useStats } from '@/components/health/charts'
import {
  RecordManager,
  type ColumnDef,
  type FieldDef,
} from '@/components/health/record-manager'
import { api, type PageResult } from '@/lib/api'

// ------------------------------------------------------------------ 类型
type PhoneCard = {
  id: number
  phone_number: string
  operator: string
  region?: string
  balance?: number
  monthly_fee?: number
  bill_day?: number
  data_plan?: string
  call_plan?: string
  sms_plan?: string
  open_date?: string
  billing_type: 'monthly' | 'one_time' | 'yearly'
  bill_paid_this_month: boolean
  status: 'active' | 'frozen' | 'expired' | 'disabled'
  note?: string
}

type BankCard = {
  id: number
  card_name: string
  card_holder?: string
  bank: string
  card_category: 'credit' | 'debit'
  card_form: 'physical' | 'virtual'
  card_number?: string
  balance?: number
  credit_limit?: number
  billing_day?: number
  due_day?: number
  expire_date?: string
  status: 'active' | 'frozen' | 'expired' | 'closed'
  note?: string
}

type Carrier = { id: number; name: string; website?: string; contact?: string; note?: string }
type CardBill = {
  id: number
  phone_card_id: number
  bill_month: string
  amount: number
  deducted_date?: string
  paid: boolean
  note?: string
}

type PhoneStats = {
  total: number
  active: number
  monthly_fee_total: number
  balance_total: number
  month_deduct: number
  month_deduct_count: number
  unpaid_this_month: number
  billing_type: { billing_type: string; count: number }[]
  by_operator: { operator: string; count: number }[]
  by_status: { status: string; count: number }[]
}

type BankStats = {
  total: number
  active: number
  balance_total: number
  credit_total: number
  by_bank: { bank: string; count: number }[]
  by_category: { card_category: string; count: number }[]
  by_status: { status: string; count: number }[]
}

type BillStats = { total: number; month_total: number; by_month: { bill_month: string; amount: number }[] }

type ItemStats = {
  total: number
  in_use: number
  total_value: number
  avg_daily_cost: number
  expiring: number
  expired: number
  by_category: { category: string; count: number }[]
  by_status: { status: string; count: number }[]
  by_source: { source: string; count: number }[]
}

const fmt = (n?: number | null) =>
  `¥${(n ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2 })}`

const TAB_META = [
  { key: 'phone', label: '手机号', icon: Smartphone },
  { key: 'bank', label: '银行卡', icon: Landmark },
  { key: 'carrier', label: '运营商', icon: BadgeCheck },
  { key: 'bill', label: '扣账账单', icon: ListChecks },
  { key: 'analysis', label: '数据分析', icon: CreditCard },
] as const

const operators = ['中国移动', '中国联通', '中国电信', '虚拟运营商']
const bankTypes = [
  { value: 'credit', label: '信用卡' },
  { value: 'debit', label: '储蓄卡' },
]
const cardForms = [
  { value: 'physical', label: '实体卡' },
  { value: 'virtual', label: '虚拟卡' },
]
const billingTypes = [
  { value: 'monthly', label: '按月' },
  { value: 'one_time', label: '一次性' },
  { value: 'yearly', label: '按年保号' },
]
const phoneStatus = [
  { value: 'active', label: '正常' },
  { value: 'frozen', label: '冻结' },
  { value: 'expired', label: '已过期' },
  { value: 'disabled', label: '已销户' },
]
const bankStatus = [
  { value: 'active', label: '正常' },
  { value: 'frozen', label: '冻结' },
  { value: 'expired', label: '已过期' },
  { value: 'closed', label: '已注销' },
]

const phoneFields: FieldDef[] = [
  { key: 'phone_number', label: '号码', type: 'text', required: true },
  {
    key: 'operator',
    label: '运营商',
    type: 'select',
    required: true,
    options: operators.map((o) => ({ value: o, label: o })),
  },
  { key: 'region', label: '归属地', type: 'text', placeholder: '如 广东-深圳' },
  { key: 'balance', label: '余额', type: 'number', step: '0.01', min: 0 },
  { key: 'monthly_fee', label: '月租', type: 'number', step: '0.01', min: 0 },
  { key: 'bill_day', label: '账单日', type: 'number', step: '1', min: 1 },
  { key: 'data_plan', label: '流量套餐', type: 'text', placeholder: '如 30GB' },
  { key: 'call_plan', label: '通话', type: 'text', placeholder: '如 100分钟' },
  { key: 'sms_plan', label: '短信', type: 'text', placeholder: '如 50条' },
  { key: 'open_date', label: '开卡时间', type: 'date' },
  {
    key: 'billing_type',
    label: '付费方式',
    type: 'select',
    options: billingTypes,
  },
  {
    key: 'bill_paid_this_month',
    label: '本月是否已扣账',
    type: 'boolean',
    options: [
      { value: 'false', label: '未扣账' },
      { value: 'true', label: '已扣账' },
    ],
  },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: phoneStatus,
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const phoneColumns: ColumnDef<PhoneCard>[] = [
  {
    key: 'phone_number',
    label: '号码',
    render: (r) => (
      <div>
        <div className="font-medium">{r.phone_number}</div>
        {r.billing_type !== 'monthly' && (
          <Badge className="mt-0.5 bg-slate-100 text-slate-600">
            {billingTypes.find((b) => b.value === r.billing_type)?.label ?? r.billing_type}
          </Badge>
        )}
      </div>
    ),
  },
  { key: 'operator', label: '运营商' },
  { key: 'region', label: '归属地', render: (r) => r.region ?? '—' },
  { key: 'data_plan', label: '流量套餐', render: (r) => r.data_plan ?? '—' },
  {
    key: 'monthly_fee',
    label: '月租',
    render: (r) => (r.monthly_fee != null ? fmt(r.monthly_fee) : '—'),
  },
  { key: 'bill_day', label: '账单日', render: (r) => (r.bill_day ? `${r.bill_day} 日` : '—') },
  { key: 'balance', label: '余额', render: (r) => (r.balance != null ? fmt(r.balance) : '—') },
  {
    key: 'bill_paid_this_month',
    label: '本月扣账',
    render: (r) =>
      r.bill_paid_this_month ? (
        <Badge className="bg-green-100 text-green-700">已扣账</Badge>
      ) : (
        <Badge className="bg-amber-100 text-amber-700">未扣账</Badge>
      ),
  },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={metaClass(r.status)}>
        {phoneStatus.find((s) => s.value === r.status)?.label ?? r.status}
      </Badge>
    ),
  },
]

const bankFields: FieldDef[] = [
  { key: 'card_name', label: '卡片名称', type: 'text', required: true },
  { key: 'card_holder', label: '持卡人', type: 'text' },
  { key: 'bank', label: '银行', type: 'text', required: true, placeholder: '如 招商银行' },
  {
    key: 'card_category',
    label: '卡类型',
    type: 'select',
    options: bankTypes,
  },
  {
    key: 'card_form',
    label: '卡形态',
    type: 'select',
    options: cardForms,
  },
  { key: 'card_number', label: '卡号', type: 'text', placeholder: '可填部分号码' },
  { key: 'balance', label: '余额', type: 'number', step: '0.01', min: 0 },
  { key: 'credit_limit', label: '信用额度', type: 'number', step: '0.01', min: 0 },
  { key: 'billing_day', label: '账单日', type: 'number', step: '1', min: 1 },
  { key: 'due_day', label: '还款日', type: 'number', step: '1', min: 1 },
  { key: 'expire_date', label: '有效期', type: 'date' },
  {
    key: 'status',
    label: '状态',
    type: 'select',
    options: bankStatus,
  },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const bankColumns: ColumnDef<BankCard>[] = [
  { key: 'card_name', label: '名称' },
  {
    key: 'card_category',
    label: '类型',
    render: (r) => (
      <Badge className={r.card_category === 'credit' ? 'bg-amber-100 text-amber-700' : 'bg-emerald-100 text-emerald-700'}>
        {r.card_category === 'credit' ? '信用卡' : '储蓄卡'}
      </Badge>
    ),
  },
  { key: 'bank', label: '银行' },
  { key: 'card_holder', label: '持卡人', render: (r) => r.card_holder ?? '—' },
  { key: 'card_number', label: '卡号', render: (r) => r.card_number ?? '—' },
  { key: 'balance', label: '余额', render: (r) => (r.balance != null ? fmt(r.balance) : '—') },
  { key: 'credit_limit', label: '额度', render: (r) => (r.credit_limit ? fmt(r.credit_limit) : '—') },
  {
    key: 'status',
    label: '状态',
    render: (r) => (
      <Badge className={metaClass(r.status)}>
        {bankStatus.find((s) => s.value === r.status)?.label ?? r.status}
      </Badge>
    ),
  },
]

const carrierFields: FieldDef[] = [
  { key: 'name', label: '平台名称', type: 'text', required: true },
  { key: 'website', label: '官网/链接', type: 'text' },
  { key: 'contact', label: '客服电话', type: 'text' },
  { key: 'note', label: '备注', type: 'textarea', full: true },
]

const carrierColumns: ColumnDef<Carrier>[] = [
  { key: 'name', label: '平台' },
  { key: 'website', label: '官网', render: (r) => r.website ?? '—' },
  { key: 'contact', label: '客服电话', render: (r) => r.contact ?? '—' },
]

function metaClass(status: string): string {
  const map: Record<string, string> = {
    active: 'bg-green-100 text-green-700',
    frozen: 'bg-amber-100 text-amber-700',
    expired: 'bg-red-100 text-red-700',
    disabled: 'bg-gray-100 text-gray-500',
    closed: 'bg-gray-100 text-gray-500',
  }
  return map[status] ?? 'bg-gray-100 text-gray-500'
}

function Tab({ active, onClick, label, icon: Icon }: { active: boolean; onClick: () => void; label: string; icon: typeof Smartphone }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
        active ? 'bg-foreground text-background' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
      }`}
    >
      <Icon className="size-4" />
      {label}
    </button>
  )
}

function StatRow({ children, cols = 4 }: { children: ReactNode; cols?: number }) {
  return <div className={`grid gap-3 sm:grid-cols-2 ${cols === 4 ? 'lg:grid-cols-4' : 'lg:grid-cols-3'}`}>{children}</div>
}

function MiniStat({ icon: Icon, label, value }: { icon?: typeof Smartphone; label: string; value: string }) {
  return (
    <Card>
      <CardContent className="flex items-center justify-between px-4 py-3">
        <div>
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className="mt-0.5 text-lg font-semibold">{value}</div>
        </div>
        {Icon && <Icon className="size-4 text-muted-foreground" />}
      </CardContent>
    </Card>
  )
}

export function CardsPage() {
  const [tab, setTab] = useState<(typeof TAB_META)[number]['key']>('phone')
  const [phoneRefresh, setPhoneRefresh] = useState(0)
  const [billRefresh, setBillRefresh] = useState(0)

  const phoneStats = useStats<PhoneStats>('/lifestyle/phone-cards', 30, phoneRefresh)
  const bankStats = useStats<BankStats>('/lifestyle/bank-cards')
  const billStats = useStats<BillStats>('/lifestyle/card-bills')
  const itemStats = useStats<ItemStats>('/lifestyle/items')

  // 用于扣账账单中显示手机号
  const [phoneMap, setPhoneMap] = useState<Record<number, string>>({})
  useEffect(() => {
    api
      .list<PhoneCard>('/lifestyle/phone-cards', { page: 1, page_size: 100 })
      .then((res: PageResult<PhoneCard>) =>
        setPhoneMap(Object.fromEntries(res.items.map((p) => [p.id, p.phone_number]))),
      )
      .catch(() => setPhoneMap({}))
  }, [phoneRefresh])

  const billFields: FieldDef[] = [
    {
      key: 'phone_card_id',
      label: '手机号',
      type: 'select',
      required: true,
      options: Object.entries(phoneMap).map(([id, num]) => ({ value: id, label: num })),
    },
    { key: 'bill_month', label: '账单月份', type: 'date', required: true },
    { key: 'amount', label: '扣账金额', type: 'number', step: '0.01', min: 0, required: true },
    { key: 'deducted_date', label: '扣账日期', type: 'date' },
    {
      key: 'paid',
      label: '是否扣账成功',
      type: 'boolean',
      options: [
        { value: 'true', label: '成功' },
        { value: 'false', label: '失败/待扣' },
      ],
    },
    { key: 'note', label: '备注', type: 'textarea', full: true },
  ]

  const billColumns: ColumnDef<CardBill>[] = [
    { key: 'phone', label: '手机号', render: (r) => phoneMap[r.phone_card_id] ?? `#${r.phone_card_id}` },
    { key: 'bill_month', label: '账单月份', render: (r) => r.bill_month.slice(0, 7) },
    { key: 'amount', label: '金额', render: (r) => fmt(r.amount) },
    { key: 'deducted_date', label: '扣账日期', render: (r) => r.deducted_date ?? '—' },
    {
      key: 'paid',
      label: '状态',
      render: (r) =>
        r.paid ? (
          <Badge className="bg-green-100 text-green-700">已扣账</Badge>
        ) : (
          <Badge className="bg-amber-100 text-amber-700">待扣</Badge>
        ),
    },
  ]

  const doDeduct = async (id: number) => {
    try {
      const rep = await api.post<PhoneCard>(`/lifestyle/phone-cards/${id}/deduct`)
      toast.success('已记录当月扣账', { description: `${rep.phone_number} · ${fmt(rep.monthly_fee ?? 0)}` })
      setPhoneRefresh((v) => v + 1)
      setBillRefresh((v) => v + 1)
    } catch (e) {
      toast.error('扣账失败', { description: (e as Error).message })
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-center justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">卡片管理</h1>
          <p className="text-sm text-muted-foreground">
            管理手机号卡与银行卡，维护运营商平台设置，自动记录扣账账单并分析。
          </p>
        </div>
      </section>

      <div className="flex flex-wrap gap-1 rounded-xl border bg-muted/40 p-1">
        {TAB_META.map((t) => (
          <Tab key={t.key} active={tab === t.key} label={t.label} icon={t.icon} onClick={() => setTab(t.key)} />
        ))}
      </div>

      {tab === 'phone' && (
        <RecordManager<PhoneCard>
          title=""
          description=""
          apiPath="/lifestyle/phone-cards"
          fields={phoneFields}
          columns={phoneColumns}
          refreshKey={phoneRefresh}
          rowActions={(r) =>
            !r.bill_paid_this_month ? (
              <Button
                variant="ghost"
                size="icon"
                title="记录当月扣账"
                className="text-indigo-600"
                onClick={() => doDeduct(r.id)}
              >
                <Banknote className="size-4" />
              </Button>
            ) : null
          }
          extra={
            phoneStats ? (
              <>
                <StatRow>
                  <MiniStat icon={Smartphone} label="手机卡总数" value={`${phoneStats.total} 张`} />
                  <MiniStat icon={BadgeCheck} label="正常在网" value={`${phoneStats.active} 张`} />
                  <MiniStat icon={Banknote} label="月租合计" value={fmt(phoneStats.monthly_fee_total)} />
                  <MiniStat icon={CreditCard} label="本月扣账" value={`${phoneStats.month_deduct_count} 笔 / ${fmt(phoneStats.month_deduct)}`} />
                  <MiniStat label="余额合计" value={fmt(phoneStats.balance_total)} />
                  <MiniStat label="本月未扣账" value={`${phoneStats.unpaid_this_month} 张`} />
                </StatRow>
                <div className="grid gap-4 lg:grid-cols-3">
                  <BarChartCard title="运营商分布" data={phoneStats.by_operator} xKey="operator" series={[{ key: 'count', name: '数量', color: '#4f46e5' }]} />
                  <BarChartCard title="状态分布" data={phoneStats.by_status} xKey="status" series={[{ key: 'count', name: '数量', color: '#0ea5e9' }]} />
                  <BarChartCard title="付费方式" data={phoneStats.billing_type} xKey="billing_type" series={[{ key: 'count', name: '数量', color: '#f59e0b' }]} />
                </div>
              </>
            ) : null
          }
        />
      )}

      {tab === 'bank' && (
        <RecordManager<BankCard>
          title=""
          description=""
          apiPath="/lifestyle/bank-cards"
          fields={bankFields}
          columns={bankColumns}
          extra={
            bankStats ? (
              <>
                <StatRow>
                  <MiniStat icon={Landmark} label="银行卡总数" value={`${bankStats.total} 张`} />
                  <MiniStat icon={BadgeCheck} label="正常使用" value={`${bankStats.active} 张`} />
                  <MiniStat icon={CreditCard} label="余额合计" value={fmt(bankStats.balance_total)} />
                  <MiniStat icon={Banknote} label="信用卡额度" value={fmt(bankStats.credit_total)} />
                </StatRow>
                <div className="grid gap-4 lg:grid-cols-3">
                  <BarChartCard title="银行分布" data={bankStats.by_bank} xKey="bank" series={[{ key: 'count', name: '数量', color: '#0891b2' }]} />
                  <BarChartCard title="卡类型" data={bankStats.by_category} xKey="card_category" series={[{ key: 'count', name: '数量', color: '#7c3aed' }]} />
                  <BarChartCard title="状态分布" data={bankStats.by_status} xKey="status" series={[{ key: 'count', name: '数量', color: '#059669' }]} />
                </div>
              </>
            ) : null
          }
        />
      )}

      {tab === 'carrier' && (
        <RecordManager<Carrier>
          title=""
          description=""
          apiPath="/lifestyle/carriers"
          fields={carrierFields}
          columns={carrierColumns}
        />
      )}

      {tab === 'bill' && (
        <RecordManager<CardBill>
          title=""
          description=""
          apiPath="/lifestyle/card-bills"
          fields={billFields}
          columns={billColumns}
          refreshKey={billRefresh}
          extra={
            billStats ? (
              <StatRow cols={3}>
                <MiniStat icon={ListChecks} label="本月扣账笔数" value={`${billStats.total} 笔`} />
                <MiniStat icon={CreditCard} label="本月扣账总额" value={fmt(billStats.month_total)} />
                <MiniStat icon={Banknote} label="历史月份数" value={`${billStats.by_month.length} 个月`} />
              </StatRow>
            ) : null
          }
        />
      )}

      {tab === 'analysis' && (
        <div className="flex flex-col gap-6">
          {itemStats && (
            <section className="flex flex-col gap-4">
              <div className="flex items-center gap-2">
                <Package className="size-4 text-indigo-500" />
                <h3 className="text-base font-semibold">物品追踪</h3>
              </div>
              <StatRow>
                <MiniStat icon={Package} label="物品总数" value={`${itemStats.total} 件`} />
                <MiniStat icon={BadgeCheck} label="使用中" value={`${itemStats.in_use} 件`} />
                <MiniStat icon={CreditCard} label="物品总值" value={fmt(itemStats.total_value)} />
                <MiniStat icon={Banknote} label="临期/已过期" value={`${itemStats.expiring} 临期 / ${itemStats.expired} 已过`} />
              </StatRow>
              <div className="grid gap-4 lg:grid-cols-3">
                <BarChartCard title="物品 · 分类" data={itemStats.by_category} xKey="category" series={[{ key: 'count', name: '数量', color: '#6366f1' }]} />
                <BarChartCard title="物品 · 状态" data={itemStats.by_status} xKey="status" series={[{ key: 'count', name: '数量', color: '#0ea5e9' }]} />
                <BarChartCard title="物品 · 来源" data={itemStats.by_source} xKey="source" series={[{ key: 'count', name: '数量', color: '#a855f7' }]} />
              </div>
            </section>
          )}

          {phoneStats && (
            <section className="flex flex-col gap-4">
              <div className="flex items-center gap-2">
                <Smartphone className="size-4 text-blue-500" />
                <h3 className="text-base font-semibold">手机卡</h3>
              </div>
              <div className="grid gap-4 lg:grid-cols-3">
                <BarChartCard title="手机卡 · 运营商" data={phoneStats.by_operator} xKey="operator" series={[{ key: 'count', name: '数量', color: '#4f46e5' }]} />
                <BarChartCard title="手机卡 · 付费方式" data={phoneStats.billing_type} xKey="billing_type" series={[{ key: 'count', name: '数量', color: '#f59e0b' }]} />
                <BarChartCard title="手机卡 · 状态" data={phoneStats.by_status} xKey="status" series={[{ key: 'count', name: '数量', color: '#0ea5e9' }]} />
              </div>
            </section>
          )}

          {bankStats && (
            <section className="flex flex-col gap-4">
              <div className="flex items-center gap-2">
                <Landmark className="size-4 text-cyan-600" />
                <h3 className="text-base font-semibold">银行卡</h3>
              </div>
              <div className="grid gap-4 lg:grid-cols-3">
                <BarChartCard title="银行卡 · 银行" data={bankStats.by_bank} xKey="bank" series={[{ key: 'count', name: '数量', color: '#0891b2' }]} />
                <BarChartCard title="银行卡 · 类型" data={bankStats.by_category} xKey="card_category" series={[{ key: 'count', name: '数量', color: '#7c3aed' }]} />
                <BarChartCard title="银行卡 · 状态" data={bankStats.by_status} xKey="status" series={[{ key: 'count', name: '数量', color: '#059669' }]} />
              </div>
            </section>
          )}

          {billStats && billStats.by_month.length > 0 && (
            <section className="flex flex-col gap-4">
              <div className="flex items-center gap-2">
                <ListChecks className="size-4 text-red-500" />
                <h3 className="text-base font-semibold">扣账账单</h3>
              </div>
              <BarChartCard title="近几个月扣账趋势" data={billStats.by_month} xKey="bill_month" series={[{ key: 'amount', name: '扣账', color: '#dc2626' }]} />
            </section>
          )}
        </div>
      )}
    </div>
  )
}