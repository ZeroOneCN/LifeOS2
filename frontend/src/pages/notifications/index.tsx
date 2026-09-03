import { useState } from 'react'
import { Bell, Cable, Inbox, MailCheck, Send, SlidersHorizontal } from 'lucide-react'

import { cn } from '@/lib/utils'
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

      <div className="flex flex-wrap gap-1 rounded-lg border bg-muted/30 p-1">
        {TABS.map((t) => {
          const Icon = t.icon
          return (
            <button
              key={t.key}
              type="button"
              onClick={() => setTab(t.key)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
                tab === t.key
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              <Icon className="size-4" />
              {t.label}
            </button>
          )
        })}
      </div>

      {TABS.find((t) => t.key === tab)?.node}
    </div>
  )
}