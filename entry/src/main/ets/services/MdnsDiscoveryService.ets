/**
 * mDNS 发现服务
 * 扫描局域网内的 cc-haha桌面端服务器
 */

import mdns from '@ohos.net.mdns'
import { DiscoveredServer, ServerDiscoverListener } from '../models/Models'

const SERVICE_TYPE = '_cc-haha._tcp'

function buildUrl(host: string, port: number): string {
  // IPv6 地址需要加括号: http://[fe80::1]:3456
  if (host.includes(':')) {
    return `http://[${host}]:${port}`
  }
  return `http://${host}:${port}`
}

function extractName(serviceName: string): string {
  return serviceName
    .replace(`.${SERVICE_TYPE}.local.`, '')
    .replace(`.${SERVICE_TYPE}`, '')
    .replace('.local.', '')
}

export class MdnsDiscoveryService {
  private discoveryService: mdns.DiscoveryService | null = null
  private listener: ServerDiscoverListener | null = null
  private discoveredServers: Map<string, DiscoveredServer> = new Map()

  setListener(listener: ServerDiscoverListener): void {
    this.listener = listener
  }

  getDiscoveredServers(): DiscoveredServer[] {
    const result: DiscoveredServer[] = []
    this.discoveredServers.forEach((server) => {
      result.push(server)
    })
    return result
  }

  startDiscovery(context: Context): void {
    if (this.discoveryService) {
      console.info('[mDNS] Already discovering')
      return
    }

    try {
      this.discoveryService = mdns.createDiscoveryService(context, SERVICE_TYPE)

      // 注册服务发现监听器
      this.discoveryService.on('serviceFound', (serviceInfo: mdns.LocalServiceInfo) => {
        console.info(`[mDNS] Service found: ${serviceInfo.serviceName}`)
        const port = serviceInfo.port ?? 0
        const hostAddr = serviceInfo.host
        const ip = hostAddr?.address ?? ''

        // 记录原始数据用于调试
        console.info(`[mDNS] Raw info: host=${JSON.stringify(hostAddr)}, port=${port}, ip=${ip}`)

        // 跳过无效数据
        if (!ip || port === 0) {
          console.warn(`[mDNS] Skipping invalid server: ip=${ip}, port=${port}`)
          return
        }

        const url = buildUrl(ip, port)
        const name = extractName(serviceInfo.serviceName)

        console.info(`[mDNS] Built URL: ${url}, name: ${name}`)

        const server: DiscoveredServer = {
          id: serviceInfo.serviceName,
          name: name,
          ip: ip,
          port: port,
          url: url,
          host: ip
        }
        this.discoveredServers.set(server.id, server)
        if (this.listener) {
          this.listener.onServerFound(server)
        }
      })

      this.discoveryService.on('serviceLost', (serviceInfo: mdns.LocalServiceInfo) => {
        console.info(`[mDNS] Service lost: ${serviceInfo.serviceName}`)
        this.discoveredServers.delete(serviceInfo.serviceName)
        if (this.listener) {
          this.listener.onServerLost(serviceInfo.serviceName)
        }
      })

      // 开始搜索
      this.discoveryService.startSearchingMDNS()

      if (this.listener) {
        this.listener.onSearchStateChange(true)
      }
    } catch (e) {
      console.error(`[mDNS] Start discovery error: ${e}`)
      this.discoveryService = null
    }
  }

  stopDiscovery(): void {
    if (!this.discoveryService) return
    try {
      this.discoveryService.stopSearchingMDNS()
    } catch (e) {
      console.error(`[mDNS] Stop discovery error: ${e}`)
    }
    this.discoveryService = null
    this.discoveredServers.clear()
    if (this.listener) {
      this.listener.onSearchStateChange(false)
    }
  }
}

export const mdnsDiscoveryService = new MdnsDiscoveryService()