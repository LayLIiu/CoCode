/**
 * mDNS 发现服务
 * 扫描局域网内的 cc-haha桌面端服务器
 */

import mdns from '@ohos.net.mdns'
import { DiscoveredServer, ServerDiscoverListener } from '../models/Models'

const SERVICE_TYPE = '_cc-haha._tcp'

export class MdnsDiscoveryService {
  private discoveryManager: mdns.DiscoveryManager | null = null
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
    if (this.discoveryManager) {
      console.info('[mDNS] Already discovering')
      return
    }

    try {
      this.discoveryManager = mdns.createDiscoveryManager(context)
      this.discoveryManager.startSearching(SERVICE_TYPE, {
        onServiceFound: (service: mdns.DiscoveredService) => {
          console.info(`[mDNS] Service found: ${service.serviceName}`)
          const addresses = service.addresses || []
          const ip = addresses.length > 0 ? addresses[0].address : service.host
          const server: DiscoveredServer = {
            id: service.serviceId,
            name: service.serviceName.replace(`.${SERVICE_TYPE}.local.`, '').replace(`.${SERVICE_TYPE}`, ''),
            ip: ip,
            port: service.port,
            url: `http://${ip}:${service.port}`,
            host: service.host
          }
          this.discoveredServers.set(server.id, server)
          if (this.listener) {
            this.listener.onServerFound(server)
          }
        },
        onServiceLost: (service: mdns.DiscoveredService) => {
          console.info(`[mDNS] Service lost: ${service.serviceName}`)
          this.discoveredServers.delete(service.serviceId)
          if (this.listener) {
            this.listener.onServerLost(service.serviceId)
          }
        },
        onStartSearching: () => {
          console.info('[mDNS] Start searching')
          if (this.listener) {
            this.listener.onSearchStateChange(true)
          }
        },
        onStopSearching: () => {
          console.info('[mDNS] Stop searching')
          if (this.listener) {
            this.listener.onSearchStateChange(false)
          }
        }
      })
    } catch (e) {
      console.error(`[mDNS] Start discovery error: ${e}`)
      this.discoveryManager = null
    }
  }

  stopDiscovery(): void {
    if (!this.discoveryManager) return
    try {
      this.discoveryManager.stopSearching(SERVICE_TYPE)
    } catch (e) {
      console.error(`[mDNS] Stop discovery error: ${e}`)
    }
    this.discoveryManager = null
    this.discoveredServers.clear()
  }
}

export const mdnsDiscoveryService = new MdnsDiscoveryService()