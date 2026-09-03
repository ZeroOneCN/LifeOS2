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