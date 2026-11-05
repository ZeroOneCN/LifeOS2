import { useEffect, useState } from 'react'
import { Bookmark, HandCoins, Landmark, Wallet } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { api } from '@/lib/api'
import { formatCny, formatMoney } from '@/lib/format'

import { DebtTab } from './debt-tab'
import { InvestTab } from './invest-tab'
import { MemoTab } from './memo-tab'
import { RateTab } from './rate-tab'
import type { Currency, Fmt } from './shared'

type TabKey = 'debt' | 'invest' | 'memo' | 'rate'

export function DebtsPage() {
  const TAB_KEY = 'lifeos_debts_tab'
  const [tab, setTabState] = useState<TabKey>(() => {
    const saved = localStorage.getItem(TAB_KEY)
    return saved === 'debt' || saved === 'invest' || saved === 'memo' || saved === 'rate' ? saved : 'debt'
  })
  const setTab = (t: TabKey) => {
    setTabState(t)
    localStorage.setItem(TAB_KEY, t)
  }
  const [currencies, setCurrencies] = useState<Currency[]>([])
  const [currency, setCurrency] = useState<Currency | null>(null)

  // 显示币种持久化到本地，避免切换页面/刷新后重置
  const DISPLAY_CURRENCY_KEY = 'lifeos_display_currency'
  const setDisplayCurrency = (c: Currency | null) => {
    setCurrency(c)
    if (c) localStorage.setItem(DISPLAY_CURRENCY_KEY, c.currency)
  }

  useEffect(() => {
    api.query<Currency[]>('/finance/currencies').then((list) => {
      setCurrencies(list)
      const cny = list.find((c) => c.currency === 'CNY')
      const saved = localStorage.getItem(DISPLAY_CURRENCY_KEY)
      setCurrency(list.find((c) => c.currency === saved) ?? cny ?? list[0] ?? null)
    }).catch(() => {})
  }, [])

  /** 按展示币种换算后格式化为金额；无汇率或本位币时回退人民币格式。 */
  const fmtMoney: Fmt = (cny: number) => {
    const r = currency
    if (!r || !r.rate_to_cny) return formatCny(cny)
    return formatMoney(cny / r.rate_to_cny, r.symbol ?? '')
  }

  const tabs: { key: TabKey; label: string; icon: typeof Wallet }[] = [
    { key: 'debt', label: '民间借贷', icon: HandCoins },
    { key: 'invest', label: '投资记账', icon: Landmark },
    { key: 'memo', label: '备忘录', icon: Bookmark },
    { key: 'rate', label: '汇率设置', icon: Wallet },
  ]

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-1">
          <h1 className="font-heading text-2xl font-semibold tracking-tight">债务管理</h1>
          <p className="text-sm text-muted-foreground">
            管理民间借贷与网贷同步，并维护投资记账与汇率换算。
          </p>
        </div>
        {currency && <Badge variant="outline" className="text-base">显示：{currency.name ?? currency.currency} {currency.symbol ?? ''}</Badge>}
      </section>

      <div className="flex gap-1 overflow-x-auto rounded-lg bg-muted p-1">
        {tabs.map((t) => (
          <Button key={t.key} variant={tab === t.key ? 'default' : 'ghost'} className="min-w-max flex-1 whitespace-nowrap" onClick={() => setTab(t.key)}>
            <t.icon className="size-4" /> {t.label}
          </Button>
        ))}
      </div>

      {tab === 'debt' && <DebtTab fmtMoney={fmtMoney} />}
      {tab === 'invest' && <InvestTab />}
      {tab === 'memo' && <MemoTab />}
      {tab === 'rate' && <RateTab currencies={currencies} setCurrencies={setCurrencies} currency={currency} setCurrency={setDisplayCurrency} />}
    </div>
  )
}
