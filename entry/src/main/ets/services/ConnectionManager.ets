/**
 * 智能连接管理器
 * 实现 LAN 优先、Tunnel 回退的自动切换逻辑
 */

import http from '@ohos.net.http'
import { authStore } from '../stores/AuthStore'
import { apiService } from './APIService'
import { wsService } from './WebSocketService'
import { NetworkInfo } from '../models/Models'

export type ConnectionType = 'lan' | 'pgy' | 'tunnel' | 'cloud_relay' | 'unknown'
export type ConnectionQuality = 'good' | 'poor' | 'unavailable'

export interface ConnectionStatus {
  type: ConnectionType
  quality: ConnectionQuality
  latency: number  // ms, -1 表示不可用
  lastChecked: number
  lanUrl: string
  tunnelUrl: string
  cloudRelayUrl: string
}

export interface ConnectionCheckResult {
  url: string
  available: boolean
  latency: number  // ms
  type: ConnectionType
}

type ConnectionChangeListener = (status: ConnectionStatus) => void

export class ConnectionManager {
  private static instance: ConnectionManager
  private currentStatus: ConnectionStatus | null = null
  private checkTimer: number = -1
  private listeners: ConnectionChangeListener[] = []
  private lastNetworkInfo: NetworkInfo | null = null

  // 配置参数
  private readonly CHECK_INTERVAL = 60000  // 60秒检查一次
  private readonly CHECK_TIMEOUT = 5000    // 5秒超时
  private readonly FAST_CHECK_TIMEOUT = 2000  // 快速检查 2秒超时
  private readonly GOOD_LATENCY_THRESHOLD = 100  // 100ms 以下为良好
  private readonly POOR_LATENCY_THRESHOLD = 500  // 500ms 以上为差

  static getInstance(): ConnectionManager {
    if (!ConnectionManager.instance) {
      ConnectionManager.instance = new ConnectionManager()
    }
    return ConnectionManager.instance
  }

  /**
   * 添加连接状态变化监听器
   */
  addListener(listener: ConnectionChangeListener): void {
    this.listeners.push(listener)
  }

  /**
   * 移除连接状态变化监听器
   */
  removeListener(listener: ConnectionChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }

  private notifyListeners(): void {
    if (this.currentStatus) {
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentStatus)
      }
    }
  }

  /**
   * 获取当前连接状态
   */
  getStatus(): ConnectionStatus | null {
    return this.currentStatus
  }

  /**
   * 启动定期连接检查
   */
  startPeriodicCheck(): void {
    this.stopPeriodicCheck()
    // 立即检查一次
    this.smartConnect()
    // 启动定期检查
    this.checkTimer = setInterval(() => {
      this.smartConnect()
    }, this.CHECK_INTERVAL)
    console.info('[ConnectionManager] Started periodic check')
  }

  /**
   * 停止定期连接检查
   */
  stopPeriodicCheck(): void {
    if (this.checkTimer >= 0) {
      clearInterval(this.checkTimer)
      this.checkTimer = -1
    }
  }

  /**
   * 测试单个 URL 的连通性
   */
  async testConnection(url: string, timeout: number = this.CHECK_TIMEOUT, hintType?: ConnectionType): Promise<ConnectionCheckResult> {
    const startTime = Date.now()
    const httpRequest = http.createHttp()

    try {
      // 使用 sessions 接口检测连通性（HEAD 请求更快）
      // 如果服务端不支持 HEAD，则使用 GET
      const testUrl = url + '/api/sessions'

      const response = await httpRequest.request(testUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: timeout,
        readTimeout: timeout,
        header: {
          'Accept': 'application/json'
        }
      })

      const latency = Date.now() - startTime

      // 200-299 表示成功，401 也表示服务器可达（只是需要认证）
      if (response.responseCode >= 200 && response.responseCode < 500) {
        return {
          url: url,
          available: true,
          latency: latency,
          type: hintType || (url.startsWith('https://') ? 'tunnel' : 'lan')
        }
      }

      return {
        url: url,
        available: false,
        latency: -1,
        type: hintType || (url.startsWith('https://') ? 'tunnel' : 'lan')
      }
    } catch (e) {
      const err = e as Error
      console.warn(`[ConnectionManager] Test ${url} failed: ${err.message}`)
      return {
        url: url,
        available: false,
        latency: -1,
        type: hintType || (url.startsWith('https://') ? 'tunnel' : 'lan')
      }
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 并行测试多个 URL，返回最快的可用连接
   */
  async findBestConnection(urls: string[], urlTypeMap?: Record<string, ConnectionType>): Promise<ConnectionCheckResult | null> {
    if (urls.length === 0) return null

    // 并行测试所有 URL
    const promises: Promise<ConnectionCheckResult>[] = []
    for (let i = 0; i < urls.length; i++) {
      const hintType = urlTypeMap ? urlTypeMap[urls[i]] : undefined
      promises.push(this.testConnection(urls[i], this.CHECK_TIMEOUT, hintType))
    }

    const results = await Promise.all(promises)

    // 找出所有可用连接
    const available = results.filter(r => r.available)

    if (available.length === 0) {
      return null
    }

    // 按权重排序，优先选择权重高的连接类型
    // 权重: LAN/Pgy > cloud_relay > tunnel
    available.sort((a, b) => {
      const weight = (type: ConnectionType): number => {
        switch (type) {
          case 'lan':
          case 'pgy': return 3
          case 'cloud_relay': return 2
          case 'tunnel': return 1
          default: return 0
        }
      }
      const aWeight = weight(a.type)
      const bWeight = weight(b.type)

      // 如果类型相同或权重相同，按延迟排序
      if (aWeight === bWeight) {
        return a.latency - b.latency
      }

      // LAN/Pgy 且延迟良好 → 绝对优先
      if ((a.type === 'lan' || a.type === 'pgy') && a.latency < this.GOOD_LATENCY_THRESHOLD * 2) return -1
      if ((b.type === 'lan' || b.type === 'pgy') && b.latency < this.GOOD_LATENCY_THRESHOLD * 2) return 1

      // cloud_relay 比 tunnel 优先（延迟通常更低）
      if (a.type === 'cloud_relay' && b.type === 'tunnel') return -1
      if (a.type === 'tunnel' && b.type === 'cloud_relay') return 1

      // 否则按延迟
      return a.latency - b.latency
    })

    return available[0]
  }

  /**
   * 智能连接：自动选择最佳连接方式
   * LAN 优先，Tunnel 回退
   */
  async smartConnect(): Promise<ConnectionStatus> {
    console.info('[ConnectionManager] Starting smart connect...')

    // 1. 从服务器获取网络信息
    try {
      this.lastNetworkInfo = await apiService.getNetworkInfo()
    } catch (e) {
      console.warn('[ConnectionManager] Failed to get network info from server')
    }

    // 2. 收集可用的 URL 列表
    const urls: string[] = []
    const urlMap: Record<string, ConnectionType> = {}

    // 从 AuthStore 获取已配置的 URL
    const profiles = authStore.serverProfiles
    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i]
      if (profile.url && !urls.includes(profile.url)) {
        urls.push(profile.url)
        urlMap[profile.url] = profile.type as ConnectionType
      }
    }

    // 从网络信息补充
    if (this.lastNetworkInfo) {
      if (this.lastNetworkInfo.lanUrl && !urls.includes(this.lastNetworkInfo.lanUrl)) {
        urls.push(this.lastNetworkInfo.lanUrl)
        urlMap[this.lastNetworkInfo.lanUrl] = 'lan'
      }
      if (this.lastNetworkInfo.cloudRelayUrl && !urls.includes(this.lastNetworkInfo.cloudRelayUrl)) {
        urls.push(this.lastNetworkInfo.cloudRelayUrl)
        urlMap[this.lastNetworkInfo.cloudRelayUrl] = 'cloud_relay'
      }
      if (this.lastNetworkInfo.tunnelUrl && this.lastNetworkInfo.tunnelEnabled &&
          !urls.includes(this.lastNetworkInfo.tunnelUrl)) {
        urls.push(this.lastNetworkInfo.tunnelUrl)
        urlMap[this.lastNetworkInfo.tunnelUrl] = 'tunnel'
      }
    }

    if (urls.length === 0) {
      console.warn('[ConnectionManager] No URLs to check')
      const status: ConnectionStatus = {
        type: 'unknown',
        quality: 'unavailable',
        latency: -1,
        lastChecked: Date.now(),
        lanUrl: '',
        tunnelUrl: '',
        cloudRelayUrl: ''
      }
      this.currentStatus = status
      this.notifyListeners()
      return status
    }

    console.info(`[ConnectionManager] Checking ${urls.length} URLs...`)

    // 3. 并行测试所有 URL，找出最佳连接
    const best = await this.findBestConnection(urls, urlMap)

    if (!best) {
      console.warn('[ConnectionManager] No available connection')
      const status: ConnectionStatus = {
        type: 'unknown',
        quality: 'unavailable',
        latency: -1,
        lastChecked: Date.now(),
        lanUrl: this.lastNetworkInfo?.lanUrl || '',
        tunnelUrl: this.lastNetworkInfo?.tunnelUrl || '',
        cloudRelayUrl: this.lastNetworkInfo?.cloudRelayUrl || ''
      }
      this.currentStatus = status
      this.notifyListeners()
      return status
    }

    // 4. 更新连接状态
    let quality: ConnectionQuality = 'good'
    if (best.latency > this.POOR_LATENCY_THRESHOLD) {
      quality = 'poor'
    } else if (best.latency > this.GOOD_LATENCY_THRESHOLD) {
      quality = 'poor'  // 中等也标记为 poor，便于监控
    }

    const status: ConnectionStatus = {
      type: best.type,
      quality: quality,
      latency: best.latency,
      lastChecked: Date.now(),
      lanUrl: this.lastNetworkInfo?.lanUrl || '',
      tunnelUrl: this.lastNetworkInfo?.tunnelUrl || '',
      cloudRelayUrl: this.lastNetworkInfo?.cloudRelayUrl || ''
    }

    // 5. 如果连接发生变化，切换到最佳连接
    const needSwitch = this.shouldSwitchConnection(best)
    if (needSwitch) {
      console.info(`[ConnectionManager] Switching to ${best.type}: ${best.url} (${best.latency}ms)`)
      await this.switchToUrl(best.url, best.type)
    }

    this.currentStatus = status
    this.notifyListeners()

    console.info(`[ConnectionManager] Connected via ${best.type}, latency: ${best.latency}ms, quality: ${quality}`)
    return status
  }

  /**
   * 判断是否需要切换连接
   */
  private shouldSwitchConnection(best: ConnectionCheckResult): boolean {
    // 如果当前没有连接，需要切换
    if (!this.currentStatus || this.currentStatus.quality === 'unavailable') {
      return true
    }

    // 如果当前 URL 和最佳 URL 不同
    const currentUrl = apiService.getBaseUrl()
    if (currentUrl !== best.url) {
      const current = this.currentStatus.type

      // 任何连接 → LAN/Pgy（局域网可用时始终切换）
      if (best.type === 'lan' || best.type === 'pgy') return true

      // Tunnel → cloud_relay（云中继通常更快）
      if (current === 'tunnel' && best.type === 'cloud_relay') return true

      // cloud_relay → Tunnel（不切换，cloud_relay 更快）
      if (current === 'cloud_relay' && best.type === 'tunnel') return false

      // 当前延迟很高，新的延迟低很多 → 切换
      if (this.currentStatus.latency > this.POOR_LATENCY_THRESHOLD &&
          best.latency < this.GOOD_LATENCY_THRESHOLD) {
        return true
      }
    }

    return false
  }

  /**
   * 切换到指定 URL
   */
  private async switchToUrl(url: string, type: ConnectionType): Promise<void> {
    // 更新 API 服务
    apiService.setBaseUrl(url)

    // 更新 WebSocket 服务
    wsService.setServerUrl(url)

    // 尝试找到对应的 profile 并切换
    const profiles = authStore.serverProfiles
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].url === url) {
        await authStore.switchProfile(profiles[i].id)
        break
      }
    }

    // 重连 WebSocket
    wsService.forceReconnectAll()
  }

  /**
   * 快速检查当前连接是否仍然可用
   */
  async quickCheck(): Promise<boolean> {
    const currentUrl = apiService.getBaseUrl()
    if (!currentUrl) return false

    const result = await this.testConnection(currentUrl, this.FAST_CHECK_TIMEOUT)
    return result.available
  }

  /**
   * 强制使用 Tunnel（用户手动切换时）
   */
  async forceTunnel(): Promise<boolean> {
    if (!this.lastNetworkInfo?.tunnelUrl || !this.lastNetworkInfo?.tunnelEnabled) {
      // 尝试从配置获取
      const tunnelProfile = authStore.serverProfiles.find(p => p.type === 'tunnel')
      if (!tunnelProfile) {
        console.warn('[ConnectionManager] No tunnel URL configured')
        return false
      }
      await this.switchToUrl(tunnelProfile.url, 'tunnel')
      return true
    }

    await this.switchToUrl(this.lastNetworkInfo.tunnelUrl, 'tunnel')
    return true
  }

  /**
   * 强制使用 LAN（用户手动切换时）
   */
  async forceLan(): Promise<boolean> {
    const lanProfile = authStore.serverProfiles.find(p => p.type === 'lan')
    if (!lanProfile && !this.lastNetworkInfo?.lanUrl) {
      console.warn('[ConnectionManager] No LAN URL configured')
      return false
    }

    const url = lanProfile?.url || this.lastNetworkInfo?.lanUrl
    if (!url) return false

    // 先测试是否可用
    const result = await this.testConnection(url)
    if (!result.available) {
      console.warn('[ConnectionManager] LAN not available')
      return false
    }

    await this.switchToUrl(url, 'lan')
    return true
  }

  /**
   * 获取连接类型显示名称
   */
  getConnectionTypeName(type: ConnectionType): string {
    switch (type) {
      case 'lan':
      case 'pgy': return '局域网'
      case 'tunnel': return '远程隧道'
      case 'cloud_relay': return '云中继'
      default: return '未知'
    }
  }

  /**
   * 强制使用云中继（用户手动切换时）
   */
  async forceCloudRelay(): Promise<boolean> {
    const relayProfile = authStore.serverProfiles.find(p => p.type === 'cloud_relay')
    if (!relayProfile && !this.lastNetworkInfo?.cloudRelayUrl) {
      console.warn('[ConnectionManager] No cloud relay URL configured')
      return false
    }

    const url = relayProfile?.url || this.lastNetworkInfo?.cloudRelayUrl
    if (!url) return false

    // 先测试是否可用
    const result = await this.testConnection(url)
    if (!result.available) {
      console.warn('[ConnectionManager] Cloud relay not available')
      return false
    }

    await this.switchToUrl(url, 'cloud_relay')
    return true
  }

  /**
   * 获取连接质量显示名称
   */
  getQualityName(quality: ConnectionQuality): string {
    switch (quality) {
      case 'good': return '良好'
      case 'poor': return '较差'
      default: return '不可用'
    }
  }
}

export const connectionManager = ConnectionManager.getInstance()
