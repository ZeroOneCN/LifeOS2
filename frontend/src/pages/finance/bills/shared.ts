/** 金额四舍五入到分（避免浮点误差，如 1823.03 - 1823.0300000000002 = -2.27e-13）。 */
export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100
/**
 * 金额格式化：保留 2 位小数。
 * 对极小值（|n| < 0.005，含浮点误差产生的负零）归零，避免显示成 ¥-0.00。
 */
export const fmt = (n: number) => {
  const v = Math.abs(n) < 0.005 ? 0 : n
  return `¥${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}
/** 计算账单剩余欠款：取整到分并夹紧为非负（优惠抵减后浮点误差会得到极小负数）。 */
export const remainingOf = (amount: number, paidAmount: number) => Math.max(0, round2(amount - paidAmount))
