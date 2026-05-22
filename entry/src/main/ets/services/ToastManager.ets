/**
 * 全局 Toast 管理器 — 观察者模式，跨组件通信
 *
 * 用法:
 *   ToastManager.show('保存成功', 'success')
 *   ToastManager.error('网络连接失败')
 *   ToastManager.success('已复制到剪贴板')
 */

export type ToastType = 'info' | 'success' | 'error' | 'warning'

export interface ToastOptions {
  message: string
  type: ToastType
  duration: number
}

type ToastListener = (options: ToastOptions) => void

class ToastManagerBase {
  private listeners: ToastListener[] = []

  /** 注册监听，返回取消订阅函数 */
  subscribe(listener: ToastListener): () => void {
    this.listeners.push(listener)
    return () => {
      const idx = this.listeners.indexOf(listener)
      if (idx >= 0) {
        this.listeners.splice(idx, 1)
      }
    }
  }

  /** 显示 Toast */
  show(message: string, type: ToastType = 'info', duration: number = 2500): void {
    const options: ToastOptions = { message, type, duration }
    for (const listener of this.listeners) {
      listener(options)
    }
  }

  /** 快捷：成功提示 */
  success(message: string): void {
    this.show(message, 'success', 2500)
  }

  /** 快捷：错误提示 */
  error(message: string): void {
    this.show(message, 'error', 3500)
  }

  /** 快捷：警告提示 */
  warning(message: string): void {
    this.show(message, 'warning', 3000)
  }

  /** 快捷：信息提示 */
  info(message: string): void {
    this.show(message, 'info', 2500)
  }

  /** 快捷：复制成功 */
  copied(label?: string): void {
    this.show(label ? `已复制 ${label}` : '已复制', 'success', 2000)
  }
}

/** 全局单例 */
export const toastManager = new ToastManagerBase()