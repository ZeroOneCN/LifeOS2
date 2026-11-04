import type { LucideIcon } from 'lucide-react'

import { Card, CardContent, CardHeader, CardHeaderActions, CardTitle } from '@/components/ui/card'

export function StatCard({ icon: Icon, label, value, hint, className }: { icon: LucideIcon; label: string; value: string; hint?: string; className?: string }) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground min-w-0 max-w-[55%] truncate">{label}</CardTitle>
        <CardHeaderActions>
          <Icon className={`size-4 ${className ?? 'text-muted-foreground'}`} />
        </CardHeaderActions>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  )
}
