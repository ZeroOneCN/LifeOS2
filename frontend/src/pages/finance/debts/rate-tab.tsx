import { useState } from 'react'
import { toast } from 'sonner'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'

import type { Currency } from './shared'

/* ---------------- 汇率设置 ---------------- */

export function RateTab({ currencies, setCurrencies, currency, setCurrency }: {
  currencies: Currency[]
  setCurrencies: (c: Currency[]) => void
  currency: Currency | null
  setCurrency: (c: Currency) => void
}) {
  const { dialog: confirmDialog } = useConfirm({ title: '确认删除', description: '确定删除这个币种吗？' })
  const [editing, setEditing] = useState<Currency | null>(null)
  const [rateValue, setRateValue] = useState('')

  const saveRate = async () => {
    if (!editing) return
    const v = Number(rateValue)
    if (!v || v <= 0) return
    try {
      const updated = await api.update<Currency>('/finance/currencies', editing.id, {
        currency: editing.currency, name: editing.name, symbol: editing.symbol, rate_to_cny: v,
      })
      setCurrencies(currencies.map((c) => (c.id === updated.id ? updated : c)))
      setEditing(null)
      toast.success('汇率已更新')
    } catch (e) {
      toast.error('更新失败', {
        description: e instanceof Error ? e.message : '请稍后重试',
      })
    }
  }
  const resetToCny = () => {
    const c = currencies.find((x) => x.currency === 'CNY')
    if (c) setCurrency(c)
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">币种与汇率（相对人民币）</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {currencies.map((c) => (
            <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border px-3 py-2 text-sm">
              <span className="flex items-center gap-2">
                <b>{c.name ?? c.currency}</b>
                <Badge variant="outline">{c.symbol ?? ''}{c.currency}</Badge>
              </span>
              <span className="flex items-center gap-2">
                {editing?.id === c.id ? (
                  <>
                    <Input className="w-28" type="number" step="0.0001" value={rateValue} onChange={(e) => setRateValue(e.target.value)} />
                    <Button size="sm" onClick={saveRate}>保存</Button>
                    <Button size="sm" variant="outline" onClick={() => setEditing(null)}>取消</Button>
                  </>
                ) : (
                  <>
                    <span className="text-muted-foreground">1 {c.currency} ≈ {c.rate_to_cny} 人民币</span>
                    <Button size="sm" variant="outline" onClick={() => { setEditing(c); setRateValue(String(c.rate_to_cny)) }}>编辑</Button>
                  </>
                )}
                {c.currency === 'CNY' && (
                  <Button size="sm" variant="ghost" onClick={resetToCny}>当前显示：人民币</Button>
                )}
                {c.currency !== 'CNY' && (
                  <Button size="sm" variant="ghost" onClick={() => setCurrency(c)} className={currency?.currency === c.currency ? 'text-decor-indigo' : ''}>
                    {currency?.currency === c.currency ? '当前显示' : '设为显示'}
                  </Button>
                )}
              </span>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">{currency ? `${currency.name ?? currency.currency}（${currency.symbol ?? ''}）显示` : '显示币种'}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-1.5 text-sm">
          <p className="text-muted-foreground">
            当前以 <b>{currency?.name ?? '人民币'}</b> 显示页面金额。所有金额以人民币存储，切换币种仅改变显示换算。
          </p>
          <div className="flex flex-wrap items-center gap-2">
            {currencies.map((c) => (
              <Button key={c.id} size="sm" variant={currency?.currency === c.currency ? 'default' : 'outline'} onClick={() => setCurrency(c)}>
                {c.name ?? c.currency}
              </Button>
            ))}
          </div>
        </CardContent>
      </Card>
      {confirmDialog}
    </div>
  )
}
