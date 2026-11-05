import { Construction } from 'lucide-react'

import { PageHeader } from '@/components/page-header'
import { Card, CardContent } from '@/components/ui/card'

type PlaceholderPageProps = {
  title: string
  description: string
}

export function PlaceholderPage({ title, description }: PlaceholderPageProps) {
  return (
    <div className="flex flex-col gap-4">
      <PageHeader title={title} description={description} />

      <Card>
        <CardContent className="flex flex-col items-center justify-center gap-3 py-16 text-center">
          <Construction className="size-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            功能开发中，敬请期待
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
