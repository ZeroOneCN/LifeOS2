import { formatCny } from '@/lib/format'

/** 金额四舍五入到分（避免浮点误差，如 1823.03 - 1823.0300000000002 = -2.27e-13）。 */
export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100
/**
 * 账单金额格式化：统一走公共 formatCny（2 位小数、千分位、负号在 ¥ 前）。
 * 对极小值归零的处理已由 formatCny 内置，避免显示成 ¥-0.00。
 */
export const fmt = formatCny
/** 计算账单剩余欠款：取整到分并夹紧为非负（优惠抵减后浮点误差会得到极小负数）。 */
export const remainingOf = (amount: number, paidAmount: number) => Math.max(0, round2(amount - paidAmount))
