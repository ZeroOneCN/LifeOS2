/**
 * 本地开发 HTTPS 证书生成器。
 *
 * Web Bluetooth 要求「安全上下文」（HTTPS 或 localhost），
 * 局域网 IP 通过 http 访问时浏览器会直接屏蔽 navigator.bluetooth，
 * 因此本地开发也需要 HTTPS。
 *
 * 该脚本自动探测本机所有可用 IPv4 与 localhost，生成带 SAN 的自签名证书：
 *   frontend/certs/dev-cert.pem   服务器证书（同时是根证书）
 *   frontend/certs/dev-key.pem    私钥
 *   frontend/certs/san.json       已签发的 IP 列表（用于 IP 变化时自动重签）
 *
 * 若把 dev-cert.pem 导入系统「受信任的根证书颁发机构」，浏览器不再报警告。
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import selfsigned from 'selfsigned'

const CERT_DIR = path.resolve(import.meta.dirname, '../certs')
const CERT_PATH = path.join(CERT_DIR, 'dev-cert.pem')
const KEY_PATH = path.join(CERT_DIR, 'dev-key.pem')
const SAN_PATH = path.join(CERT_DIR, 'san.json')

/** 收集本机需要签入证书的主机名与 IP（排除虚拟网卡与回环段） */
function collectHosts() {
  const hosts = new Set(['localhost', '127.0.0.1'])

  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const addr of addrs ?? []) {
      if (addr.family !== 'IPv4' || addr.internal) continue
      // 过滤 VMware / Hyper-V / WSL 等虚拟网卡，仅保留真实物理网卡地址
      if (/^(VMware|vEthernet|VirtualBox|Hyper-V|Loopback)/i.test(name)) continue
      if (addr.address.startsWith('169.254.')) continue
      hosts.add(addr.address)
    }
  }

  return [...hosts]
}

/** 读取上次签发的主机列表，用于判断是否需要重新签发 */
function readPreviousHosts() {
  try {
    const raw = fs.readFileSync(SAN_PATH, 'utf8')
    return JSON.parse(raw).hosts ?? []
  } catch {
    return []
  }
}

/**
 * 确保证书存在且覆盖当前所有主机地址。
 *
 * @param {boolean} force 为 true 时强制重新生成
 * @returns {Promise<{ key: Buffer, cert: Buffer, hosts: string[], regenerated: boolean, certPath: string }>}
 */
export async function ensureDevCert(force = false) {
  const hosts = collectHosts()
  const previous = readPreviousHosts()
  const sameHosts =
    previous.length === hosts.length && hosts.every((h) => previous.includes(h))
  const filesExist = fs.existsSync(CERT_PATH) && fs.existsSync(KEY_PATH)

  if (!force && filesExist && sameHosts) {
    return {
      key: fs.readFileSync(KEY_PATH),
      cert: fs.readFileSync(CERT_PATH),
      hosts,
      regenerated: false,
      certPath: CERT_PATH,
    }
  }

  const altNames = hosts.map((h) =>
    /^[0-9.]+$/.test(h) ? { type: 7, ip: h } : { type: 2, value: h },
  )

  const pems = await selfsigned.generate(
    [{ name: 'commonName', value: 'LifeOS Dev' }],
    {
      days: 825,
      keySize: 2048,
      algorithm: 'sha256',
      extensions: [
        // 标记为 CA，便于把该证书导入系统受信任根后完全受信
        { name: 'basicConstraints', cA: true },
        { name: 'subjectAltName', altNames },
        {
          name: 'keyUsage',
          digitalSignature: true,
          keyEncipherment: true,
          keyCertSign: true,
        },
        { name: 'extKeyUsage', serverAuth: true },
      ],
    },
  )

  fs.mkdirSync(CERT_DIR, { recursive: true })
  fs.writeFileSync(CERT_PATH, pems.cert)
  fs.writeFileSync(KEY_PATH, pems.private)
  fs.writeFileSync(SAN_PATH, JSON.stringify({ hosts, generatedAt: Date.now() }, null, 2))

  return {
    key: Buffer.from(pems.private),
    cert: Buffer.from(pems.cert),
    hosts,
    regenerated: true,
    certPath: CERT_PATH,
  }
}
