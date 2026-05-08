/**
 * 认证状态管理
 */

import preferences from '@ohos.data.preferences'
import { User, ServerMode } from '../models/Models'
import { apiService } from '../services/APIService'

export class AuthStore {
  private static instance: AuthStore
  private context?: Context

  // 状态
  user: User | null = null
  isLoggedIn: boolean = false
  lanUrl: string = ''
  tunnelUrl: string = ''
  serverMode: ServerMode = 'lan'

  private preferences?: preferences.Preferences

  static getInstance(): AuthStore {
    if (!AuthStore.instance) {
      AuthStore.instance = new AuthStore()
    }
    return AuthStore.instance
  }

  setContext(context: Context): void {
    this.context = context
    this.loadSavedData()
  }

  private async loadSavedData(): Promise<void> {
    if (!this.context) return

    try {
      this.preferences = await preferences.getPreferences(this.context, 'auth_store')

      this.lanUrl = await this.preferences.get('lanUrl', '') as string
      this.tunnelUrl = await this.preferences.get('tunnelUrl', '') as string
      this.serverMode = await this.preferences.get('serverMode', 'lan') as ServerMode

      // 恢复用户信息
      const userData = await this.preferences.get('userData', '') as string
      if (userData) {
        this.user = JSON.parse(userData) as User
        this.isLoggedIn = true
      }

      // 更新 API 服务地址
      this.updateApiServiceUrl()

      console.info(`[AuthStore] Loaded: lanUrl=${this.lanUrl}, tunnelUrl=${this.tunnelUrl}`)
    } catch (e) {
      console.error(`[AuthStore] Load error: ${e}`)
    }
  }

  get serverUrl(): string {
    return this.serverMode === 'lan' ? this.lanUrl : this.tunnelUrl
  }

  async setLanUrl(url: string): Promise<void> {
    this.lanUrl = this.normalizeUrl(url)
    if (this.preferences) {
      await this.preferences.put('lanUrl', this.lanUrl)
      await this.preferences.flush()
    }
    this.updateApiServiceUrl()
  }

  async setTunnelUrl(url: string): Promise<void> {
    this.tunnelUrl = this.normalizeUrl(url)
    if (this.preferences) {
      await this.preferences.put('tunnelUrl', this.tunnelUrl)
      await this.preferences.flush()
    }
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
    if (this.preferences) {
      await this.preferences.delete('userData')
      await this.preferences.flush()
    }
  }

  private updateApiServiceUrl(): void {
    const url = this.serverUrl
    if (url) {
      apiService.setBaseUrl(url)
    }
  }

  private normalizeUrl(url: string): string {
    if (!url) return url

    let processed = url

    // 移除协议前缀
    if (processed.startsWith('https://')) {
      processed = processed.substring(8)
    } else if (processed.startsWith('http://')) {
      processed = processed.substring(7)
    }

    // 处理 host:port:token 格式
    const colonCount = (processed.match(/:/g) || []).length
    if (colonCount >= 2) {
      const parts = processed.split(':')
      if (parts.length >= 2) {
        const host = parts[0]
        const port = parts[1]
        const isTunnel = host.includes('.tunnel.') ||
          host.includes('trycloudflare') ||
          host.includes('loca.lt')
        processed = isTunnel ? `https://${host}:${port}` : `http://${host}:${port}`
        return processed
      }
    }

    // 添加协议
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      const isTunnel = url.includes('.tunnel.') ||
        url.includes('trycloudflare') ||
        url.includes('loca.lt')
      return isTunnel ? `https://${url}` : `http://${url}`
    }

    return url
  }
}

export const authStore = AuthStore.getInstance()
