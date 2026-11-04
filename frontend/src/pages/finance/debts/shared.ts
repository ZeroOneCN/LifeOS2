/** 债务管理页共享类型与常量（各 Tab 模块共用，不含组件）。 */

export type Currency = { id: number; currency: string; name?: string; rate_to_cny: number; symbol?: string }
export type Fmt = (cny: number) => string

export const directionMeta: Record<string, { label: string; className: string }> = {
  lend: { label: '借出', className: 'bg-info-muted text-info-muted-foreground' },
  borrow: { label: '借入', className: 'bg-warning-muted text-warning-muted-foreground' },
}
export const statusMeta: Record<string, { label: string; className: string }> = {
  active: { label: '进行中', className: 'bg-info-muted text-info-muted-foreground' },
  settled: { label: '已结清', className: 'bg-success-muted text-success-muted-foreground' },
}

export const investCategories = ['美股', '港股', '外汇', '加密货币-合约', '加密货币-现货', '加密货币-钱包(Alpha)']

export type DebtRecord = {
  id: number
  debt_date: string
  name: string
  direction: 'lend' | 'borrow'
  counterparty?: string
  amount: number
  remaining?: number
  interest_rate?: number
  interest_total?: number
  channel?: string
  due_date?: string
  status: 'active' | 'settled'
  note?: string
}
export type DebtPayment = { id: number; debt_id: number; repay_date: string; amount: number; discount?: number; actual?: number; note?: string }
export const channelOptions = ['现金', '银行转账', '微信', '支付宝', '其他']
export const channelMeta: Record<string, { className: string }> = {
  现金: { className: 'bg-zinc-100 text-zinc-700 dark:bg-zinc-500/15 dark:text-zinc-300' },
  银行转账: { className: 'bg-info-muted text-info-muted-foreground' },
  微信: { className: 'bg-success-muted text-success-muted-foreground' },
  支付宝: { className: 'bg-info-muted text-info-muted-foreground' },
  其他: { className: 'bg-muted text-muted-foreground' },
}
export type DebtStats = {
  total: number; active: number; settled: number
  borrow_total: number; lend_total: number; outstanding: number; overdue: number
  by_status: { status: string; label: string; count: number }[]
  overdue_list: { name: string; counterparty?: string; direction: string; remaining: number; due_date?: string }[]
}
export type LoanSync = { total_remaining: number; platform_count: number; platforms: { platform_id: number; name: string; remaining: number; bill_count: number }[] }
