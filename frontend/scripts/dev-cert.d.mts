/** dev-cert.mjs 的类型声明 */

export interface DevCert {
  key: Buffer
  cert: Buffer
  /** 证书覆盖的主机名 / IP 列表 */
  hosts: string[]
  /** 本次是否重新生成 */
  regenerated: boolean
  /** 证书文件路径 */
  certPath: string
}

/**
 * 确保证书存在且覆盖当前所有主机地址。
 *
 * @param force 为 true 时强制重新生成
 */
export declare function ensureDevCert(force?: boolean): Promise<DevCert>
