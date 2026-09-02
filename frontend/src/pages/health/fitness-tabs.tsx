import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Activity, Dumbbell, Scale, Utensils } from 'lucide-react'

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
      <div className="flex w-fit gap-1 rounded-lg border bg-muted/40 p-1">
        {TABS.map((t) => {
          const Icon = t.icon
          return (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm transition-colors ${
                tab === t.key
                  ? 'bg-background font-medium shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              <Icon className="size-4" />
              {t.label}
            </button>
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