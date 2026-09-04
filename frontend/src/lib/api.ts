const BASE = '/api/v1'

const AUTH_EXEMPT = ['/auth/login', '/auth/register']

function authHeaders(extra?: HeadersInit): HeadersInit {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  const token = localStorage.getItem('lifeos_token')
  if (token) headers['Authorization'] = `Bearer ${token}`
  return { ...headers, ...(extra as Record<string, string>) }
}

function handleUnauthorized(path: string) {
  localStorage.removeItem('lifeos_token')
  const current = window.location.pathname
  if (!AUTH_EXEMPT.some((p) => path.startsWith(p)) && !current.startsWith('/login') && !current.startsWith('/register')) {
    window.location.href = '/login'
  }
}

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    headers: authHeaders(options?.headers),
    ...options,
  })
  if (res.status === 401) handleUnauthorized(path)
  if (!res.ok) {
    const body = await res.json().catch(() => null)
    let msg = body?.detail ?? `请求失败（${res.status}）`
    // FastAPI 422 的 detail 是数组/对象，转成可读文本，避免显示 OBJECT
    if (typeof msg === 'object') {
      if (Array.isArray(msg)) {
        msg = msg
          .map((d) => (d && typeof d === 'object' ? `${(d.loc || []).slice(1).join('.')}: ${d.msg || ''}` : String(d)))
          .join('；')
      } else {
        try { msg = JSON.stringify(msg) } catch { msg = String(msg) }
      }
    }
    throw new Error(msg)
  }
  if (res.status === 204) return undefined as T
  return res.json()
}

export type PageResult<T> = {
  items: T[]
  total: number
  page: number
  page_size: number
}

export type ListParams = {
  page?: number
  page_size?: number
  start?: string
  end?: string
  /** 额外的过滤参数（如账本 id、平台 id 等） */
  extra?: Record<string, string | number | undefined>
}

export const api = {
  list: <T>(path: string, params?: ListParams) => {
    const qs = new URLSearchParams()
    if (params?.page) qs.set('page', String(params.page))
    if (params?.page_size) qs.set('page_size', String(params.page_size))
    if (params?.start) qs.set('start', params.start)
    if (params?.end) qs.set('end', params.end)
    if (params?.extra) {
      for (const [k, v] of Object.entries(params.extra)) {
        if (v !== undefined && v !== '') qs.set(k, String(v))
      }
    }
    const query = qs.toString()
    return request<PageResult<T>>(`${path}${query ? `?${query}` : ''}`)
  },
  get: <T>(path: string, id: number) => request<T>(`${path}/${id}`),
  query: <T>(path: string) => request<T>(path),
  create: <T>(path: string, data: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(data) }),
  post: <T>(path: string, data?: unknown) =>
    request<T>(path, {
      method: 'POST',
      body: data ? JSON.stringify(data) : undefined,
    }),
  update: <T>(path: string, id: number, data: unknown) =>
    request<T>(`${path}/${id}`, { method: 'PUT', body: JSON.stringify(data) }),
  put: <T>(path: string, data: unknown) =>
    request<T>(path, { method: 'PUT', body: JSON.stringify(data) }),
  remove: (path: string, id: number) =>
    request<void>(`${path}/${id}`, { method: 'DELETE' }),
  upload: async <T>(path: string, formData: FormData) => {
    const headers: Record<string, string> = {}
    const token = localStorage.getItem('lifeos_token')
    if (token) headers['Authorization'] = `Bearer ${token}`
    const res = await fetch(`${BASE}${path}`, { method: 'POST', headers, body: formData })
    if (res.status === 401) handleUnauthorized(path)
    if (!res.ok) {
      const body = await res.json().catch(() => null)
      throw new Error(body?.detail ?? `上传失败（${res.status}）`)
    }
    return res.json() as Promise<T>
  },
  stats: <T>(path: string, days: number | 'all' = 30) =>
    request<T>(`${path}/stats?days=${days === 'all' ? 0 : days}`),
  download: async (path: string, fallbackName = 'download.pdf') => {
    const headers: Record<string, string> = {}
    const token = localStorage.getItem('lifeos_token')
    if (token) headers['Authorization'] = `Bearer ${token}`
    const res = await fetch(`${BASE}${path}`, { headers })
    if (res.status === 401) handleUnauthorized(path)
    if (!res.ok) {
      const body = await res.json().catch(() => null)
      throw new Error(body?.detail ?? `下载失败（${res.status}）`)
    }
    const blob = await res.blob()
    const disp = res.headers.get('Content-Disposition') || ''
    const match = disp.match(/filename\*=UTF-8''([^;]+)/)
    const filename = match ? decodeURIComponent(match[1]) : fallbackName
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    URL.revokeObjectURL(url)
  },
}
