export type TableInfo = {
  name: string
  count: number
  label: string | null
  mapped: boolean
  module: string
  module_label: string
}

export type BackupFile = {
  filename: string
  size: number
  size_display: string
  modified_at: string
}

export type BackupPage = {
  items: BackupFile[]
  total: number
  page: number
  page_size: number
}

export type BackupPreview = {
  filename: string
  ext: string
  size: number
  size_display: string
  content: string
  truncated: boolean
}

export type ImportResult = {
  message: string
  total_inserted: number
  tables: Record<string, number>
}

export type CronOption = 'preset' | 'custom'

export type ScheduleItem = {
  id: number
  name: string
  enabled: boolean
  cron_expression: string
  export_format: string
  compress: boolean
  table_selection: string
  selected_tables: string[] | null
  last_run_at: string | null
  last_status: string | null
  created_at: string
  updated_at: string
}

export type LogItem = {
  id: number
  schedule_id: number | null
  name: string
  export_format: string
  filename: string | null
  file_size: number | null
  file_size_display: string | null
  status: string
  error_message: string | null
  started_at: string
  finished_at: string
  created_at: string
}

export type LogPage = {
  items: LogItem[]
  total: number
  page: number
  page_size: number
}

export function formatTime(iso: string) {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}
