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
  private isInitialized: boolean = false  // 是否已完成首次连接
  private smartConnectPromise: Promise<ConnectionStatus> | null = null
  private lastSmartConnectStartedAt: number = 0

  // 配置参数
  private readonly CHECK_INTERVAL = 60000  // 60秒检查一次
  private readonly CHECK_TIMEOUT = 10000   // 10秒超时（兼容云中继）
  private readonly FAST_CHECK_TIMEOUT = 3000  // 快速检查 3秒超时
  private readonly CLOUD_RELAY_TIMEOUT = 15000  // 云中继专用超时 15秒
  private readonly GOOD_LATENCY_THRESHOLD = 100  // 100ms 以下为良好
  private readonly POOR_LATENCY_THRESHOLD = 500  // 500ms 以上为差
  private readonly QUICK_START_CHECK_DEBOUNCE = 30000  // 前台恢复 30 秒内不重复探测

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
   * 快速启动：立即使用已配置的 URL，不等待网络检测
   * 后台执行完整的连接优化
   */
  quickStart(): void {
    const serverUrl = authStore.serverUrl
    if (!serverUrl) {
      console.warn('[ConnectionManager] No server URL configured')
      return
    }

    // 立即设置 API 和 WebSocket 地址
    apiService.setBaseUrl(serverUrl)
    wsService.setServerUrl(serverUrl)

    // 根据 URL 类型设置初始状态
    const profile = authStore.activeProfile
    const connType: ConnectionType = (profile?.type as ConnectionType) || 'unknown'

    this.currentStatus = {
      type: connType,
      quality: 'good',  // 先假设良好，后台检测后再更新
      latency: 0,
      lastChecked: Date.now(),
      lanUrl: connType === 'lan' ? serverUrl : '',
      tunnelUrl: connType === 'tunnel' ? serverUrl : '',
      cloudRelayUrl: connType === 'cloud_relay' ? serverUrl : ''
    }
    this.notifyListeners()

    console.info(`[ConnectionManager] Quick start: using ${connType} ${serverUrl}`)

    // 后台执行完整连接检查（不阻塞启动），避免前后台切换时堆积探测请求
    const now = Date.now()
    if (this.smartConnectPromise || now - this.lastSmartConnectStartedAt < this.QUICK_START_CHECK_DEBOUNCE) {
      console.info('[ConnectionManager] Smart connect already running or recently checked, skipping quickStart check')
      return
    }

    setTimeout(() => {
      this.smartConnect().catch((e: Error) => {
        console.error(`[ConnectionManager] Background smart connect error: ${e.message}`)
      })
    }, 100)
  }

  /**
   * 检查是否已初始化
   */
  isReady(): boolean {
    return this.isInitialized
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
   * 端口自动扫描：当配置的 URL 不可用时，扫描同 IP 的其他端口寻找 cchaha 服务器
   * 扫描范围：3456（fixedPort）以及桌面端可能使用的随机端口范围
   */
  private async scanPortsForServer(originalUrl: string): Promise<string | null> {
    // 手动解析 URL 获取 host 和 scheme（ArkTS 不支持 new URL）
    let scheme = 'http'
    let host = ''
    let originalPort = 3456

    if (originalUrl.startsWith('https://')) {
      scheme = 'https'
    }
    const cleaned = originalUrl.replace(/^https?:\/\//, '')
    const colonIdx = cleaned.indexOf(':')
    const slashIdx = cleaned.indexOf('/')
    if (colonIdx > 0 && (slashIdx < 0 || colonIdx < slashIdx)) {
      host = cleaned.substring(0, colonIdx)
      const portEnd = slashIdx > 0 ? slashIdx : cleaned.length
      originalPort = parseInt(cleaned.substring(colonIdx + 1, portEnd)) || 3456
    } else {
      host = slashIdx > 0 ? cleaned.substring(0, slashIdx) : cleaned
    }

    if (!host) return null

    // 构造候选端口列表：3456 优先，然后是桌面端可能使用的端口范围
    const candidatePorts: number[] = [3456]
    if (originalPort !== 3456) {
      candidatePorts.push(originalPort)
    }
    // 桌面端 sidecar 可能的随机端口范围（常见的高位端口）
    const scanRanges = [51000, 52000, 53000, 54000, 55000, 56000, 57000, 58000, 59000, 60000,
      61000, 62000, 40000, 41000, 42000, 43000, 44000, 45000, 46000, 47000, 48000, 49000, 50000]
    for (let i = 0; i < scanRanges.length; i++) {
      if (!candidatePorts.includes(scanRanges[i])) {
        candidatePorts.push(scanRanges[i])
      }
    }

    // 并行扫描所有候选端口，使用较短超时
    const scanTimeout = 3000
    const foundUrls: string[] = []

    const testPromises: Promise<void>[] = []
    for (let i = 0; i < candidatePorts.length; i++) {
      const port = candidatePorts[i]
      const testUrl = scheme + '://' + host + ':' + port
      testPromises.push(
        this.testConnection(testUrl, scanTimeout, 'lan').then(result => {
          if (result.available) {
            foundUrls.push(testUrl)
          }
        }).catch(() => {})
      )
    }

    await Promise.all(testPromises)
    return foundUrls.length > 0 ? foundUrls[0] : null
  }

  /**
   * 并行测试多个 URL，返回最快的可用连接
   * 优化：使用"第一个成功即返回"策略，不等待所有测试完成
   */
  async findBestConnection(urls: string[], urlTypeMap?: Record<string, ConnectionType>): Promise<ConnectionCheckResult | null> {
    if (urls.length === 0) return null

    // 使用 Promise.race 策略：一旦有可用的连接就立即返回
    // 同时记录所有结果用于后续排序选择最优
    const results: ConnectionCheckResult[] = []
    let bestResult: ConnectionCheckResult | null = null

    // 创建所有测试 Promise
    const promises: Promise<void>[] = []
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i]
      const hintType = urlTypeMap ? urlTypeMap[url] : undefined
      // 云中继/隧道使用更长超时
      const timeout = (hintType === 'cloud_relay' || hintType === 'tunnel')
        ? this.CLOUD_RELAY_TIMEOUT
        : this.CHECK_TIMEOUT

      const promise = this.testConnection(url, timeout, hintType).then((result) => {
        results.push(result)
        // 如果是第一个可用的结果，记录为候选
        if (result.available && !bestResult) {
          bestResult = result
          console.info(`[ConnectionManager] First available connection: ${result.type} ${result.url} (${result.latency}ms)`)
        }
      })
      promises.push(promise)
    }

    // 使用 Promise.all 等待，但设置总超时
    const overallTimeout = new Promise<void>((resolve) => {
      setTimeout(() => resolve(), this.CLOUD_RELAY_TIMEOUT + 1000)
    })

    // 等待所有测试完成或超时
    await Promise.race([
      Promise.all(promises),
      overallTimeout
    ])

    // 如果有可用的结果，选择最优的
    const available = results.filter(r => r.available)

    if (available.length === 0) {
      console.warn(`[ConnectionManager] No available connections after testing ${urls.length} URLs`)
      return null
    }

    // 按权重排序，选择最优连接
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
    if (this.smartConnectPromise) {
      console.info('[ConnectionManager] Smart connect already running, reusing current task')
      return this.smartConnectPromise
    }

    this.lastSmartConnectStartedAt = Date.now()
    this.smartConnectPromise = this.smartConnectInternal().then((status: ConnectionStatus) => {
      this.smartConnectPromise = null
      return status
    }).catch((err: Error) => {
      this.smartConnectPromise = null
      throw err
    })
    return this.smartConnectPromise
  }

  private async smartConnectInternal(): Promise<ConnectionStatus> {
    console.info('[ConnectionManager] Starting smart connect...')

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

    // 优化：如果只有一个 URL，直接使用它，跳过测试
    if (urls.length === 1) {
      const singleUrl = urls[0]
      const singleType = urlMap[singleUrl] || 'unknown'
      console.info(`[ConnectionManager] Single URL configured: ${singleType} ${singleUrl}, using directly`)

      // 直接设置并测试连接
      const result = await this.testConnection(singleUrl, this.CLOUD_RELAY_TIMEOUT, singleType)

      if (result.available) {
        await this.switchToUrl(singleUrl, singleType)
        const status: ConnectionStatus = {
          type: singleType,
          quality: result.latency < this.POOR_LATENCY_THRESHOLD ? 'good' : 'poor',
          latency: result.latency,
          lastChecked: Date.now(),
          lanUrl: '',
          tunnelUrl: '',
          cloudRelayUrl: singleType === 'cloud_relay' ? singleUrl : ''
        }
        this.currentStatus = status
        this.isInitialized = true
        this.notifyListeners()
        return status
      }

      // 单 URL 不可用时，尝试同 IP 自动扫描端口
      console.warn(`[ConnectionManager] Single URL ${singleUrl} is not available, trying port scan...`)
      const scannedUrl = await this.scanPortsForServer(singleUrl)
      if (scannedUrl) {
        console.info(`[ConnectionManager] Found server at ${scannedUrl} via port scan`)
        await this.switchToUrl(scannedUrl, singleType)
        // 自动更新保存的 URL，下次就不用再扫描了
        authStore.updateActiveProfileUrl(scannedUrl)
        const scanStatus: ConnectionStatus = {
          type: singleType,
          quality: 'good',
          latency: 0,
          lastChecked: Date.now(),
          lanUrl: '',
          tunnelUrl: '',
          cloudRelayUrl: singleType === 'cloud_relay' ? scannedUrl : ''
        }
        this.currentStatus = scanStatus
        this.isInitialized = true
        this.notifyListeners()
        return scanStatus
      }

      const failStatus: ConnectionStatus = {
        type: singleType,
        quality: 'unavailable',
        latency: -1,
        lastChecked: Date.now(),
        lanUrl: '',
        tunnelUrl: '',
        cloudRelayUrl: singleType === 'cloud_relay' ? singleUrl : ''
      }
      this.currentStatus = failStatus
      this.isInitialized = true
      this.notifyListeners()
      return failStatus
    }

    // 1. 从服务器获取网络信息（多 URL 时才需要）
    try {
      this.lastNetworkInfo = await apiService.getNetworkInfo()
    } catch (e) {
      console.warn('[ConnectionManager] Failed to get network info from server')
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
      this.isInitialized = true
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
      this.isInitialized = true
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
    this.isInitialized = true
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

    // 重连 WebSocket（确保 h5Token 已同步）
    if (authStore.h5Token) {
      wsService.setH5Token(authStore.h5Token)
    }
    wsService.forceReconnectAll()
  }

  /**
   * 快速检查当前连接是否仍然可用
   * 对于云中继使用更长超时
   */
  async quickCheck(): Promise<boolean> {
    const currentUrl = apiService.getBaseUrl()
    if (!currentUrl) return false

    // 根据连接类型选择超时时间
    const currentType = this.currentStatus?.type || 'unknown'
    const timeout = (currentType === 'cloud_relay' || currentType === 'tunnel')
      ? this.CLOUD_RELAY_TIMEOUT
      : this.FAST_CHECK_TIMEOUT

    const result = await this.testConnection(currentUrl, timeout)
    return result.available
  }

  /**
   * 重新检测当前正在使用的连接。
   * 这个方法不做智能切换，也不复用 smartConnect 的后台任务，适合设置页手动测速。
   */
  async retestCurrentConnection(): Promise<ConnectionStatus> {
    const currentUrl = authStore.serverUrl || apiService.getBaseUrl()
    const profile = authStore.activeProfile
    const currentType: ConnectionType = (profile?.type as ConnectionType) || this.currentStatus?.type || 'unknown'

    if (!currentUrl) {
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

    const timeout = (currentType === 'cloud_relay' || currentType === 'tunnel')
      ? this.CLOUD_RELAY_TIMEOUT
      : this.FAST_CHECK_TIMEOUT
    const result = await this.testConnection(currentUrl, timeout, currentType)

    const status: ConnectionStatus = {
      type: currentType,
      quality: result.available ? (result.latency < this.POOR_LATENCY_THRESHOLD ? 'good' : 'poor') : 'unavailable',
      latency: result.available ? result.latency : -1,
      lastChecked: Date.now(),
      lanUrl: currentType === 'lan' || currentType === 'pgy' ? currentUrl : '',
      tunnelUrl: currentType === 'tunnel' ? currentUrl : '',
      cloudRelayUrl: currentType === 'cloud_relay' ? currentUrl : ''
    }

    this.currentStatus = status
    this.notifyListeners()
    return status
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
