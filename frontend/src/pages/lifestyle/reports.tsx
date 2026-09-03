import { useEffect, useState } from 'react'
import {
  ChevronDown,
  ChevronUp,
  Download,
  FileText,
  Loader2,
  Plus,
  Sparkles,
  Trash2,
} from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'

type ReportItem = {
  id: number
  title: string
  period_label?: string
  period_start?: string
  period_end?: string
  created_at?: string
}

type ReportDetail = ReportItem & { summary?: string; content?: unknown }

type ContentSection =
  | { type: 'h2'; text: string }
  | { type: 'paragraph'; text: string }
  | { type: 'kv'; label?: string; rows: string[][] }
  | { type: 'table'; header?: string[]; rows: string[][] }

function SectionBody({ section }: { section: ContentSection }) {
  if (section.type === 'paragraph') {
    return <p className="text-sm leading-6 text-muted-foreground">{section.text}</p>
  }
  if (section.type === 'table') {
    const header = section.header ?? ['项目', '数值']
    return (
      <div className="overflow-hidden rounded-lg border">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[320px] text-sm">
            <thead>
              <tr className="bg-rose-600">
                {header.map((h) => (
                  <th key={h} className="px-3 py-2 text-left font-medium text-white">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {section.rows.map((row, i) => (
                <tr key={i} className="border-t odd:bg-muted/30">
                  {row.map((cell, j) => (
                    <td key={j} className="px-3 py-2">
                      {cell}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    )
  }
  if (section.type === 'kv') {
    return (
      <div className="grid gap-px overflow-hidden rounded-lg border bg-border sm:grid-cols-2">
        {section.rows.map((row, i) => {
          const [k, v] = row
          return (
            <div
              key={i}
              className="flex items-center justify-between bg-background px-3 py-2 text-sm"
            >
              <span className="text-muted-foreground">{k}</span>
              <span className="font-medium">{v}</span>
            </div>
          )
        })}
      </div>
    )
  }
  return null
}

function ReportContent({ content }: { content?: unknown }) {
  let sections: ContentSection[] = []
  try {
    sections = Array.isArray(content) ? (content as ContentSection[]) : []
  } catch {
    sections = []
  }
  return (
    <div className="space-y-4">
      {sections.map((s, i) =>
        s.type === 'h2' ? (
          <h3 key={i} className="border-l-4 border-rose-500 pl-3 text-base font-semibold">
            {s.text}
          </h3>
        ) : (
          <div key={i}>
            <SectionBody section={s} />
          </div>
        ),
      )}
    </div>
  )
}

export function LifestyleReportsPage() {
  const [items, setItems] = useState<ReportItem[]>([])
  const [loading, setLoading] = useState(true)
  const [genOpen, setGenOpen] = useState(false)
  const [month, setMonth] = useState('')
  const [generating, setGenerating] = useState(false)
  const [preview, setPreview] = useState<ReportDetail | null>(null)
  const [previewCollapsed, setPreviewCollapsed] = useState(false)
  const [exportingId, setExportingId] = useState<number | null>(null)
  const { confirm, dialog: confirmDialog } = useConfirm({
    title: '确认删除报告',
    description: '确定删除这份生活报告吗？此操作不可恢复。',
  })

  const load = async () => {
    setLoading(true)
    try {
      const res = await api.query<ReportItem[]>('/lifestyle/reports')
      setItems(res)
    } catch (e) {
      toast.error('加载失败', { description: (e as Error).message })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const loadDetail = async (id: number) => {
    try {
      const rep = await api.get<ReportDetail>('/lifestyle/reports', id)
      setPreview(rep)
      setPreviewCollapsed(false)
      await load()
    } catch (e) {
      toast.error('加载失败', { description: (e as Error).message })
    }
  }

  const handleGenerate = async () => {
    setGenerating(true)
    try {
      const path = month ? `/lifestyle/reports/generate?month=${encodeURIComponent(month)}` : '/lifestyle/reports/generate'
      const rep = await api.post<ReportDetail>(path)
      setGenOpen(false)
      toast.success('报告已生成', { description: rep.title })
      setPreview(rep)
      setPreviewCollapsed(false)
      await load()
    } catch (e) {
      toast.error('生成失败', { description: (e as Error).message })
    } finally {
      setGenerating(false)
    }
  }

  const handleExport = async (id: number) => {
    setExportingId(id)
    try {
      await api.download(`/lifestyle/reports/${id}/export`)
      toast.success('PDF 已导出')
    } catch (e) {
      toast.error('导出失败', { description: (e as Error).message })
    } finally {
      setExportingId(null)
    }
  }

  const handleDelete = async (id: number) => {
    if (!(await confirm())) return
    try {
      await api.remove('/lifestyle/reports', id)
      toast.success('报告已删除')
      if (preview?.id === id) setPreview(null)
      await load()
    } catch (e) {
      toast.error('删除失败', { description: (e as Error).message })
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="font-heading text-2xl font-semibold tracking-tight">生活报告</h1>
          <p className="text-sm text-muted-foreground">
            自动汇总物品、卡片与待办等生活数据，生成月度报告并支持 PDF 导出。
          </p>
        </div>
        <Button onClick={() => setGenOpen(true)}>
          <Sparkles className="size-4" />
          生成报告
        </Button>
      </div>

      {preview && (
        <Card className="border-rose-200">
          <CardHeader className="flex flex-row items-start justify-between gap-3 border-b pb-3">
            <button
              type="button"
              className="min-w-0 flex-1 text-left"
              onClick={() => setPreviewCollapsed((v) => !v)}
            >
              <div className="flex items-center gap-2">
                <ChevronDown
                  className={`size-4 shrink-0 text-rose-600 transition-transform ${previewCollapsed ? '-rotate-90' : ''}`}
                />
                <CardTitle className="text-base">{preview.title}</CardTitle>
              </div>
              {preview.summary && <p className="mt-1 text-sm text-muted-foreground">{preview.summary}</p>}
            </button>
            <div className="flex shrink-0 items-center gap-2">
              <Button
                size="sm"
                variant="ghost"
                onClick={() => setPreviewCollapsed((v) => !v)}
                title={previewCollapsed ? '展开' : '收起'}
              >
                {previewCollapsed ? <ChevronDown className="size-4" /> : <ChevronUp className="size-4" />}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => handleExport(preview.id)}
                disabled={exportingId === preview.id}
              >
                {exportingId === preview.id ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
                导出 PDF
              </Button>
            </div>
          </CardHeader>
          {!previewCollapsed && (
            <CardContent className="pt-4">
              <ReportContent content={preview.content} />
            </CardContent>
          )}
        </Card>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">历史报告（{items.length}）</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-3">
              <Skeleton className="h-14 w-full" />
              <Skeleton className="h-14 w-full" />
              <Skeleton className="h-14 w-full" />
            </div>
          ) : items.length === 0 ? (
            <div className="flex flex-col items-center gap-2 py-10 text-center">
              <FileText className="size-10 text-muted-foreground/40" />
              <p className="text-sm text-muted-foreground">暂无报告，点击右上角“生成报告”开始。</p>
            </div>
          ) : (
            <div className="space-y-2">
              {items.map((r) => (
                <div
                  key={r.id}
                  className="flex items-start justify-between gap-3 rounded-lg border p-3 hover:bg-muted/40"
                >
                  <button type="button" className="min-w-0 flex-1 text-left" onClick={() => loadDetail(r.id)}>
                    <div className="flex items-center gap-2">
                      <FileText className="size-4 shrink-0 text-rose-600" />
                      <span className="truncate text-sm font-medium">{r.title}</span>
                    </div>
                    <div className="mt-0.5 text-xs text-muted-foreground">
                      {r.period_label}
                      {r.created_at ? ` · ${r.created_at}` : ''}
                    </div>
                  </button>
                  <div className="flex shrink-0 items-center gap-1">
                    <Button
                      size="icon"
                      variant="ghost"
                      title="导出 PDF"
                      onClick={() => handleExport(r.id)}
                      disabled={exportingId === r.id}
                    >
                      {exportingId === r.id ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      className="text-destructive"
                      title="删除"
                      onClick={() => handleDelete(r.id)}
                    >
                      <Trash2 className="size-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={genOpen} onOpenChange={setGenOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>生成生活报告</DialogTitle>
            <DialogDescription>
              选择统计月份（默认当前月），系统将自动汇总该月物品、卡片与待办数据并生成报告。
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 py-2">
            <div className="text-sm font-medium">统计月份（YYYY-MM，留空为当前月）</div>
            <Input type="month" value={month} onChange={(e) => setMonth(e.target.value)} placeholder="2026-09" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setGenOpen(false)}>
              取消
            </Button>
            <Button onClick={handleGenerate} disabled={generating}>
              {generating ? <Loader2 className="size-4 animate-spin" /> : <Plus className="size-4" />}
              生成
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirmDialog}
    </div>
  )
}