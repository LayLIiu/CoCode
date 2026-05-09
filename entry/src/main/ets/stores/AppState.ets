/**
 * 应用全局状态
 */

import { ModelInfo, Provider } from '../models/Models'
import { apiService } from '../services/APIService'
import { authStore } from './AuthStore'

export type ThemeMode = 'light' | 'dark' | 'glass'

export class AppState {
  private static instance: AppState

  // 前后台状态
  isInForeground: boolean = true

  // 主题
  themeMode: ThemeMode = 'dark'

  // 模型
  models: ModelInfo[] = []
  currentModel: ModelInfo | null = null
  currentProviderId: string | null = null
  currentProviderName?: string

  // 服务商
  providers: Provider[] = []
  activeProviderId: string | null = null

  // 思考强度
  effortLevel: string = 'medium'
  availableEfforts: string[] = ['low', 'medium', 'high', 'max']

  // 按服务商存储的模型列表（用于 per-provider 模型过滤）
  sessionModels: Record<string, ModelInfo[]> = {}

  // 加载状态
  isLoadingModels: boolean = false

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

  setEffortLevel(level: string): void {
    this.effortLevel = level
  }

  async fetchModels(): Promise<void> {
    this.isLoadingModels = true
    try {
      const response = await apiService.getModels()
      this.models = response.models
      if (response.provider) {
        this.currentProviderId = response.provider.id
        this.currentProviderName = response.provider.name
      }
      // 如果当前模型不在列表中，使用第一个
      if (!this.currentModel || !this.models.find(m => m.id === this.currentModel!.id)) {
        if (this.models.length > 0) {
          this.currentModel = this.models[0]
        }
      }
      if (this.onModelsChanged) {
        this.onModelsChanged()
      }
    } catch (e) {
      console.error(`[AppState] Fetch models error: ${e}`)
    } finally {
      this.isLoadingModels = false
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

  // 获取指定服务商的模型列表
  getModelsForProvider(providerId: string): ModelInfo[] {
    if (this.sessionModels[providerId] && this.sessionModels[providerId].length > 0) {
      return this.sessionModels[providerId]
    }
    return this.models
  }

  // 检查服务商是否未配置
  isProviderUnconfigured(providerId: string): boolean {
    const models = this.sessionModels[providerId]
    return models !== undefined && models.length === 0
  }

  async fetchEffortOptions(): Promise<void> {
    try {
      const response = await apiService.getEffort()
      this.availableEfforts = response.available
      if (!this.availableEfforts.includes(this.effortLevel)) {
        this.effortLevel = response.level
      }
    } catch (e) {
      // 使用默认值
      console.error(`[AppState] Fetch effort error: ${e}`)
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
      this.fetchProviders(),
      this.fetchEffortOptions()
    ])
  }
}

export const appState = AppState.getInstance()
