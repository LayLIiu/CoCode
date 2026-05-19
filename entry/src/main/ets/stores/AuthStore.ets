/**
 * 认证状态管理
 * 支持多服务器配置（局域网、蒲公英、公网隧道）
 */

import preferences from '@ohos.data.preferences'
import { User, ServerMode, ServerProfile } from '../models/Models'
import { apiService } from '../services/APIService'
import { wsService } from '../services/WebSocketService'
import { UrlUtils } from '../common/UrlUtils'

export class AuthStore {
  private static instance: AuthStore
  private context?: Context

  // 状态
  user: User | null = null
  isLoggedIn: boolean = false

  // 生物识别锁屏
  isLocked: boolean = false
  biometricEnabled: boolean = true

  // 兼容旧版字段（单服务器）
  lanUrl: string = ''
  tunnelUrl: string = ''
  serverMode: ServerMode = 'lan'

  // 新版多服务器配置
  serverProfiles: ServerProfile[] = []
  activeProfileId: string = ''

  private preferences?: preferences.Preferences

  static getInstance(): AuthStore {
    if (!AuthStore.instance) {
      AuthStore.instance = new AuthStore()
    }
    return AuthStore.instance
  }

  async setContext(context: Context): Promise<void> {
    this.context = context
    await this.loadSavedData()
  }

  private async loadSavedData(): Promise<void> {
    if (!this.context) return

    try {
      this.preferences = await preferences.getPreferences(this.context, 'auth_store')

      // 加载旧版配置（向后兼容）
      this.lanUrl = await this.preferences.get('lanUrl', '') as string
      this.tunnelUrl = await this.preferences.get('tunnelUrl', '') as string
      this.serverMode = await this.preferences.get('serverMode', 'lan') as ServerMode

      // 加载新版多服务器配置
      const profilesData = await this.preferences.get('serverProfiles', '') as string
      if (profilesData) {
        this.serverProfiles = JSON.parse(profilesData) as ServerProfile[]
      }
      this.activeProfileId = await this.preferences.get('activeProfileId', '') as string

      // 加载生物识别设置
      this.biometricEnabled = await this.preferences.get('biometricEnabled', true) as boolean

      // 恢复用户信息
      const userData = await this.preferences.get('userData', '') as string
      if (userData) {
        this.user = JSON.parse(userData) as User
        this.isLoggedIn = true
      }

      // 更新 API 服务地址
      this.updateApiServiceUrl()

      console.info(`[AuthStore] Loaded: ${this.serverProfiles.length} profiles, active=${this.activeProfileId}`)
    } catch (e) {
      console.error(`[AuthStore] Load error: ${e}`)
    }
  }

  get serverUrl(): string {
    // 优先使用新版多配置
    if (this.activeProfileId) {
      const profile = this.serverProfiles.find(p => p.id === this.activeProfileId)
      if (profile) return profile.url
    }
    // 回退旧版
    return this.serverMode === 'lan' ? this.lanUrl : this.tunnelUrl
  }

  get activeProfile(): ServerProfile | null {
    if (!this.activeProfileId) return null
    return this.serverProfiles.find(p => p.id === this.activeProfileId) || null
  }

  /**
   * 添加服务器配置
   */
  async addProfile(name: string, url: string, type: 'lan' | 'pgy' | 'tunnel'): Promise<string> {
    const id = 'server_' + Date.now()
    const profile: ServerProfile = {
      id: id,
      name: name,
      url: UrlUtils.normalizeUrl(url),
      type: type,
      lastUsed: Date.now()
    }
    this.serverProfiles = [...this.serverProfiles, profile]
    await this.saveProfiles()
    return id
  }

  /**
   * 删除服务器配置
   */
  async removeProfile(id: string): Promise<void> {
    this.serverProfiles = this.serverProfiles.filter(p => p.id !== id)
    if (this.activeProfileId === id) {
      this.activeProfileId = this.serverProfiles.length > 0 ? this.serverProfiles[0].id : ''
    }
    await this.saveProfiles()
    if (this.activeProfileId) {
      this.updateApiServiceUrl()
    }
  }

  /**
   * 切换服务器配置
   */
  async switchProfile(id: string): Promise<void> {
    const profile = this.serverProfiles.find(p => p.id === id)
    if (!profile) return

    this.activeProfileId = id
    profile.lastUsed = Date.now()
    await this.saveProfiles()
    this.updateApiServiceUrl()
  }

  /**
   * 更新服务器配置 URL
   */
  async updateProfileUrl(id: string, url: string): Promise<void> {
    const profile = this.serverProfiles.find(p => p.id === id)
    if (!profile) return

    profile.url = UrlUtils.normalizeUrl(url)
    profile.lastUsed = Date.now()
    await this.saveProfiles()
    if (this.activeProfileId === id) {
      this.updateApiServiceUrl()
    }
  }

  /**
   * 更新服务器配置名称
   */
  async updateProfileName(id: string, name: string): Promise<void> {
    const profile = this.serverProfiles.find(p => p.id === id)
    if (!profile) return
    profile.name = name
    await this.saveProfiles()
  }

  /**
   * 登录时自动添加配置（兼容旧版登录流程）
   */
  async addFromLogin(url: string): Promise<void> {
    const normalized = UrlUtils.normalizeUrl(url)

    // 检查是否已有相同 URL 的配置
    const existing = this.serverProfiles.find(p => p.url === normalized)
    if (existing) {
      await this.switchProfile(existing.id)
      return
    }

    // 判断连接类型
    let type: 'lan' | 'pgy' | 'tunnel' = 'lan'
    if (normalized.startsWith('https://')) {
      type = 'tunnel'
    } else if (normalized.includes('10.') || normalized.includes('172.')) {
      type = 'pgy'
    }

    // 生成默认名称
    const count = this.serverProfiles.length + 1
    let name = type === 'tunnel' ? `隧道 ${count}` : type === 'pgy' ? `蒲公英 ${count}` : `局域网 ${count}`

    await this.addProfile(name, normalized, type)
    // 自动切换到新配置
    await this.switchProfile(this.serverProfiles[this.serverProfiles.length - 1].id)

    // 同步旧版字段（兼容）
    if (type === 'tunnel') {
      this.tunnelUrl = normalized
    } else {
      this.lanUrl = normalized
    }
  }

  private async saveProfiles(): Promise<void> {
    if (!this.preferences) return
    await this.preferences.put('serverProfiles', JSON.stringify(this.serverProfiles))
    await this.preferences.put('activeProfileId', this.activeProfileId)
    await this.preferences.flush()
  }

  // 以下为旧版兼容方法

  async setLanUrl(url: string): Promise<void> {
    this.lanUrl = UrlUtils.normalizeUrl(url)
    if (this.preferences) {
      await this.preferences.put('lanUrl', this.lanUrl)
      await this.preferences.flush()
    }
    // 同步到配置
    await this.addFromLogin(url)
    this.updateApiServiceUrl()
  }

  async setTunnelUrl(url: string): Promise<void> {
    this.tunnelUrl = UrlUtils.normalizeUrl(url)
    if (this.preferences) {
      await this.preferences.put('tunnelUrl', this.tunnelUrl)
      await this.preferences.flush()
    }
    await this.addFromLogin(url)
    this.updateApiServiceUrl()
  }

  async setServerMode(mode: ServerMode): Promise<void> {
    this.serverMode = mode
    if (this.preferences) {
      await this.preferences.put('serverMode', mode)
      await this.preferences.flush()
    }
    this.updateApiServiceUrl()
  }

  async login(user: User): Promise<void> {
    this.user = user
    this.isLoggedIn = true
    if (this.preferences) {
      await this.preferences.put('userData', JSON.stringify(user))
      await this.preferences.flush()
    }
  }

  async logout(): Promise<void> {
    this.user = null
    this.isLoggedIn = false
    this.isLocked = false
    if (this.preferences) {
      await this.preferences.delete('userData')
      await this.preferences.flush()
    }
  }

  // MARK: - 生物识别锁屏

  lock(): void {
    this.isLocked = true
  }

  unlock(): void {
    this.isLocked = false
  }

  async setBiometricEnabled(enabled: boolean): Promise<void> {
    this.biometricEnabled = enabled
    if (this.preferences) {
      await this.preferences.put('biometricEnabled', enabled)
      await this.preferences.flush()
    }
  }

  private updateApiServiceUrl(): void {
    const url = this.serverUrl
    if (url) {
      apiService.setBaseUrl(url)
      wsService.setServerUrl(url)
    }
  }

  }

export const authStore = AuthStore.getInstance()
