/**
 * 全局 Toast 组件 — 在 Index 根节点渲染，覆盖所有页面
 *
 * 玻璃半透明风格 + 顶部滑入动画
 */

import { curves } from '@kit.ArkUI'
import { toastManager, type ToastType, type ToastOptions } from '../services/ToastManager'
import { Theme } from '../common/Theme'

@Component
export struct GlobalToast {
  @State toastMessage: string = ''
  @State toastType: ToastType = 'info'
  @State toastVisible: boolean = false
  @State toastOffsetY: number = -80
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
    if (this.dismissTimer >= 0) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = -1
    }

    this.toastMessage = options.message
    this.toastType = options.type

    // 滑入
    animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.6) }, () => {
      this.toastOffsetY = 0
    })

    // 定时滑出
    this.dismissTimer = setTimeout(() => {
      animateTo({ duration: 250, curve: Curve.EaseIn }, () => {
        this.toastOffsetY = -80
      })
      this.dismissTimer = setTimeout(() => {
        this.toastVisible = false
        this.dismissTimer = -1
      }, 280)
    }, options.duration)
  }

  private getAccentColor(): ResourceColor {
    switch (this.toastType) {
      case 'success':
        return Theme.AccentGreen
      case 'error':
        return Theme.ErrorColor
      case 'warning':
        return Theme.AccentOrange
      case 'info':
      default:
        return Theme.AccentBlue
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
      if (this.toastVisible || this.toastOffsetY > -80) {
        Row({ space: 8 }) {
          // 左侧色条
          Column()
            .width(3)
            .height(20)
            .backgroundColor(this.getAccentColor())
            .borderRadius(1.5)

          // 图标
          Text(this.getIconUnicode())
            .fontSize(14)
            .fontColor(this.getAccentColor())
            .fontWeight(FontWeight.Bold)

          // 消息
          Text(this.toastMessage)
            .fontSize(14)
            .fontColor(Color.White)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding({ left: 14, right: 16, top: 10, bottom: 10 })
        .backgroundColor('rgba(30, 30, 30, 0.85)')
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(14)
        .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.1)' })
        .alignItems(VerticalAlign.Center)
        .translate({ y: this.toastOffsetY })
        .shadow({ radius: 16, color: '#33000000', offsetY: 6 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
    .padding({ top: 56, left: 20, right: 20 })
    .hitTestBehavior(HitTestMode.None)
    .clip(true)
  }
}