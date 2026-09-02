import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Link } from 'react-router-dom'

export function NotFoundPage() {
  return (
    <div className="flex flex-1 items-center justify-center">
      <Card className="w-full max-w-sm">
        <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
          <p className="font-heading text-5xl font-semibold">404</p>
          <p className="text-sm text-muted-foreground">
            页面不存在或已被移除
          </p>
          <Button asChild>
            <Link to="/dashboard">返回工作台</Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
