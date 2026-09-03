import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react'

import { api } from '@/lib/api'

const TOKEN_KEY = 'lifeos_token'

export type AuthUser = {
  id: number
  account: string
  username: string | null
  nickname: string
  isAdmin: boolean
  avatar: string | null
  email: string | null
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

type AuthContextValue = {
  user: AuthUser | null
  isAuthed: boolean
  login: (account: string, password: string) => Promise<void>
  register: (account: string, username: string, password: string, nickname?: string) => Promise<void>
  logout: () => void
  refresh: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const isAuthed = !!getToken()

  const refresh = useCallback(async () => {
    if (!getToken()) {
      setUser(null)
      return
    }
    try {
      setUser(await api.query<AuthUser>('/auth/me'))
    } catch {
      setUser(null)
    }
  }, [])

  useEffect(() => {
    refresh()
  }, [refresh])

  const login = useCallback(async (account: string, password: string) => {
    const data = await api.post<{ access_token: string; user: AuthUser }>('/auth/login', {
      account,
      password,
    })
    setToken(data.access_token)
    setUser(data.user)
  }, [])

  const register = useCallback(
    async (account: string, username: string, password: string, nickname?: string) => {
      const data = await api.post<{ access_token: string; user: AuthUser }>(
        '/auth/register',
        { account, username, password, nickname },
      )
      setToken(data.access_token)
      setUser(data.user)
    },
    [],
  )

  const logout = useCallback(() => {
    setToken(null)
    setUser(null)
    window.location.href = '/login'
  }, [])

  const value = useMemo(
    () => ({ user, isAuthed, login, register, logout, refresh }),
    [user, isAuthed, login, register, logout, refresh],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth 必须在 AuthProvider 内使用')
  return ctx
}