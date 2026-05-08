/**
 * 应用全局状态
 */

import { ModelInfo, Provider } from '../models/Models'
import { apiService } from '../services/APIService'
import { authStore } from './AuthStore'

export type ThemeMode = 'light' | 'dark' | 'glass'

export class AppState {
  private static instance: AppState

  // 主题
  themeMode: ThemeMode = 'dark'

  // 模型
  models: ModelInfo[] = []
  currentModel: ModelInfo | null = null
  currentProviderId: string | null = null

  // 服务商
  providers: Provider[] = []
  activeProviderId: string | null = null

  // 状态变更回调
  onThemeChanged?: () => void
  onModelsChanged?: () => void

  static getInstance(): AppState {
    if (!AppState.instance) {
      AppState.instance = new AppState()
    }
    return AppState.instance
  }

  setThemeMode(mode: ThemeMode): void {
    this.themeMode = mode
    if (this.onThemeChanged) {
      this.onThemeChanged()
    }
  }

  async fetchModels(): Promise<void> {
    try {
      const response = await apiService.getModels()
      this.models = response.models
      if (response.provider) {
        this.currentProviderId = response.provider.id
      }
      if (this.onModelsChanged) {
        this.onModelsChanged()
      }
    } catch (e) {
      console.error(`[AppState] Fetch models error: ${e}`)
    }
  }

  async getCurrentModel(): Promise<void> {
    try {
      const model = await apiService.getCurrentModel()
      this.currentModel = model
      if (this.onModelsChanged) {
        this.onModelsChanged()
      }
    } catch (e) {
      console.error(`[AppState] Get current model error: ${e}`)
    }
  }

  async setCurrentModel(modelId: string): Promise<void> {
    try {
      await apiService.setCurrentModel(modelId)
      const model = this.models.find(m => m.id === modelId)
      if (model) {
        this.currentModel = model
        if (this.onModelsChanged) {
          this.onModelsChanged()
        }
      }
    } catch (e) {
      console.error(`[AppState] Set current model error: ${e}`)
    }
  }

  async fetchProviders(): Promise<void> {
    try {
      const response = await apiService.getProviders()
      this.providers = response.providers
      this.activeProviderId = response.activeId || null
    } catch (e) {
      console.error(`[AppState] Fetch providers error: ${e}`)
    }
  }

  async activateProvider(id: string): Promise<void> {
    try {
      await apiService.activateProvider(id)
      this.activeProviderId = id
    } catch (e) {
      console.error(`[AppState] Activate provider error: ${e}`)
    }
  }

  // 初始化应用
  async initialize(): Promise<void> {
    if (!authStore.isLoggedIn) {
      return
    }

    await Promise.all([
      this.fetchModels(),
      this.getCurrentModel(),
      this.fetchProviders()
    ])
  }
}

export const appState = AppState.getInstance()
