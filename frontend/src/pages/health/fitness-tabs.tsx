import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Activity, Dumbbell, Scale, Utensils } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { FitnessDashboardPage } from './fitness-dashboard'
import { DietPage } from './diet'
import { FitnessPage } from './fitness'
import { BodyPage } from './body'

const TABS = [
  { key: 'dashboard', label: '数据看板', icon: Activity },
  { key: 'diet', label: '饮食记录', icon: Utensils },
  { key: 'exercise', label: '运动记录', icon: Dumbbell },
  { key: 'body', label: '体重记录', icon: Scale },
] as const

type TabKey = (typeof TABS)[number]['key']

export function FitnessTabsPage() {
  const [searchParams] = useSearchParams()
  const initTab = (searchParams.get('tab') as TabKey) || 'dashboard'
  const [tab, setTab] = useState<TabKey>(initTab)

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">健身运动</h1>
        <p className="text-sm text-muted-foreground">
          数据看板、饮食记录、运动记录与体重记录集中管理。
        </p>
      </section>
      <div className="flex gap-1 rounded-lg bg-muted p-1">
        {TABS.map((t) => {
          const Icon = t.icon
          return (
            <Button
              key={t.key}
              variant={tab === t.key ? 'default' : 'ghost'}
              className="flex-1"
              onClick={() => setTab(t.key)}
            >
              <Icon className="size-4" />
              {t.label}
            </Button>
          )
        })}
      </div>

      {tab === 'dashboard' && <FitnessDashboardPage />}
      {tab === 'diet' && <DietPage />}
      {tab === 'exercise' && <FitnessPage />}
      {tab === 'body' && <BodyPage />}
    </div>
  )
}