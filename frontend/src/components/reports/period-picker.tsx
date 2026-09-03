import { Label } from '@/components/ui/label'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

/** 报告统计区间：近 N 天或自定义起止日期 */
export type ReportPeriod = {
  days?: number
  start_date?: string
  end_date?: string
}

const PERIOD_OPTIONS = [
  { value: '7', label: '近 7 天' },
  { value: '30', label: '近 30 天' },
  { value: '90', label: '近 90 天' },
  { value: 'custom', label: '自定义' },
]

export function ReportPeriodPicker({
  value,
  onChange,
}: {
  value: ReportPeriod
  onChange: (v: ReportPeriod) => void
}) {
  const mode = value.start_date ? 'custom' : String(value.days ?? 30)
  const setMode = (m: string) => {
    if (m === 'custom') {
      onChange({ start_date: value.start_date ?? '', end_date: value.end_date ?? '' })
    } else {
      onChange({ days: Number(m) })
    }
  }
  return (
    <div className="space-y-3">
      <div className="space-y-1.5">
        <Label>统计周期</Label>
        <Select value={mode} onValueChange={setMode}>
          <SelectTrigger className="w-full">
            <SelectValue placeholder="选择周期" />
          </SelectTrigger>
          <SelectContent>
            {PERIOD_OPTIONS.map((o) => (
              <SelectItem key={o.value} value={o.value}>
                {o.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {mode === 'custom' && (
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label>开始日期</Label>
            <Input
              type="date"
              value={value.start_date ?? ''}
              onChange={(e) => onChange({ ...value, start_date: e.target.value })}
            />
          </div>
          <div className="space-y-1.5">
            <Label>结束日期</Label>
            <Input
              type="date"
              value={value.end_date ?? ''}
              onChange={(e) => onChange({ ...value, end_date: e.target.value })}
            />
          </div>
        </div>
      )}
    </div>
  )
}
