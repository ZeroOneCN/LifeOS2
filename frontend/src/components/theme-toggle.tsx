"use client"

import * as React from "react"
import { Monitor, Moon, Sun } from "lucide-react"
import { useTheme } from "next-themes"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

const THEMES: { key: string; label: string; icon: typeof Sun }[] = [
  { key: "light", label: "浅色", icon: Sun },
  { key: "dark", label: "深色", icon: Moon },
  { key: "system", label: "跟随系统", icon: Monitor },
]

/**
 * 主题切换按钮：点击弹出浅色 / 深色 / 跟随系统三档选择。
 * 当前主题以太阳/月亮图标在按钮上实时呈现，便于用户感知。
 */
export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const current = THEMES.find((t) => t.key === theme) ?? THEMES[2]

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" aria-label="切换主题">
          {current.key === "dark" ? (
            <Moon className="size-4" />
          ) : current.key === "light" ? (
            <Sun className="size-4" />
          ) : (
            <Monitor className="size-4" />
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="min-w-32">
        {THEMES.map((t) => (
          <DropdownMenuItem
            key={t.key}
            onClick={() => setTheme(t.key)}
            className={t.key === current.key ? "gap-2" : "gap-2"}
          >
            <t.icon className="size-4" />
            <span>{t.label}</span>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}