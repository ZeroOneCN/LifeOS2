export type Channel = {
  id: number
  channel_type: string
  channel_type_label: string
  name: string
  enabled: boolean
  recipients?: string | null
  note?: string | null
  config: Record<string, unknown>
}

// 来源 feature_key → 中文名称（source 存储格式为 {feature_key}:{dedup_key}）
export const SOURCE_LABELS: Record<string, string> = {
  finance_subscription_due: '服务订阅到期',
  finance_utility_due: '水电燃气到期',
  finance_loan_due: '网贷还款',
  finance_reminder_due: '账单提醒',
  finance_debt_due: '债务到期',
  lifestyle_todo_due: '待办到期',
  lifestyle_item_expire: '物品保质期',
  lifestyle_phone_bill: '手机卡月租',
  lifestyle_bankcard_due: '银行卡还款',
  lifestyle_card_expire: '证件到期',
  health_med_stock: '药品低库存',
  health_checkup_due: '体检到期',
}

/**
 * 将存储的来源标识转换为中文名称。
 * @param source 存储值，形如 health_med_stock:1
 * @returns 中文来源名称；未匹配时回退为原始 feature_key
 */
export function getSourceLabel(source?: string | null): string {
  if (!source) return '—'
  const key = source.split(':')[0]
  return SOURCE_LABELS[key] ?? key
}

// 通知分类 → 徽章配色
export const CATEGORY_STYLE: Record<string, string> = {
  系统: 'bg-blue-100 text-blue-700 dark:bg-blue-500/15 dark:text-blue-300',
  健康: 'bg-green-100 text-green-700 dark:bg-green-500/15 dark:text-green-300',
  财务: 'bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300',
  生活: 'bg-purple-100 text-purple-700 dark:bg-purple-500/15 dark:text-purple-300',
  投资: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-500/15 dark:text-cyan-300',
  其他: 'bg-gray-100 text-gray-600 dark:bg-gray-500/15 dark:text-gray-400',
}

/**
 * 获取分类徽章的配色。
 * @param category 分类名称
 * @returns 对应的 Tailwind 配色；未知分类使用「其他」配色
 */
export function getCategoryStyle(category?: string | null): string {
  return CATEGORY_STYLE[category ?? ''] ?? CATEGORY_STYLE.其他
}
