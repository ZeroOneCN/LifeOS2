import { useState, type Dispatch, type SetStateAction } from 'react'
import { Database, Loader2, Upload } from 'lucide-react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { api } from '@/lib/api'

import type { ImportResult, TableInfo } from './shared'

type ImportTabProps = {
  tables: TableInfo[]
  reloadTables: () => Promise<void>
  // 已选文件与导入结果由页面持有，切换 Tab 后不重置（与原单组件行为一致）
  importFile: File | null
  setImportFile: Dispatch<SetStateAction<File | null>>
  importResult: ImportResult | null
  setImportResult: Dispatch<SetStateAction<ImportResult | null>>
}

export function ImportTab({
  tables,
  reloadTables,
  importFile,
  setImportFile,
  importResult,
  setImportResult,
}: ImportTabProps) {
  const [importing, setImporting] = useState(false)

  const handleImport = async () => {
    if (!importFile) {
      toast.error('请选择备份文件')
      return
    }
    if (!importFile.name.endsWith('.json')) {
      toast.error('仅支持 .json 格式的备份文件导入')
      return
    }
    setImporting(true)
    try {
      const formData = new FormData()
      formData.append('file', importFile)
      const result = await api.upload<ImportResult>('/backup/import', formData)
      setImportResult(result)
      toast.success(`导入完成，共插入 ${result.total_inserted} 条记录`)
      reloadTables()
      setImportFile(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : '导入失败')
    } finally {
      setImporting(false)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Upload className="h-5 w-5" />
            导入数据
          </CardTitle>
          <CardDescription>
            上传之前导出的 JSON 备份文件，将数据恢复到当前数据库
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-3">
            <input
              type="file"
              accept=".json"
              id="import-file-input"
              onChange={(e) => {
                setImportFile(e.target.files?.[0] ?? null)
                setImportResult(null)
              }}
              className="hidden"
            />
            <Button
              variant="outline"
              onClick={() => document.getElementById('import-file-input')?.click()}
            >
              <Upload className="mr-1.5 h-4 w-4" />
              选择备份文件
            </Button>
            <span className="text-sm text-muted-foreground">
              {importFile ? importFile.name : '未选择文件'}
            </span>
          </div>
          {importFile && (
            <div className="rounded-md bg-muted/50 px-4 py-2 text-sm">
              已选择：{importFile.name}（{(importFile.size / 1024).toFixed(1)} KB）
            </div>
          )}
          <div className="flex items-center gap-2 rounded-lg bg-warning-muted px-4 py-3 text-sm text-warning-muted-foreground">
            <Database className="h-4 w-4" />
            导入将使用 INSERT IGNORE 方式，遇到主键冲突会自动跳过，不会覆盖已有数据
          </div>
          <Button onClick={handleImport} disabled={importing || !importFile}>
            {importing ? (
              <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
            ) : (
              <Upload className="mr-1.5 h-4 w-4" />
            )}
            {importing ? '导入中...' : '开始导入'}
          </Button>
        </CardContent>
      </Card>

      {importResult && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-lg">
              <Database className="h-5 w-5" />
              导入结果
            </CardTitle>
            <CardDescription>
              共插入 {importResult.total_inserted} 条记录，各表详情如下：
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>数据表</TableHead>
                    <TableHead className="text-right">插入条数</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {Object.entries(importResult.tables)
                    .filter(([, count]) => count > 0)
                    .sort((a, b) => b[1] - a[1])
                    .map(([tableName, count]) => {
                      const info = tables.find((t) => t.name === tableName)
                      return (
                        <TableRow key={tableName}>
                          <TableCell>
                            <span className="inline-flex items-center gap-1.5">
                              {info?.label ?? tableName}
                              {info && !info.mapped && (
                                <Badge variant="outline" className="px-1 py-0 text-[10px] text-warning">
                                  未配置中文名
                                </Badge>
                              )}
                            </span>
                          </TableCell>
                          <TableCell className="text-right">{count}</TableCell>
                        </TableRow>
                      )
                    })}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
