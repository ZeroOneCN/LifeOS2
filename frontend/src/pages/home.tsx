import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { navigation } from '@/config/navigation'

const centers = navigation.filter((s) => s.collapsible)

export function HomePage() {
  return (
    <div className="flex flex-col gap-6">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">
          系统首页
        </h1>
        <p className="text-sm text-muted-foreground">
          欢迎回来，选择功能区快速开始。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {centers.map((center) => (
          <Link
            key={center.title}
            to={center.children[0].url}
            className="h-full"
          >
            <Card className="h-full transition-colors hover:bg-muted">
              <CardHeader>
                <center.icon className="size-5 text-muted-foreground" />
                <CardTitle className="mt-2">{center.title}</CardTitle>
                <CardDescription>
                  {center.children.map((item) => item.title).join(' · ')}
                </CardDescription>
              </CardHeader>
            </Card>
          </Link>
        ))}
      </section>

      <BackendStatus />
    </div>
  )
}

function BackendStatus() {
  const [status, setStatus] = useState<'loading' | 'ok' | 'error'>('loading')

  useEffect(() => {
    fetch('/api/v1/health')
      .then((res) => res.json())
      .then((data) => setStatus(data.status === 'ok' ? 'ok' : 'error'))
      .catch(() => setStatus('error'))
  }, [])

  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle className="text-sm">后端连接</CardTitle>
        <CardDescription>FastAPI /api/v1/health</CardDescription>
      </CardHeader>
      <CardContent>
        {status === 'loading' && <span className="text-sm">检测中…</span>}
        {status === 'ok' && (
          <span className="text-sm text-green-600">● 后端已连接</span>
        )}
        {status === 'error' && (
          <span className="text-sm text-destructive">
            ● 后端未响应，请先启动 backend
          </span>
        )}
      </CardContent>
    </Card>
  )
}
