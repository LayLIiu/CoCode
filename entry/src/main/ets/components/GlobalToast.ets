/**
 * 全局 Toast 组件 — 在 Index 根节点渲染，覆盖所有页面
 *
 * 通过 ToastManager 监听器模式触发
 */

import { toastManager, type ToastType, type ToastOptions } from '../services/ToastManager'

@Component
export struct GlobalToast {
  @State toastMessage: string = ''
  @State toastType: ToastType = 'info'
  @State toastVisible: boolean = false
  private dismissTimer: number = -1
  private unsubscribe: (() => void) | null = null

  aboutToAppear(): void {
    this.unsubscribe = toastManager.subscribe((options: ToastOptions) => {
      this.showToast(options)
    })
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe()
      this.unsubscribe = null
    }
    if (this.dismissTimer >= 0) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = -1
    }
  }

  private showToast(options: ToastOptions): void {
    // 清除之前的定时器
    if (this.dismissTimer >= 0) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = -1
    }

    this.toastMessage = options.message
    this.toastType = options.type
    this.toastVisible = true

    // 自动消失
    this.dismissTimer = setTimeout(() => {
      this.toastVisible = false
      this.dismissTimer = -1
    }, options.duration)
  }

  private getToastColor(): ResourceColor {
    switch (this.toastType) {
      case 'success':
        return '#34C759'
      case 'error':
        return '#FF3B30'
      case 'warning':
        return '#FF9F0A'
      case 'info':
      default:
        return '#0A84FF'
    }
  }

  private getIconUnicode(): string {
    switch (this.toastType) {
      case 'success':
        return '✓'
      case 'error':
        return '✕'
      case 'warning':
        return '⚠'
      case 'info':
      default:
        return 'ℹ'
    }
  }

  build() {
    Stack() {
      if (this.toastVisible) {
        Row({ space: 8 }) {
          Text(this.getIconUnicode())
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)

          Text(this.toastMessage)
            .fontSize(14)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(Color.Black)
        .borderRadius(20)
        .alignItems(VerticalAlign.Center)
        .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
    .padding({ top: 60 })
    .hitTestBehavior(HitTestMode.None)
  }
}