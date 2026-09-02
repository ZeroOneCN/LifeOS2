import { Activity, ShieldCheck, Users } from 'lucide-react'

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

const stats = [
  { title: '用户总数', value: '0', icon: Users },
  { title: '角色数量', value: '0', icon: ShieldCheck },
  { title: '今日活跃', value: '0', icon: Activity },
]

export function DashboardPage() {
  return (
    <div className="flex flex-col gap-6">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">
          工作台
        </h1>
        <p className="text-sm text-muted-foreground">
          欢迎回来，这里是平台概览。
        </p>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        {stats.map((s) => (
          <Card key={s.title}>
            <CardHeader className="flex flex-row items-center justify-between gap-2">
              <CardTitle className="text-sm text-muted-foreground">
                {s.title}
              </CardTitle>
              <s.icon className="size-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-semibold">{s.value}</div>
            </CardContent>
          </Card>
        ))}
      </section>

      <Card>
        <CardHeader>
          <CardTitle>使用说明</CardTitle>
          <CardDescription>当前为 B 端后台框架骨架，等待需求接入</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          侧边栏导航、路由、布局均已就绪。在
          <code className="mx-1 rounded bg-muted px-1.5 py-0.5 text-xs">
            src/pages
          </code>
          中添加业务页面，并在
          <code className="mx-1 rounded bg-muted px-1.5 py-0.5 text-xs">
            src/router.tsx
          </code>
          注册路由即可扩展。
        </CardContent>
      </Card>
    </div>
  )
}
