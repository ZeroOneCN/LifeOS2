import { useState } from 'react'
import { Bell, Cable, Inbox, MailCheck, Send, SlidersHorizontal } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { NotificationList } from './list'
import { ChannelsPanel } from './channels'
import { EmailConfigPanel } from './email'
import { TemplatesPanel } from './templates'
import { ReminderSettingsPanel } from './settings'
import { SendLogPanel } from './send-logs'

const TABS = [
  { key: 'list', label: '通知列表', icon: Inbox, node: <NotificationList /> },
  { key: 'channels', label: '渠道配置', icon: Cable, node: <ChannelsPanel /> },
  { key: 'email', label: '邮件配置', icon: MailCheck, node: <EmailConfigPanel /> },
  { key: 'templates', label: '默认模板', icon: Send, node: <TemplatesPanel /> },
  { key: 'settings', label: '提醒开关', icon: SlidersHorizontal, node: <ReminderSettingsPanel /> },
  { key: 'logs', label: '发送记录', icon: Bell, node: <SendLogPanel /> },
]

export function NotificationsPage() {
  const [tab, setTab] = useState('list')

  return (
    <div className="flex flex-col gap-4">
      <section className="space-y-1">
        <h1 className="font-heading text-2xl font-semibold tracking-tight">通知中心</h1>
        <p className="text-sm text-muted-foreground">
          统一通知提醒：汇总各模块到期数据，经配置渠道下发到邮件/钉钉/飞书/企微/Telegram/Webhook。
        </p>
      </section>

      <div className="flex gap-1 overflow-x-auto rounded-lg bg-muted p-1">
        {TABS.map((t) => (
          <Button
            key={t.key}
            variant={tab === t.key ? 'default' : 'ghost'}
            className="min-w-max flex-1 whitespace-nowrap"
            onClick={() => setTab(t.key)}
          >
            <t.icon className="size-4" /> {t.label}
          </Button>
        ))}
      </div>

      {TABS.find((t) => t.key === tab)?.node}
    </div>
  )
}