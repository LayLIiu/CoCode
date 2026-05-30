/**
 * 错误边界组件
 * 捕获子组件渲染错误，显示友好的错误提示
 */

import { Theme } from '../common/Theme'

@Component
export struct ErrorBoundary {
  @BuilderParam content: () => void
  @State hasError: boolean = false
  @State errorMessage: string = ''
  @Prop onRetry: () => void = () => {}

  build() {
    if (this.hasError) {
      this.ErrorView()
    } else {
      this.content()
    }
  }

  @Builder
  ErrorView() {
    Column({ space: Theme.SpacingLG }) {
      // 错误图标
      Text('⚠️')
        .fontSize(48)

      // 错误标题
      Text('出错了')
        .fontSize(Theme.FontTitle)
        .fontColor(Theme.TextPrimary)
        .fontWeight(FontWeight.Medium)

      // 错误信息
      Text(this.errorMessage || '抱歉，发生了未知错误')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)
        .textAlign(TextAlign.Center)
        .maxLines(3)

      // 重试按钮
      Button('重试')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)
        .backgroundColor(Theme.AccentBlue)
        .borderRadius(Theme.RadiusMedium)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingMD })
        .onClick(() => {
          this.hasError = false
          this.errorMessage = ''
          this.onRetry()
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(Theme.SpacingXL)
  }

  // 供外部调用，显示错误
  showError(message: string): void {
    this.hasError = true
    this.errorMessage = message
  }

  // 供外部调用，清除错误
  clearError(): void {
    this.hasError = false
    this.errorMessage = ''
  }
}

/**
 * 网络错误视图
 */
@Component
export struct NetworkErrorView {
  @Prop onRetry: () => void = () => {}

  build() {
    Column({ space: Theme.SpacingMD }) {
      Text('📡')
        .fontSize(48)

      Text('网络连接失败')
        .fontSize(Theme.FontTitle)
        .fontColor(Theme.TextPrimary)

      Text('请检查网络设置后重试')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextSecondary)

      Button('重试')
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)
        .backgroundColor(Theme.AccentBlue)
        .borderRadius(Theme.RadiusMedium)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingMD })
        .onClick(() => this.onRetry())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding(Theme.SpacingXL)
  }
}

/**
 * 空状态视图
 */
@Component
export struct EmptyStateView {
  @Prop icon: string = '📭'
  @Prop title: string = '暂无数据'
  @Prop description: string = ''
  @Prop actionText: string = ''
  @Prop onAction: () => void = () => {}

  build() {
    Column({ space: Theme.SpacingMD }) {
      Text(this.icon)
        .fontSize(48)

      Text(this.title)
        .fontSize(Theme.FontTitle)
        .fontColor(Theme.TextPrimary)

      if (this.description) {
        Text(this.description)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextSecondary)
          .textAlign(TextAlign.Center)
      }

      if (this.actionText) {
        Button(this.actionText)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)
          .backgroundColor(Theme.AccentBlue)
          .borderRadius(Theme.RadiusMedium)
          .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, top: Theme.SpacingMD, bottom: Theme.SpacingMD })
          .onClick(() => this.onAction())
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding(Theme.SpacingXL)
  }
}
