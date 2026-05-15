/**
 * 服务商状态管理
 */

import { Provider, ProviderInput, ProviderTestOverrides } from '../models/Models'
import { apiService } from '../services/APIService'

export class ProviderStore {
  private static instance: ProviderStore

  // 服务商列表
  providers: Provider[] = []
  activeProviderId: string | null = null

  // 加载状态
  isLoading: boolean = false
  error: string | null = null

  // 状态变更回调
  onProvidersChanged?: () => void

  static getInstance(): ProviderStore {
    if (!ProviderStore.instance) {
      ProviderStore.instance = new ProviderStore()
    }
    return ProviderStore.instance
  }

  get activeProvider(): Provider | undefined {
    if (!this.activeProviderId) {
      return undefined
    }
    return this.providers.find(p => p.id === this.activeProviderId)
  }

  async loadProviders(): Promise<void> {
    this.isLoading = true
    this.error = null

    try {
      const response = await apiService.getProviders()
      this.providers = response.providers
      this.activeProviderId = response.activeId || null
      if (this.onProvidersChanged) {
        this.onProvidersChanged()
      }
    } catch (e) {
      console.error(`[ProviderStore] Failed to load providers: ${e}`)
    }

    this.isLoading = false
  }

  async createProvider(input: ProviderInput): Promise<Provider> {
    const response = await apiService.createProvider(input)
    this.providers.push(response.provider)
    if (this.onProvidersChanged) {
      this.onProvidersChanged()
    }
    return response.provider
  }

  async updateProvider(id: string, input: ProviderInput): Promise<Provider> {
    const response = await apiService.updateProvider(id, input)
    const index = this.providers.findIndex(p => p.id === id)
    if (index >= 0) {
      this.providers[index] = response.provider
    }
    if (this.onProvidersChanged) {
      this.onProvidersChanged()
    }
    return response.provider
  }

  async deleteProvider(id: string): Promise<void> {
    await apiService.deleteProvider(id)
    this.providers = this.providers.filter(p => p.id !== id)
    if (this.activeProviderId === id) {
      this.activeProviderId = null
    }
    if (this.onProvidersChanged) {
      this.onProvidersChanged()
    }
  }

  async activateProvider(id: string): Promise<void> {
    await apiService.activateProvider(id)
    this.activeProviderId = id
    if (this.onProvidersChanged) {
      this.onProvidersChanged()
    }
  }

  async activateOfficial(): Promise<void> {
    await apiService.activateOfficialProvider()
    this.activeProviderId = null
    if (this.onProvidersChanged) {
      this.onProvidersChanged()
    }
  }

  async testProvider(id: string, overrides?: ProviderTestOverrides): Promise<boolean> {
    const response = await apiService.testProvider(id, overrides)
    return response.result.connectivity.success
  }

  setError(error: string | null): void {
    this.error = error
  }
}

export const providerStore = ProviderStore.getInstance()
