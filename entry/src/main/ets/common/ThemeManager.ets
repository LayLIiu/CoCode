/**
 * 主题管理器
 * 支持深色/浅色模式切换、主题定制
 */

import { Theme } from './Theme'

export type ThemeMode = 'dark' | 'light' | 'auto'

export interface ThemeColors {
  // 背景色
  backgroundPrimary: string
  backgroundSecondary: string
  backgroundTertiary: string

  // 文本色
  textPrimary: string
  textSecondary: string
  textTertiary: string

  // 强调色
  accentBlue: string
  accentGreen: string
  accentOrange: string
  accentPurple: string
  accentRed: string

  // 状态色
  successColor: string
  warningColor: string
  errorColor: string
  infoColor: string

  // 边框色
  borderPrimary: string
  borderSecondary: string
}

export type ThemeListener = (mode: ThemeMode, colors: ThemeColors) => void

export class ThemeManager {
  private static instance: ThemeManager

  // 当前主题模式
  private currentMode: ThemeMode = 'dark'

  // 主题颜色配置
  private themes: Map<ThemeMode, ThemeColors> = new Map([
    ['dark', {
      backgroundPrimary: '#000000',
      backgroundSecondary: '#1C1C1E',
      backgroundTertiary: '#2C2C2E',
      textPrimary: '#FFFFFF',
      textSecondary: '#8E8E93',
      textTertiary: '#636366',
      accentBlue: '#0A84FF',
      accentGreen: '#30D158',
      accentOrange: '#FF9F0A',
      accentPurple: '#BF5AF2',
      accentRed: '#FF453A',
      successColor: '#30D158',
      warningColor: '#FF9F0A',
      errorColor: '#FF453A',
      infoColor: '#0A84FF',
      borderPrimary: '#38383A',
      borderSecondary: '#2C2C2E'
    }],
    ['light', {
      backgroundPrimary: '#FFFFFF',
      backgroundSecondary: '#F2F2F7',
      backgroundTertiary: '#E5E5EA',
      textPrimary: '#000000',
      textSecondary: '#636366',
      textTertiary: '#8E8E93',
      accentBlue: '#007AFF',
      accentGreen: '#34C759',
      accentOrange: '#FF9500',
      accentPurple: '#AF52DE',
      accentRed: '#FF3B30',
      successColor: '#34C759',
      warningColor: '#FF9500',
      errorColor: '#FF3B30',
      infoColor: '#007AFF',
      borderPrimary: '#C6C6C8',
      borderSecondary: '#E5E5EA'
    }]
  ])

  // 监听器
  private listeners: ThemeListener[] = []

  // 持久化键
  private readonly STORAGE_KEY = 'theme_mode'

  static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager()
    }
    return ThemeManager.instance
  }

  /**
   * 初始化主题（从本地存储恢复）
   */
  async initialize(): Promise<void> {
    try {
      // 从本地存储加载主题模式
      const savedMode = await this.loadFromStorage()
      if (savedMode) {
        this.currentMode = savedMode
      }

      // 应用主题
      this.applyTheme(this.currentMode)

      console.info(`[ThemeManager] Initialized with mode: ${this.currentMode}`)
    } catch (error) {
      console.error('[ThemeManager] Initialize error:', error)
    }
  }

  /**
   * 获取当前主题模式
   */
  getCurrentMode(): ThemeMode {
    return this.currentMode
  }

  /**
   * 获取当前主题颜色
   */
  getCurrentColors(): ThemeColors {
    return this.themes.get(this.currentMode) || this.themes.get('dark')!
  }

  /**
   * 切换主题模式
   */
  async setMode(mode: ThemeMode): Promise<void> {
    if (this.currentMode === mode) return

    const oldMode = this.currentMode
    this.currentMode = mode

    // 应用主题
    this.applyTheme(mode)

    // 持久化
    await this.saveToStorage(mode)

    // 通知监听器
    this.notifyListeners()

    console.info(`[ThemeManager] Theme changed: ${oldMode} -> ${mode}`)
  }

  /**
   * 切换深色/浅色模式
   */
  async toggleMode(): Promise<void> {
    const newMode = this.currentMode === 'dark' ? 'light' : 'dark'
    await this.setMode(newMode)
  }

  /**
   * 自定义主题颜色
   */
  customizeTheme(mode: ThemeMode, colors: Partial<ThemeColors>): void {
    const baseColors = this.themes.get(mode)
    if (baseColors) {
      const customColors = { ...baseColors, ...colors }
      this.themes.set(mode, customColors)

      // 如果是当前主题，立即应用
      if (this.currentMode === mode) {
        this.applyTheme(mode)
        this.notifyListeners()
      }

      console.info(`[ThemeManager] Customized ${mode} theme`)
    }
  }

  /**
   * 添加监听器
   */
  addListener(listener: ThemeListener): void {
    this.listeners.push(listener)
  }

  /**
   * 移除监听器
   */
  removeListener(listener: ThemeListener): void {
    this.listeners = this.listeners.filter(l => l !== listener)
  }

  /**
   * 检查是否为深色模式
   */
  isDarkMode(): boolean {
    return this.currentMode === 'dark'
  }

  /**
   * 获取所有可用主题
   */
  getAvailableThemes(): ThemeMode[] {
    return ['dark', 'light', 'auto']
  }

  // MARK: - 私有方法

  /**
   * 应用主题到全局 Theme 对象
   */
  private applyTheme(mode: ThemeMode): void {
    const colors = this.themes.get(mode)
    if (!colors) return

    // 更新全局 Theme 对象
    Theme.BackgroundPrimary = colors.backgroundPrimary
    Theme.BackgroundSecondary = colors.backgroundSecondary
    Theme.BackgroundTertiary = colors.backgroundTertiary
    Theme.TextPrimary = colors.textPrimary
    Theme.TextSecondary = colors.textSecondary
    Theme.TextTertiary = colors.textTertiary
    Theme.AccentBlue = colors.accentBlue
    Theme.AccentGreen = colors.accentGreen
    Theme.AccentOrange = colors.accentOrange
    Theme.AccentPurple = colors.accentPurple
    Theme.WarningColor = colors.warningColor
    Theme.ErrorColor = colors.errorColor
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(): void {
    const colors = this.getCurrentColors()
    this.listeners.forEach(listener => {
      try {
        listener(this.currentMode, colors)
      } catch (error) {
        console.error('[ThemeManager] Listener error:', error)
      }
    })
  }

  /**
   * 从本地存储加载主题模式
   */
  private async loadFromStorage(): Promise<ThemeMode | null> {
    try {
      // 使用 storageService 加载
      // 这里简化处理，实际应调用 StorageService
      return null
    } catch (error) {
      return null
    }
  }

  /**
   * 保存主题模式到本地存储
   */
  private async saveToStorage(mode: ThemeMode): Promise<void> {
    try {
      // 使用 storageService 保存
      // 这里简化处理，实际应调用 StorageService
    } catch (error) {
      console.error('[ThemeManager] Save error:', error)
    }
  }
}

// 全局单例
export const themeManager = ThemeManager.getInstance()
