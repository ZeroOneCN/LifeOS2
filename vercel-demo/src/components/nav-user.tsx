import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BadgeCheck, LogOut, Settings } from 'lucide-react'

import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { useAuth } from '@/lib/auth'

export function NavUser() {
  const navigate = useNavigate()
  const { user, logout } = useAuth()
  const [open, setOpen] = useState(false)
  const { confirm, dialog } = useConfirm()

  const nickname = user?.nickname?.trim() || user?.username?.trim() || '未命名用户'
  const account = user?.account ?? ''
  const email = user?.email ?? '未设置邮箱'
  const initial = nickname.charAt(0).toUpperCase()

  const onLogout = async () => {
    const ok = await confirm({
      title: '退出登录',
      description: '确定要退出当前账号吗？',
      confirmText: '确认退出',
      cancelText: '取消',
      danger: true,
    })
    if (!ok) return
    setOpen(false)
    logout()
  }

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu open={open} onOpenChange={setOpen}>
          <DropdownMenuTrigger asChild>
            <SidebarMenuButton
              size="lg"
              className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
            >
              <Avatar className="size-8 rounded-lg">
                {user?.avatar ? (
                  <AvatarImage src={user.avatar} alt={nickname} />
                ) : null}
                <AvatarFallback className="rounded-lg">{initial}</AvatarFallback>
              </Avatar>
              <div className="grid flex-1 text-left text-sm leading-tight group-data-[collapsible=icon]:hidden">
                <span className="flex items-center gap-1.5 truncate font-medium">
                  {nickname}
                  {user?.isAdmin ? (
                    <span className="rounded bg-primary/10 px-1 py-px text-[10px] font-semibold text-primary">
                      管理员
                    </span>
                  ) : null}
                </span>
                <span className="truncate text-xs text-muted-foreground">{email}</span>
              </div>
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg"
            side="bottom"
            align="end"
            sideOffset={4}
          >
            <DropdownMenuLabel className="p-0 font-normal">
              <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
                <Avatar className="size-8 rounded-lg">
                  {user?.avatar ? (
                    <AvatarImage src={user.avatar} alt={nickname} />
                  ) : null}
                  <AvatarFallback className="rounded-lg">{initial}</AvatarFallback>
                </Avatar>
                <div className="grid flex-1 text-left text-sm leading-tight">
                  <span className="flex items-center gap-1.5 truncate font-medium">
                    {nickname}
                    {user?.isAdmin ? (
                      <span className="rounded bg-primary/10 px-1 py-px text-[10px] font-semibold text-primary">
                        管理员
                      </span>
                    ) : null}
                  </span>
                  <span className="truncate text-xs text-muted-foreground">
                    {account ? `账号：${account}` : email}
                  </span>
                </div>
              </div>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuItem onSelect={() => navigate('/user-center')}>
                <BadgeCheck />
                个人资料
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => navigate('/user-center/settings')}>
                <Settings />
                账号设置
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={onLogout}>
              <LogOut />
              退出登录
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
      {dialog}
    </SidebarMenu>
  )
}
