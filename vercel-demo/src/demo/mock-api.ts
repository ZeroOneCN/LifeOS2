/**
 * Vercel 演示版 Mock API
 *
 * 该模块在浏览器启动的最早阶段拦截所有 `/api/v1/*` 请求，
 * 使用内置快照（snapshot.json）返回演示数据，并把用户的增删改保存在 localStorage，
 * 因此无需任何后端即可完整体验前端功能。
 */
import snapshot from './snapshot.json'

type Json = Record<string, any>
type Params = Record<string, string>

/** 演示数据版本，结构变更时递增可自动丢弃旧的本地修改 */
const STORAGE_KEY = 'lifeos:demo-store:v1'
const API_PREFIX = '/api/v1'
const PAGE_KEYS = new Set(['page', 'page_size', 'limit'])
const FILTER_SKIP_KEYS = new Set(['page', 'page_size', 'limit', 'days', 'start', 'end', 'keyword', 'keep_days', 'month', 'year'])

type SnapshotEntry = {
  key: string
  path: string
  params: Params
  value: any
}

type Overrides = {
  lists: Record<string, any[]>
  objects: Record<string, any>
}

/** 从快照构建路径索引，便于按 base path 查找最匹配的响应 */
const entries: SnapshotEntry[] = Object.entries(snapshot as Json).map(([key, value]) => {
  const raw = key.slice(API_PREFIX.length)
  const [path, qs] = raw.split('?')
  return {
    key,
    path,
    params: Object.fromEntries(new URLSearchParams(qs || '')),
    value,
  }
})

/** 读取本地保存的修改，失败时返回空覆盖 */
function loadOverrides(): Overrides {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return { lists: {}, objects: {} }
    const parsed = JSON.parse(raw)
    return { lists: parsed.lists || {}, objects: parsed.objects || {} }
  } catch {
    return { lists: {}, objects: {} }
  }
}

const overrides = loadOverrides()

/** 把本地修改应用到快照条目上 */
function applyOverrides() {
  for (const entry of entries) {
    const list = overrides.lists[entry.key]
    if (list && entry.value && Array.isArray(entry.value.items)) {
      entry.value.items = list
      entry.value.total = list.length
    }
    const obj = overrides.objects[entry.key]
    if (obj) entry.value = obj
  }
}
applyOverrides()

/** 持久化本地修改 */
function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(overrides))
  } catch {
    /* 配额不足时忽略，内存中的数据仍然可用 */
  }
}

/** 深拷贝，避免读取时污染快照 */
function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T
}

/** 当前时间的 ISO 字符串 */
function nowIso() {
  const d = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

/** 今天的 YYYY-MM-DD */
function today() {
  return nowIso().slice(0, 10)
}

/** 返回 JSON 响应 */
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  })
}

/** 返回错误响应 */
function errorResponse(status: number, detail: string): Response {
  return jsonResponse({ detail }, status)
}

/** 返回文件下载响应 */
function fileResponse(blob: Blob, filename: string): Response {
  return new Response(blob, {
    status: 200,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(filename)}`,
    },
  })
}

/** 构造一个可被阅读器打开的最小 PDF 文件 */
function makePdf(title: string, lines: string[]): Blob {
  const esc = (s: string) => s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)')
  const content = [
    'BT /F1 20 Tf 72 780 Td (' + esc(title) + ') Tj ET',
    ...lines.map((line, i) => `BT /F1 12 Tf 72 ${740 - i * 22} Td (${esc(line)}) Tj ET`),
  ].join('\n')
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ]
  let body = '%PDF-1.4\n'
  const offsets: number[] = []
  objects.forEach((obj, index) => {
    offsets.push(body.length)
    body += `${index + 1} 0 obj\n${obj}\nendobj\n`
  })
  const xref = body.length
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  for (const offset of offsets) body += `${String(offset).padStart(10, '0')} 00000 n \n`
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`
  return new Blob([body], { type: 'application/pdf' })
}

/** 根据路径与查询参数找到最匹配的快照条目 */
function findEntry(path: string, params: Params = {}): SnapshotEntry | undefined {
  const candidates = entries.filter((item) => item.path === path)
  if (!candidates.length) return undefined
  const scoreOf = (item: SnapshotEntry) =>
    Object.keys(item.params).filter((key) => !PAGE_KEYS.has(key) && params[key] !== undefined && String(params[key]) === item.params[key]).length
  let best = candidates[0]
  let bestScore = -1
  for (const item of candidates) {
    const score = scoreOf(item)
    if (score > bestScore) {
      best = item
      bestScore = score
    }
  }
  return best
}

/** 按查询参数过滤列表数据 */
function filterItems<T extends Json>(items: T[], params: Params): T[] {
  let result = items.filter((item) => {
    for (const [key, raw] of Object.entries(params)) {
      if (FILTER_SKIP_KEYS.has(key) || raw === '' || raw === undefined || raw === null) continue
      const sample = items.find((it) => key in it)
      if (!sample) continue
      const value = item[key]
      if (value === undefined || value === null) return false
      if (typeof value === 'boolean') {
        if (String(value) !== raw) return false
      } else if (typeof value === 'number') {
        if (Number(raw) !== value) return false
      } else {
        if (String(value) !== raw) return false
      }
    }
    return true
  })

  // 关键词搜索
  const keyword = params.keyword?.trim().toLowerCase()
  if (keyword) {
    const textFields = ['product_name', 'item_name', 'title', 'name', 'note', 'category', 'content', 'food_name', 'medicine_name', 'card_name', 'symbol']
    result = result.filter((item) => textFields.some((field) => String(item[field] ?? '').toLowerCase().includes(keyword)))
  }

  // 月份 / 年份过滤
  if (params.month || params.year) {
    const prefix = params.month || params.year
    result = result.filter((item) => {
      const dateKey = ['record_date', 'bill_month', 'detail_date', 'notify_date', 'trade_date'].find((key) => key in item)
      return dateKey ? String(item[dateKey]).startsWith(prefix) : true
    })
  }

  // 日期范围过滤
  if (params.start || params.end) {
    result = result.filter((item) => {
      const dateKey = ['record_date', 'detail_date', 'notify_date', 'trade_date', 'bill_month', 'check_date', 'buy_date', 'created_at'].find((key) => key in item)
      if (!dateKey) return true
      const date = String(item[dateKey]).slice(0, 10)
      if (params.start && date < params.start) return false
      if (params.end && date > params.end) return false
      return true
    })
  }

  // 最近 N 天
  const days = Number(params.days)
  if (days > 0) {
    const cutoff = new Date()
    cutoff.setDate(cutoff.getDate() - days)
    const cutoffText = cutoff.toISOString().slice(0, 10)
    result = result.filter((item) => {
      const dateKey = ['record_date', 'detail_date', 'notify_date', 'trade_date', 'bill_month', 'check_date', 'buy_date', 'created_at'].find((key) => key in item)
      return dateKey ? String(item[dateKey]).slice(0, 10) >= cutoffText : true
    })
  }
  return result
}

/** 读取分页响应，并在本地完成过滤与分页 */
function paginate(value: Json, params: Params): Json {
  const items = filterItems(value.items as Json[], params)
  const page = Math.max(1, Number(params.page) || 1)
  const pageSize = Math.max(1, Number(params.page_size || params.limit) || 20)
  const start = (page - 1) * pageSize
  return {
    ...clone(value),
    items: clone(items.slice(start, start + pageSize)),
    total: items.length,
    page,
    page_size: pageSize,
  }
}

/** 获取某个集合当前的可变数组引用 */
function collectionOf(path: string, params: Params = {}): any[] {
  const entry = findEntry(path, params)
  if (!entry) return []
  if (Array.isArray(entry.value)) return entry.value
  if (Array.isArray(entry.value?.items)) return entry.value.items
  return []
}

/** 新建记录时生成自增 ID */
function nextId(items: any[]) {
  return items.reduce((max, item) => Math.max(max, Number(item?.id) || 0), 0) + 1
}

/** 汇总同一路径下所有分页条目中的记录 */
function collectAll(path: string): any[] {
  const result: any[] = []
  for (const entry of entries) {
    if (entry.path !== path) continue
    const value = entry.value
    if (Array.isArray(value)) result.push(...value)
    else if (Array.isArray(value.items)) result.push(...value.items)
  }
  return result
}

/** 从体检明细聚合统计（模拟后端 /health/checkup/stats） */
function computeCheckupStats(params: Params): Json {
  const days = Number(params.days) || 0
  const since = days > 0 ? new Date(Date.now() - days * 86400000).toISOString().slice(0, 10) : ''
  const rows = collectAll('/health/checkup')
    .filter((row) => !since || String(row.check_date).slice(0, 10) >= since)
    .sort((a, b) => String(a.check_date).localeCompare(String(b.check_date)))

  const statusLabel: Json = { normal: '正常', high: '偏高', low: '偏低' }
  const buckets = new Map<string, Json>()
  for (const row of rows) {
    const value = Number(row.value)
    const high = row.ref_high === null || row.ref_high === undefined ? null : Number(row.ref_high)
    const low = row.ref_low === null || row.ref_low === undefined ? null : Number(row.ref_low)
    const result = high !== null && value > high ? 'high' : low !== null && value < low ? 'low' : 'normal'
    let bucket = buckets.get(row.item_name)
    if (!bucket) {
      bucket = {
        item_name: row.item_name,
        unit: row.unit,
        reference_range: row.reference_range,
        ref_low: row.ref_low,
        ref_high: row.ref_high,
        latest: null,
        trend: [],
      }
      buckets.set(row.item_name, bucket)
    }
    bucket.trend.push({ check_date: row.check_date, value: row.value, result })
    if (!bucket.latest || String(row.check_date) > String(bucket.latest.check_date)) {
      bucket.latest = { check_date: row.check_date, value: row.value, result }
    }
  }

  const items: any[] = Array.from(buckets.values()).map((bucket) => ({
    ...bucket,
    count: bucket.trend.length,
    trend: bucket.trend.slice(-30),
  }))
  const statusCounts = { normal: 0, high: 0, low: 0 }
  for (const item of items) {
    const result = item.latest?.result
    if (result in statusCounts) statusCounts[result as keyof typeof statusCounts] += 1
  }
  const abnormalItems = items
    .filter((item) => item.latest && item.latest.result !== 'normal')
    .map((item) => item.latest)

  return {
    items,
    total_count: rows.length,
    abnormal_count: abnormalItems.length,
    status_counts: statusCounts,
    abnormal_items: abnormalItems,
    status_label: statusLabel,
  }
}

/** 保存某个分页集合的本地修改 */
function saveList(entry: SnapshotEntry, items: any[]) {
  if (Array.isArray(entry.value)) {
    entry.value = items
    overrides.objects[entry.key] = items
  } else {
    entry.value.items = items
    entry.value.total = items.length
    overrides.lists[entry.key] = items
  }
  persist()
}

/** 修正报告详情：新生成的报告复用已有详情结构，仅替换标题与周期 */
function reportDetail(kind: string, id: number): any {
  const exact = findEntry(`/${kind}/reports/${id}`)
  if (exact) return clone(exact.value)
  const base = findEntry(`/${kind}/reports/1`)
  if (!base) return { id, title: '演示报告', period_label: '', content: '[]' }
  const list = collectionOf(`/${kind}/reports`)
  const record = list.find((item) => Number(item.id) === id)
  const detail = clone(base.value)
  detail.id = id
  if (record) {
    detail.title = record.title ?? detail.title
    detail.period_label = record.period_label ?? detail.period_label
    detail.report_date = record.report_date ?? detail.report_date
  }
  return detail
}

/** 生成周期标签 */
function periodLabel(body: Json): string {
  if (body.start_date && body.end_date) return `${body.start_date} ~ ${body.end_date}`
  const days = Number(body.days) || 30
  const end = new Date()
  const start = new Date()
  start.setDate(start.getDate() - days)
  const fmt = (d: Date) => d.toISOString().slice(0, 10)
  return `${fmt(start)} ~ ${fmt(end)}`
}

/** 处理登录 */
function handleLogin(body: Json) {
  const account = String(body.account ?? '').trim()
  if (account !== 'demo') {
    return errorResponse(401, '演示环境请使用账号 demo / 密码 demo123456 登录')
  }
  const user = clone(findEntry('/auth/me')?.value ?? {})
  return jsonResponse({ access_token: 'demo-access-token', refresh_token: 'demo-refresh-token', user })
}

/** 创建一条记录 */
function createRecord(path: string, body: Json, params: Params = {}) {
  const merged: Params = { ...params }
  if (body && typeof body === 'object') {
    for (const key of ['housing_id', 'ledger_id', 'platform_id', 'phone_card_id', 'bill_id', 'debt_id']) {
      if (body[key] !== undefined) merged[key] = String(body[key])
    }
  }
  const entry = findEntry(path, merged) ?? findEntry(path)
  if (!entry) return null
  const items = collectionOf(path, merged)
  const time = nowIso()
  const item = { id: nextId(items), created_at: time, updated_at: time, ...clone(body) }
  items.unshift(item)
  saveList(entry, items)
  return item
}

/** 更新一条记录 */
function updateRecord(path: string, id: number, body: Json) {
  const entry = findEntry(path)
  if (!entry) return null
  const items = collectionOf(path)
  const target = items.find((item) => Number(item.id) === id)
  if (!target) return null
  Object.assign(target, clone(body), { updated_at: nowIso() })
  saveList(entry, items)
  return target
}

/** 删除一条记录 */
function removeRecord(path: string, id: number) {
  const entry = findEntry(path)
  if (!entry) return false
  const items = collectionOf(path)
  const index = items.findIndex((item) => Number(item.id) === id)
  if (index < 0) return false
  items.splice(index, 1)
  saveList(entry, items)
  return true
}

/** 批量更新 */
function batchUpdate(path: string, ids: number[], fields: Json) {
  const entry = findEntry(path)
  if (!entry) return []
  const items = collectionOf(path)
  const updated = items.filter((item) => ids.includes(Number(item.id)))
  updated.forEach((item) => Object.assign(item, clone(fields), { updated_at: nowIso() }))
  saveList(entry, items)
  return updated
}

/** 批量删除 */
function batchRemove(path: string, ids: number[]) {
  const entry = findEntry(path)
  if (!entry) return false
  const items = collectionOf(path)
  const remain = items.filter((item) => !ids.includes(Number(item.id)))
  saveList(entry, remain)
  return true
}

/** 处理读请求中的特殊接口 */
function handleSpecialRead(path: string, params: Params): Response | null {
  // 饮食热量估算
  if (path === '/health/diet/estimate') {
    const name = params.food_name || ''
    const weight = Number(params.weight_g) || 100
    const record = collectionOf('/health/diet').find((item) => String(item.food_name).includes(name))
    const per100 = record
      ? {
          calories: (Number(record.calories) / Math.max(1, Number(record.weight_g))) * 100,
          protein: (Number(record.protein) / Math.max(1, Number(record.weight_g))) * 100,
          carbs: (Number(record.carbs) / Math.max(1, Number(record.weight_g))) * 100,
          fat: (Number(record.fat) / Math.max(1, Number(record.weight_g))) * 100,
        }
      : { calories: 120, protein: 6, carbs: 18, fat: 3 }
    return jsonResponse({
      calories: Math.round(per100.calories * weight / 100),
      protein: Math.round(per100.protein * weight / 100 * 10) / 10,
      carbs: Math.round(per100.carbs * weight / 100 * 10) / 10,
      fat: Math.round(per100.fat * weight / 100 * 10) / 10,
    })
  }

  // 运动热量估算
  if (path === '/health/fitness/estimate') {
    const type = params.exercise_type || ''
    const duration = Number(params.duration_min) || 30
    const record = collectionOf('/health/fitness').find((item) => String(item.exercise_type) === type)
    const perMinute = record ? Number(record.calories) / Math.max(1, Number(record.duration_min)) : 7
    return jsonResponse({ calories: Math.round(perMinute * duration) })
  }

  // 体检统计：按所选区间从明细实时聚合
  if (path === '/health/checkup/stats') {
    return jsonResponse(computeCheckupStats(params))
  }

  // 旅行报告详情
  const travelDetail = path.match(/^\/finance\/travel\/report\/(\d+)$/)
  if (travelDetail) {
    const id = Number(travelDetail[1])
    const report = collectionOf('/finance/travel/report').find((item) => Number(item.id) === id)
    return report ? jsonResponse(clone(report)) : errorResponse(404, '报告不存在')
  }

  // 旅行报告 PDF 导出
  const travelExport = path.match(/^\/finance\/travel\/report\/(\d+)\/export$/)
  if (travelExport) {
    return fileResponse(
      makePdf('旅行开支报告', [
        'This PDF is generated by the Vercel demo environment.',
        'All data shown in the app is simulated.',
        '',
        `travel report #${travelExport[1]}`,
        'Generated at ' + nowIso(),
      ]),
      `旅行开支报告_${travelExport[1]}.pdf`,
    )
  }

  // 报告详情（支持新生成报告）
  const detailMatch = path.match(/\/(finance|health|lifestyle|investment)\/reports\/(\d+)$/)
  if (detailMatch) {
    const [, kind, id] = detailMatch
    return jsonResponse(reportDetail(kind, Number(id)))
  }

  // 备份文件预览
  const previewMatch = path.match(/^\/backup\/exports\/(.+)\/preview$/)
  if (previewMatch) {
    const filename = decodeURIComponent(previewMatch[1])
    return jsonResponse({
      filename,
      ext: filename.split('.').pop() || 'json',
      size: 2_100_000,
      size_display: '2.1MB',
      content: '{\n  "demo": true,\n  "message": "这是 Vercel 演示环境的模拟备份预览内容",\n  "tables": 42\n}',
      truncated: false,
    })
  }

  // 备份文件下载
  const fileMatch = path.match(/^\/backup\/exports\/(.+)$/)
  if (fileMatch) {
    const filename = decodeURIComponent(fileMatch[1])
    return fileResponse(new Blob(['{"demo":true,"message":"Vercel 演示环境模拟备份文件"}'], { type: 'application/json' }), filename)
  }

  // 报告 PDF 导出
  const exportMatch = path.match(/\/(finance|health|lifestyle|investment)\/reports\/(\d+)\/export$/)
  if (exportMatch) {
    return fileResponse(
      makePdf('LifeOS Demo Report', [
        'This PDF is generated by the Vercel demo environment.',
        'All data shown in the app is simulated.',
        '',
        `${exportMatch[1]} report #${exportMatch[2]}`,
        'Generated at ' + nowIso(),
      ]),
      `demo-report-${exportMatch[2]}.pdf`,
    )
  }

  return null
}

/** 处理写请求中的特殊接口 */
function handleSpecialWrite(path: string, method: string, body: Json, params: Params): Response | null {
  if (method === 'POST' && path === '/auth/login') return handleLogin(body)
  if (method === 'POST' && path === '/auth/refresh') {
    return jsonResponse({ access_token: 'demo-access-token', refresh_token: 'demo-refresh-token', token_type: 'bearer' })
  }
  if (method === 'POST' && path === '/auth/logout') return new Response(null, { status: 204 })
  if (method === 'POST' && path === '/auth/register') {
    return errorResponse(403, '演示环境已关闭注册，请使用演示账号 demo / demo123456 登录')
  }
  if (method === 'GET' && path === '/auth/me') return jsonResponse(clone(findEntry('/auth/me')?.value ?? {}))
  if (method === 'POST' && path === '/auth/sessions/revoke-others') {
    const entry = findEntry('/auth/sessions')
    const current = collectionOf('/auth/sessions').filter((item) => item.is_current)
    if (entry) {
      entry.value = current
      overrides.objects[entry.key] = current
      persist()
    }
    return new Response(null, { status: 204 })
  }

  // 用户资料与设置
  if (path === '/user/profile') {
    const entry = findEntry('/user/profile')
    if (method === 'PUT' && entry) {
      Object.assign(entry.value, clone(body), { updated_at: nowIso() })
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
    if (method === 'GET') return jsonResponse(clone(entry?.value ?? {}))
  }
  if (path === '/user/settings') {
    const entry = findEntry('/user/settings')
    if (method === 'PUT' && entry) {
      Object.assign(entry.value, { has_password: true, updated_at: nowIso() })
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
    if (method === 'GET') return jsonResponse(clone(entry?.value ?? {}))
  }

  // 站点配置
  if (path === '/site-config' && method === 'GET') return jsonResponse(clone(findEntry('/site-config')?.value ?? {}))
  if (path === '/site-config' && method === 'PUT') {
    const entry = findEntry('/site-config')
    if (entry) {
      Object.assign(entry.value, clone(body), { updated_at: nowIso() })
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
  }
  if (path === '/site-config/reset' && method === 'POST') {
    const fallback = {
      site_title: 'LifeOS 演示空间',
      logo: null,
      login_title: '登录 LifeOS 演示空间',
      login_subtitle: '演示账号 demo / demo123456',
      register_title: '加入 LifeOS 演示空间',
      register_subtitle: '演示环境未开放注册',
    }
    const entry = findEntry('/site-config')
    if (entry) {
      entry.value = { ...fallback, updated_at: nowIso() }
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
    return jsonResponse(fallback)
  }

  // 步数设置
  if (path === '/health/steps/settings' && method === 'PUT') {
    const entry = findEntry('/health/steps/settings')
    if (entry) {
      Object.assign(entry.value, clone(body), { updated_at: nowIso() })
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
  }

  // 通知扫描 / 测试发送 / 模板重置
  if (path === '/notifications/scan' && method === 'POST') {
    return jsonResponse({ scanned: 9, created: 0, skipped: 9, sent: 0, failed: 0 })
  }
  if (path === '/notifications/test-send' && method === 'POST') {
    return jsonResponse({ ok: true, message: '演示环境：测试消息已模拟发送成功' })
  }
  const templateReset = path.match(/^\/notifications\/templates\/(\d+)\/reset$/)
  if (templateReset && method === 'POST') {
    return jsonResponse({ ok: true, id: Number(templateReset[1]) })
  }

  // 债务还款
  const debtRepay = path.match(/^\/finance\/debts\/(\d+)\/repay$/)
  if (debtRepay && method === 'POST') {
    const id = Number(debtRepay[1])
    const debt = collectionOf('/finance/debts').find((item) => Number(item.id) === id)
    if (!debt) return errorResponse(404, '债务记录不存在')
    const amount = Number(body.amount) || 0
    const discount = Number(body.discount) || 0
    debt.remaining = Math.max(0, Math.round((Number(debt.remaining) - amount) * 100) / 100)
    if (discount > 0) debt.interest_total = Math.max(0, Number(debt.interest_total) - discount)
    if (debt.remaining <= 0) debt.status = 'settled'
    const entry = findEntry('/finance/debts')
    if (entry) {
      const items = collectionOf('/finance/debts')
      saveList(entry, items)
    }
    const paymentsEntry = findEntry(`/finance/debts/${id}/payments`)
    if (paymentsEntry) {
      const payments = collectionOf(`/finance/debts/${id}/payments`)
      payments.unshift({
        id: nextId(payments),
        debt_id: id,
        repay_date: body.repay_date || today(),
        amount,
        discount,
        note: body.note || null,
        created_at: nowIso(),
      })
      paymentsEntry.value = payments
      overrides.objects[paymentsEntry.key] = payments
      persist()
    }
    return jsonResponse(clone(debt))
  }

  // 手机卡扣账
  const deduct = path.match(/^\/lifestyle\/phone-cards\/(\d+)\/deduct$/)
  if (deduct && method === 'POST') {
    const id = Number(deduct[1])
    const entry = findEntry('/lifestyle/phone-cards')
    const card = collectionOf('/lifestyle/phone-cards').find((item) => Number(item.id) === id)
    if (!card || !entry) return errorResponse(404, '手机卡不存在')
    card.balance = Math.round((Number(card.balance) - Number(card.monthly_fee)) * 100) / 100
    card.bill_paid_this_month = true
    card.updated_at = nowIso()
    saveList(entry, collectionOf('/lifestyle/phone-cards'))
    return jsonResponse(clone(card))
  }

  // 物品同步
  if (path === '/lifestyle/items/sync' && method === 'POST') {
    return jsonResponse({ created: 0, skipped: 16 })
  }

  // 备份相关
  if (path === '/backup/import' && method === 'POST') {
    return jsonResponse({ message: '演示环境已完成模拟导入', total_inserted: 0, tables: {} })
  }
  if (path === '/backup/export' && method === 'POST') {
    return fileResponse(new Blob(['{"demo":true}'], { type: 'application/json' }), 'lifeos_demo_export.json')
  }
  if (path === '/backup/logs' && method === 'DELETE') {
    const entry = findEntry('/backup/logs')
    const count = collectionOf('/backup/logs').length
    if (entry) {
      entry.value.items = []
      entry.value.total = 0
      overrides.lists[entry.key] = []
      persist()
    }
    return jsonResponse({ deleted: count })
  }
  if (path === '/backup/exports' && method === 'DELETE') {
    const keepDays = Number(params.keep_days ?? 0)
    const entry = findEntry('/backup/exports')
    const items = collectionOf('/backup/exports')
    const removed = keepDays > 0 ? Math.max(0, items.length - 3) : 0
    if (entry) {
      const remain = keepDays > 0 ? items.slice(0, 3) : items
      entry.value.items = remain
      entry.value.total = remain.length
      overrides.lists[entry.key] = remain
      persist()
    }
    return jsonResponse({ deleted: removed })
  }

  // 备份计划创建 / 更新 / 启停 / 删除
  if (path === '/backup/schedules' && method === 'POST') {
    const created = createRecord('/backup/schedules', { enabled: true, ...body })
    return created ? jsonResponse(clone(created)) : errorResponse(404, '接口不存在')
  }
  const toggle = path.match(/^\/backup\/schedules\/(\d+)\/toggle$/)
  if (toggle && method === 'POST') {
    const entry = findEntry('/backup/schedules')
    const items = collectionOf('/backup/schedules')
    const target = items.find((item) => Number(item.id) === Number(toggle[1]))
    if (!target || !entry) return errorResponse(404, '备份任务不存在')
    target.enabled = !target.enabled
    entry.value = items
    overrides.objects[entry.key] = items
    persist()
    return jsonResponse(clone(target))
  }

  // 旅行报告生成
  if (path === '/finance/travel/report/generate' && method === 'POST') {
    const entry = findEntry('/finance/travel/report')
    const reports = collectionOf('/finance/travel/report')
    const ledgerId = body.ledger_id === null || body.ledger_id === undefined ? null : Number(body.ledger_id)
    const details = collectAll('/finance/travel/details').filter(
      (item) => ledgerId === null || Number(item.ledger_id) === ledgerId,
    )
    const ledger = collectAll('/finance/travel/ledgers').find((item) => Number(item.id) === ledgerId)
    const total = details.reduce((sum, item) => sum + (Number(item.actual_price) || 0), 0)
    const dates = details.map((item) => String(item.detail_date)).sort()
    const periodStart = dates[0] ?? today()
    const periodEnd = dates[dates.length - 1] ?? today()
    const categories = new Map<string, number>()
    for (const item of details) {
      categories.set(item.category, (categories.get(item.category) ?? 0) + (Number(item.actual_price) || 0))
    }
    const title = `${ledger?.name ?? '全部行程'}旅行开支报告（${periodStart} ~ ${periodEnd}）`
    const summary = `共 ${details.length} 笔消费，合计 ¥${total.toFixed(2)}，覆盖 ${categories.size} 个消费类别。`
    const id = nextId(reports)
    const record = {
      id,
      title,
      ledger_id: ledgerId,
      period_start: periodStart,
      period_end: periodEnd,
      summary,
      created_at: nowIso(),
      content: [
        { type: 'h2', text: '开支概览' },
        {
          type: 'kv',
          rows: [
            ['行程', ledger?.name ?? '全部行程'],
            ['统计区间', `${periodStart} ~ ${periodEnd}`],
            ['记录笔数', `${details.length} 笔`],
            ['合计支出', `¥${total.toFixed(2)}`],
          ],
        },
        { type: 'h2', text: '类别汇总' },
        {
          type: 'table',
          header: ['类别', '金额'],
          rows: Array.from(categories.entries()).map(([name, amount]) => [name, `¥${amount.toFixed(2)}`]),
        },
        { type: 'h2', text: '费用明细' },
        {
          type: 'table',
          header: ['日期', '类别', '项目', '实付金额'],
          rows: details.map((item) => [
            String(item.detail_date),
            String(item.category ?? ''),
            String(item.item ?? ''),
            `¥${(Number(item.actual_price) || 0).toFixed(2)}`,
          ]),
        },
      ],
    }
    reports.unshift(record)
    if (entry) saveList(entry, reports)
    return jsonResponse(record)
  }

  // 报告生成
  const generate = path.match(/^\/(finance|health|lifestyle|investment)\/reports\/generate$/)
  if (generate && method === 'POST') {
    const kind = generate[1]
    const label = periodLabel(body)
    if (kind === 'health') {
      const entry = findEntry('/health/reports')
      const items = collectionOf('/health/reports')
      const id = nextId(items)
      const base = clone(items[0] ?? {})
      const record = {
        ...base,
        id,
        report_date: today(),
        title: `健康报告（${label}）`,
        created_at: nowIso(),
        updated_at: nowIso(),
      }
      items.unshift(record)
      if (entry) saveList(entry, items)
      return jsonResponse(record)
    }
    const entry = findEntry(`/${kind}/reports`)
    const items = collectionOf(`/${kind}/reports`)
    const id = nextId(items)
    const names: Record<string, string> = { finance: '财务报告', lifestyle: '生活报告', investment: '投资报告' }
    const record = { id, title: `${label} ${names[kind]}`, period_label: label, created_at: nowIso() }
    items.unshift(record)
    if (entry) {
      entry.value = items
      overrides.objects[entry.key] = items
      persist()
    }
    const base = findEntry(`/${kind}/reports/1`)
    const detail = clone(base?.value ?? { content: '[]' })
    return jsonResponse({ ...detail, ...record })
  }

  // 通知设置、模板、渠道等单条更新
  const singular = path.match(/^(\/notifications\/(?:settings|templates|channels))\/\d+$/)
  if (singular && method === 'PUT') {
    const basePath = singular[1]
    const id = Number(path.split('/').pop())
    const entry = findEntry(basePath)
    const items = collectionOf(basePath)
    const target = items.find((item) => Number(item.id) === id)
    if (target && entry) {
      Object.assign(target, clone(body), { updated_at: nowIso() })
      entry.value = items
      overrides.objects[entry.key] = items
      persist()
      return jsonResponse(clone(target))
    }
    return errorResponse(404, '记录不存在')
  }
  if (singular && method === 'DELETE') {
    const basePath = singular[1]
    const id = Number(path.split('/').pop())
    const entry = findEntry(basePath)
    const items = collectionOf(basePath)
    const remain = items.filter((item) => Number(item.id) !== id)
    if (entry) {
      entry.value = remain
      overrides.objects[entry.key] = remain
      persist()
    }
    return new Response(null, { status: 204 })
  }

  // 删除报告
  const reportDelete = path.match(/^\/(finance|health|lifestyle|investment)\/reports\/(\d+)$/)
  if (reportDelete && method === 'DELETE') {
    const kind = reportDelete[1]
    const id = Number(reportDelete[2])
    const listPath = `/${kind}/reports`
    const entry = findEntry(listPath)
    if (entry) {
      if (Array.isArray(entry.value)) {
        entry.value = entry.value.filter((item) => Number(item.id) !== id)
        overrides.objects[entry.key] = entry.value
      } else {
        entry.value.items = collectionOf(listPath).filter((item) => Number(item.id) !== id)
        entry.value.total = entry.value.items.length
        overrides.lists[entry.key] = entry.value.items
      }
      persist()
    }
    delete overrides.objects[`${API_PREFIX}/${kind}/reports/${id}`]
    delete overrides.lists[`${API_PREFIX}/${kind}/reports/${id}`]
    persist()
    return new Response(null, { status: 204 })
  }

  return null
}

/** 处理单个 API 请求，返回 Response */
async function handleRequest(pathname: string, search: string, method: string, body: Json): Promise<Response> {
  const path = pathname.startsWith(API_PREFIX) ? pathname.slice(API_PREFIX.length) : pathname
  const params: Params = Object.fromEntries(new URLSearchParams(search))

  const specialWrite = handleSpecialWrite(path, method, body, params)
  if (specialWrite) return specialWrite

  if (method === 'GET') {
    const specialRead = handleSpecialRead(path, params)
    if (specialRead) return specialRead
    const entry = findEntry(path, params)
    if (!entry) return jsonResponse([])
    const value = entry.value
    if (value && Array.isArray(value.items)) return jsonResponse(paginate(value, params))
    if (Array.isArray(value)) return jsonResponse(clone(filterItems(value, params)))
    return jsonResponse(clone(value))
  }

  if (method === 'POST') {
    if (path.endsWith('/batch')) return errorResponse(404, '演示环境暂不支持该操作')
    const created = createRecord(path, body, params)
    if (!created) return errorResponse(404, '接口不存在')
    return jsonResponse(clone(created))
  }

  if (method === 'PUT') {
    const last = path.split('/').pop() || ''
    const id = Number(last)
    if (Number.isFinite(id) && id > 0) {
      const basePath = path.slice(0, path.lastIndexOf('/'))
      const updated = updateRecord(basePath, id, body)
      if (updated) return jsonResponse(clone(updated))
      return errorResponse(404, '记录不存在')
    }
    const entry = findEntry(path, params)
    if (entry && !Array.isArray(entry.value) && typeof entry.value === 'object' && !Array.isArray(entry.value.items)) {
      Object.assign(entry.value, clone(body), { updated_at: nowIso() })
      overrides.objects[entry.key] = entry.value
      persist()
      return jsonResponse(clone(entry.value))
    }
    return errorResponse(404, '接口不存在')
  }

  if (method === 'PATCH' && path.endsWith('/batch')) {
    const basePath = path.slice(0, -'/batch'.length)
    const ids = Array.isArray(body.ids) ? body.ids.map(Number) : []
    const fields = body.fields ?? {}
    return jsonResponse(clone(batchUpdate(basePath, ids, fields)))
  }

  if (method === 'DELETE') {
    if (path.endsWith('/batch')) {
      const basePath = path.slice(0, -'/batch'.length)
      const ids = Array.isArray(body.ids) ? body.ids.map(Number) : []
      batchRemove(basePath, ids)
      return new Response(null, { status: 204 })
    }
    const last = path.split('/').pop() || ''
    const id = Number(last)
    if (Number.isFinite(id) && id > 0) {
      const basePath = path.slice(0, path.lastIndexOf('/'))
      const removed = removeRecord(basePath, id)
      return removed ? new Response(null, { status: 204 }) : errorResponse(404, '记录不存在')
    }
    const entry = findEntry(path, params)
    if (entry && Array.isArray(entry.value)) {
      const count = entry.value.length
      entry.value = []
      overrides.objects[entry.key] = []
      persist()
      return jsonResponse({ deleted: count })
    }
    return jsonResponse({ deleted: 0 })
  }

  return errorResponse(405, '不支持的请求方法')
}

/** 安装 fetch 拦截器，仅在浏览器环境下生效 */
export function installDemoFetch() {
  if (typeof window === 'undefined') return
  const flag = '__lifeosDemoFetchInstalled'
  const globalWindow = window as unknown as Record<string, boolean>
  if (globalWindow[flag]) return
  globalWindow[flag] = true

  const originalFetch = window.fetch.bind(window)
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    let urlText = ''
    let method = 'GET'
    if (typeof input === 'string') {
      urlText = input
      method = init?.method || 'GET'
    } else if (input instanceof URL) {
      urlText = input.toString()
      method = init?.method || 'GET'
    } else {
      urlText = input.url
      method = init?.method || input.method || 'GET'
    }
    const resolved = new URL(urlText, window.location.origin)
    if (!resolved.pathname.startsWith(`${API_PREFIX}/`)) {
      return originalFetch(input as RequestInfo, init)
    }

    let body: Json = {}
    const rawBody = init?.body
    if (typeof rawBody === 'string') {
      try {
        body = JSON.parse(rawBody)
      } catch {
        body = {}
      }
    }

    // 模拟网络延迟，让加载动画有真实的反馈
    await new Promise((resolve) => setTimeout(resolve, 120))
    try {
      return await handleRequest(resolved.pathname, resolved.search.replace(/^\?/, ''), method.toUpperCase(), body)
    } catch (error) {
      return errorResponse(500, error instanceof Error ? error.message : '演示数据处理失败')
    }
  }
}
