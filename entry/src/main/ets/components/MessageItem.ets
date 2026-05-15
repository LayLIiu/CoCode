import { Theme } from '../common/Theme'
import { MessageModel, MessageType, ToolStatus } from '../viewmodel/MessageModel'

/**
 * 消息项组件
 */
@Component
export struct MessageItem {
  @Prop message: MessageModel
  @Prop @Watch('onRefresh') refreshTrigger: number = 0

  onRefresh(): void {
    // refreshTrigger 变化时触发组件重新渲染，解决 @Prop 深拷贝不更新问题
  }

  build() {
    Column() {
      if (this.message.type === MessageType.TEXT) {
        this.TextMessage()
      } else if (this.message.type === MessageType.TOOL_EXECUTION) {
        this.ToolExecutionMessage()
      } else if (this.message.type === MessageType.EXECUTING) {
        this.ExecutingMessage()
      }
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  /**
   * 文本消息
   */
  @Builder
  TextMessage() {
    Column() {
      Text(this.message.content)
        .fontSize(Theme.FontBody)
        .fontColor(Theme.TextPrimary)
        .lineHeight(24)
        .width('100%')
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusLarge)
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 工具执行消息
   */
  @Builder
  ToolExecutionMessage() {
    Row() {
      // 工具图标
      Image(this.message.toolInfo?.icon)
        .width(20)
        .height(20)
        .fillColor(Theme.TextSecondary)
        .margin({ right: Theme.SpacingSM })
      
      // 工具信息
      Column() {
        Text(this.message.toolInfo?.toolName || '')
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .fontWeight(FontWeight.Medium)
        
        Text(this.message.content)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      // 状态图标
      if (this.message.toolInfo?.status === ToolStatus.SUCCESS) {
        Image($r('app.media.ic_checkmark'))
          .width(16)
          .height(16)
          .fillColor(Theme.AccentGreen)
      } else if (this.message.toolInfo?.status === ToolStatus.FAIL) {
        Image($r('app.media.ic_error'))
          .width(16)
          .height(16)
          .fillColor('#FF3B30')
      }
    }
    .width('100%')
    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: Theme.SpacingSM, bottom: Theme.SpacingSM })
    .backgroundColor(Theme.BackgroundTertiary)
    .borderRadius(Theme.RadiusMedium)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 执行中消息
   */
  @Builder
  ExecutingMessage() {
    Row() {
      // 终端图标
      Image($r('app.media.ic_terminal'))
        .width(20)
        .height(20)
        .fillColor(Theme.AccentOrange)
        .margin({ right: Theme.SpacingSM })
      
      // 执行信息
      Text(`执行中... ${this.message.executingInfo?.duration || 0}s`)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .layoutWeight(1)
      
      // 加载动画
      LoadingProgress()
        .width(16)
        .height(16)
        .color(Theme.AccentOrange)
    }
    .width('100%')
    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: Theme.SpacingSM, bottom: Theme.SpacingSM })
    .backgroundColor(Theme.BackgroundTertiary)
    .borderRadius(Theme.RadiusMedium)
    .alignItems(VerticalAlign.Center)
  }
}
