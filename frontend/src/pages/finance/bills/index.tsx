import { useState } from 'react'
import { Banknote, Home, Repeat } from 'lucide-react'

import { PageHeader } from '@/components/page-header'
import { Button } from '@/components/ui/button'

import { HousingTab } from './housing-tab'
import { LoanTab } from './loan-tab'
import { SubscriptionTab } from './subscription-tab'

type TabKey = 'housing' | 'subscription' | 'loan'

/* ---------------- 页面 ---------------- */

export function BillsPage() {
  const TAB_KEY = 'lifeos_bills_tab'
  const [tab, setTabState] = useState<TabKey>(() => {
    const saved = localStorage.getItem(TAB_KEY)
    return saved === 'housing' || saved === 'subscription' || saved === 'loan' ? saved : 'loan'
  })
  const setTab = (t: TabKey) => {
    setTabState(t)
    localStorage.setItem(TAB_KEY, t)
  }
  const tabs: { key: TabKey; label: string; icon: typeof Home }[] = [
    { key: 'loan', label: '网贷借还', icon: Banknote },
    { key: 'housing', label: '房租水电', icon: Home },
    { key: 'subscription', label: '服务订阅', icon: Repeat },
  ]

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="账单管理" description="集中管理住房水电、服务订阅与网贷还款。" />

      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {tabs.map((t) => (
          <Button
            key={t.key}
            variant={tab === t.key ? 'default' : 'ghost'}
            className="flex-1"
            onClick={() => setTab(t.key)}
          >
            <t.icon className="size-4" /> {t.label}
          </Button>
        ))}
      </div>

      {tab === 'loan' && <LoanTab />}
      {tab === 'housing' && <HousingTab />}
      {tab === 'subscription' && <SubscriptionTab />}
    </div>
  )
}
