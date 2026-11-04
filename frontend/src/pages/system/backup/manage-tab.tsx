import { useState, type Dispatch, type SetStateAction } from 'react'
import { Download, Eraser, Eye, HardDrive, Loader2, Trash2 } from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { PaginationBar } from '@/components/ui/pagination-bar'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Tip } from '@/components/ui/tip'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { api } from '@/lib/api'

import {
  formatTime,
  type BackupFile,
  type BackupPreview,
} from './shared'

type ManageTabProps = {
  // 当前页码由页面持有，切换 Tab 后不重置（与原单组件行为一致）
  backupPage: number
  setBackupPage: Dispatch<SetStateAction<number>>
  // 列表数据由页面层的统一轮询提供，未挂载时也保持刷新
  backups: BackupFile[]
  backupTotal: number
  loadingBackups: boolean
  reloadBackups: () => Promise<void>
}

export function ManageTab({
  backupPage,
  setBackupPage,
  backups,
  backupTotal,
  loadingBackups,
  reloadBackups,
}: ManageTabProps) {
  const { confirm, dialog: confirmDialog } = useConfirm()
  const backupPageSize = 10
  // SQL 在线预览
  const [previewFile, setPreviewFile] = useState<BackupFile | null>(null)
  const [previewContent, setPreviewContent] = useState<BackupPreview | null>(null)
  const [previewLoading, setPreviewLoading] = useState(false)

  const handleDownloadBackup = (filename: string) => {
    api.download(`/backup/exports/${encodeURIComponent(filename)}`, filename)
  }

  const handleDeleteBackup = async (filename: string) => {
    const ok = await confirm({
      title: '删除备份文件',
      description: `确定要删除备份文件「${filename}」吗？此操作不可撤销。`,
      confirmText: '确认删除',
      danger: true,
    })
    if (!ok) return
    try {
      await api.del(`/backup/exports/${encodeURIComponent(filename)}`)
      toast.success(`备份文件 ${filename} 已删除`)
      // 若当前页删除后为空且非第一页，则回退一页
      if (backups.length === 1 && backupPage > 1) {
        setBackupPage((p) => p - 1)
      } else {
        reloadBackups()
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '删除失败')
    }
  }

  const handleClearBackups = async () => {
    const ok = await confirm({
      title: '清除旧备份文件',
      description: '将删除 3 天前的备份文件，最近 3 天内的备份会被保留。此操作不可撤销。',
      confirmText: '确认清除',
      danger: true,
    })
    if (!ok) return
    try {
      const res = await api.del<{ deleted: number }>('/backup/exports?keep_days=3')
      toast.success(`已清除 ${res.deleted} 个旧备份文件（保留近 3 天）`)
      if (backupPage === 1) reloadBackups()
      else setBackupPage(1)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '清除备份失败')
    }
  }

  const handlePreviewBackup = async (f: BackupFile) => {
    setPreviewFile(f)
    setPreviewContent(null)
    setPreviewLoading(true)
    try {
      const data = await api.query<BackupPreview>(
        `/backup/exports/${encodeURIComponent(f.filename)}/preview`
      )
      setPreviewContent(data)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '预览失败')
      setPreviewFile(null)
    } finally {
      setPreviewLoading(false)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <HardDrive className="h-5 w-5" />
            备份文件列表
          </CardTitle>
          <CardDescription>
            管理已生成的备份文件，支持在线预览 SQL、下载或删除，共 {backupTotal} 个文件
          </CardDescription>
          <CardAction>
            <Button
              variant="outline"
              size="sm"
              disabled={backupTotal === 0}
              onClick={handleClearBackups}
            >
              <Eraser className="mr-1 h-4 w-4" />
              清除备份
            </Button>
          </CardAction>
        </CardHeader>
        <CardContent>
          {backups.length === 0 && loadingBackups ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : backups.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
              <HardDrive className="mb-2 h-10 w-10" />
              <p>暂无备份文件</p>
              <p className="text-xs">在"数据导出"或"定时备份"中导出数据后，备份文件将出现在这里</p>
            </div>
          ) : (
            <div
              className={`overflow-x-auto transition-opacity ${
                loadingBackups ? 'pointer-events-none opacity-60' : ''
              }`}
            >
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>文件名</TableHead>
                    <TableHead className="w-24">大小</TableHead>
                    <TableHead className="w-[160px]">修改时间</TableHead>
                    <TableHead className="w-28 text-right">操作</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {backups.map((f) => (
                    <TableRow key={f.filename}>
                      <Tip label={f.filename}>
                        <TableCell className="max-w-[300px] truncate font-mono text-xs">
                          {f.filename}
                        </TableCell>
                      </Tip>
                      <TableCell className="text-muted-foreground text-xs">{f.size_display}</TableCell>
                      <TableCell className="text-muted-foreground text-xs">
                        {formatTime(f.modified_at)}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1">
                          {f.filename.toLowerCase().endsWith('.sql') && (
                            <Tip label="在线预览">
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8"
                                onClick={() => handlePreviewBackup(f)}
                              >
                                <Eye className="h-4 w-4" />
                              </Button>
                            </Tip>
                          )}
                          <Tip label="下载">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8"
                              onClick={() => handleDownloadBackup(f.filename)}
                            >
                              <Download className="h-4 w-4" />
                            </Button>
                          </Tip>
                          <Tip label="删除">
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-destructive hover:text-destructive"
                              onClick={() => handleDeleteBackup(f.filename)}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </Tip>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          {/* 分页 */}
          {backupTotal > backupPageSize && (
            <div className="mt-4">
              <PaginationBar
                page={backupPage}
                totalPages={Math.max(1, Math.ceil(backupTotal / backupPageSize))}
                total={backupTotal}
                onPageChange={setBackupPage}
              />
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── SQL 在线预览弹窗 ── */}
      <Dialog open={!!previewFile} onOpenChange={(v) => { if (!v) setPreviewFile(null) }}>
        <DialogContent className="sm:max-w-3xl">
          <DialogHeader>
            <DialogTitle>SQL 在线预览</DialogTitle>
            <DialogDescription>
              {previewFile?.filename ?? ''}
              {previewContent ? ` · ${previewContent.size_display}` : ''}
            </DialogDescription>
          </DialogHeader>
          {previewLoading ? (
            <div className="flex items-center justify-center py-10">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : (
            <pre className="max-h-[60vh] overflow-auto rounded-lg bg-muted/50 p-4 font-mono text-xs leading-relaxed whitespace-pre break-all">
              {previewContent?.content ?? ''}
            </pre>
          )}
          {previewContent?.truncated && (
            <p className="text-xs text-warning">
              内容过长，已截断显示（完整内容请下载后查看）
            </p>
          )}
          <DialogFooter showCloseButton={false}>
            <Button variant="outline" onClick={() => setPreviewFile(null)}>
              关闭
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {confirmDialog}
    </div>
  )
}
