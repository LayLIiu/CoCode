/**
 * 统一错误处理工具
 * 提供全局错误捕获、错误分类、错误恢复策略
 */

export enum ErrorSeverity {
  LOW = 'low',           // 不影响核心功能
  MEDIUM = 'medium',     // 影响部分功能
  HIGH = 'high',         // 影响核心功能
  CRITICAL = 'critical'  // 应用崩溃级别
}

export enum ErrorCategory {
  NETWORK = 'network',
  WEBSOCKET = 'websocket',
  API = 'api',
  STORAGE = 'storage',
  PERMISSION = 'permission',
  UI = 'ui',
  UNKNOWN = 'unknown'
}

export interface AppError {
  id: string
  message: string
  severity: ErrorSeverity
  category: ErrorCategory
  timestamp: number
  context?: Record<string, Object>
  stackTrace?: string
  recoverable: boolean
  recoveryAction?: string
}

export type ErrorListener = (error: AppError) => void

export class ErrorHandler {
  private static instance: ErrorHandler
  private errors: AppError[] = []
  private listeners: ErrorListener[] = []
  private maxErrors: number = 100

  static getInstance(): ErrorHandler {
    if (!ErrorHandler.instance) {
      ErrorHandler.instance = new ErrorHandler()
    }
    return ErrorHandler.instance
  }

  /**
   * 捕获并处理错误
   */
  handleError(
    error: Error | string,
    category: ErrorCategory = ErrorCategory.UNKNOWN,
    severity: ErrorSeverity = ErrorSeverity.MEDIUM,
    context?: Record<string, Object>
  ): AppError {
    const appError: AppError = {
      id: `err-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      message: typeof error === 'string' ? error : error.message,
      severity,
      category,
      timestamp: Date.now(),
      context,
      stackTrace: typeof error === 'object' ? error.stack : undefined,
      recoverable: this.isRecoverable(category, severity),
      recoveryAction: this.getRecoveryAction(category)
    }

    // 记录错误
    this.errors.push(appError)
    if (this.errors.length > this.maxErrors) {
      this.errors.shift()
    }

    // 控制台输出
    this.logError(appError)

    // 通知监听器
    this.notifyListeners(appError)

    return appError
  }

  /**
   * 便捷方法：网络错误
   */
  handleNetworkError(message: string, context?: Record<string, Object>): AppError {
    return this.handleError(message, ErrorCategory.NETWORK, ErrorSeverity.HIGH, context)
  }

  /**
   * 便捷方法：WebSocket 错误
   */
  handleWebSocketError(message: string, context?: Record<string, Object>): AppError {
    return this.handleError(message, ErrorCategory.WEBSOCKET, ErrorSeverity.HIGH, context)
  }

  /**
   * 便捷方法：API 错误
   */
  handleApiError(message: string, context?: Record<string, Object>): AppError {
    return this.handleError(message, ErrorCategory.API, ErrorSeverity.MEDIUM, context)
  }

  /**
   * 添加错误监听器
   */
  addListener(listener: ErrorListener): void {
    this.listeners.push(listener)
  }

  /**
   * 移除错误监听器
   */
  removeListener(listener: ErrorListener): void {
    this.listeners = this.listeners.filter(l => l !== listener)
  }

  /**
   * 获取最近的错误列表
   */
  getRecentErrors(count: number = 10): AppError[] {
    return this.errors.slice(-count)
  }

  /**
   * 获取指定分类的错误
   */
  getErrorsByCategory(category: ErrorCategory): AppError[] {
    return this.errors.filter(e => e.category === category)
  }

  /**
   * 清空错误记录
   */
  clearErrors(): void {
    this.errors = []
  }

  // MARK: - 私有方法

  private isRecoverable(category: ErrorCategory, severity: ErrorSeverity): boolean {
    if (severity === ErrorSeverity.CRITICAL) return false
    if (category === ErrorCategory.NETWORK || category === ErrorCategory.WEBSOCKET) return true
    if (category === ErrorCategory.API) return true
    return severity !== ErrorSeverity.HIGH
  }

  private getRecoveryAction(category: ErrorCategory): string {
    switch (category) {
      case ErrorCategory.NETWORK:
      case ErrorCategory.WEBSOCKET:
        return '检查网络连接并重试'
      case ErrorCategory.API:
        return '刷新页面或稍后重试'
      case ErrorCategory.STORAGE:
        return '清理存储空间'
      case ErrorCategory.PERMISSION:
        return '检查应用权限设置'
      default:
        return '重新启动应用'
    }
  }

  private logError(error: AppError): void {
    const level = error.severity === ErrorSeverity.CRITICAL ? 'error' :
                  error.severity === ErrorSeverity.HIGH ? 'warn' : 'info'
    
    console[level](`[${error.category.toUpperCase()}] ${error.message}`, {
      id: error.id,
      severity: error.severity,
      recoverable: error.recoverable,
      context: error.context
    })
  }

  private notifyListeners(error: AppError): void {
    this.listeners.forEach(listener => {
      try {
        listener(error)
      } catch (e) {
        console.error('[ErrorHandler] Listener error:', e)
      }
    })
  }
}

// 全局单例
export const errorHandler = ErrorHandler.getInstance()
