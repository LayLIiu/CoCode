import { Theme } from '../common/Theme'
import { ConversationModel, ConversationStatus } from '../viewmodel/ConversationModel'
import router from '@ohos.router'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

/**
 * 会话列表项组件 - 沉浸光感液态玻璃效果
 */
@Component
export struct ConversationItem {
  @Prop conversation: ConversationModel
  @State scaleValue: number = 1.0
  @State pressed: boolean = false
  private touchTimer: number = -1
  private pendingTimers: number[] = []
  private isDestroyed: boolean = false

  aboutToDisappear(): void {
    this.isDestroyed = true
    this.pendingTimers.forEach(id => clearTimeout(id))
    this.pendingTimers = []
    if (this.touchTimer !== -1) {
      clearTimeout(this.touchTimer)
      this.touchTimer = -1
    }
  }

  private scheduleTimer(callback: () => void, delay: number): void {
    const id = setTimeout(() => {
      const idx = this.pendingTimers.indexOf(id)
      if (idx >= 0) {
        this.pendingTimers.splice(idx, 1)
      }
      if (!this.isDestroyed) {
        callback()
      }
    }, delay)
    this.pendingTimers.push(id)
  }

  build() {
    Row() {
      // 左侧状态图标
      this.StatusIcon()
      
      // 中间内容区域
      Column() {
        // 会话标题
        Text(this.conversation.title)
          .fontSize(Theme.FontHeading)
          .fontColor(Theme.TextPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        // 文件路径
        Text(this.conversation.filePath)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: Theme.SpacingXS })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    // 沉浸光感液态玻璃核心效果
    .backgroundColor(this.pressed ? 'rgba(255, 255, 255, 0.12)' : 'rgba(255, 255, 255, 0.08)')
    .backgroundBlurStyle(BlurStyle.Regular)
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
    .margin({ bottom: Theme.SpacingMD })
    .scale({ x: this.scaleValue, y: this.scaleValue })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
    .onClick(() => {
      this.navigateToChatDetail()
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          // 长按操作
        })
    )
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.scaleValue = 0.95
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.touchTimer !== -1) {
          clearTimeout(this.touchTimer)
        }
        this.touchTimer = setTimeout(() => {
          this.scaleValue = 1.0
          this.pressed = false
          this.touchTimer = -1
        }, 100)
      }
    })
  }

  @Builder
  StatusIcon() {
    Stack() {
      // 圆角矩形背景 - 液态玻璃效果
      Column()
        .width(48)
        .height(48)
        .backgroundColor(this.conversation.iconTheme)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(Theme.RadiusMedium)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
        .opacity(0.25)
      
      // 休眠图标
      if (this.conversation.status === ConversationStatus.SLEEPING) {
        Column() {
          Text('💤')
            .fontSize(20)
          
          Text('休眠中')
            .fontSize(10)
            .fontColor(Theme.TextSecondary)
            .margin({ top: -4 })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Image($r('app.media.ic_terminal'))
          .width(24)
          .height(24)
          .fillColor(this.conversation.iconTheme)
      }
    }
    .width(48)
    .height(48)
    .alignContent(Alignment.Center)
  }

  /**
   * 导航到对话详情页
   */
  private navigateToChatDetail() {
    this.scaleValue = 0.95
    this.scheduleTimer(() => {
      this.scaleValue = 1.02
      this.scheduleTimer(() => {
        this.scaleValue = 1.0

        router.pushUrl({
          url: 'pages/ChatDetailPage',
          params: {
            conversationId: this.conversation.id,
            title: this.conversation.title
          }
        })
          .then(() => {
            console.log('Navigate to chat detail success')
          })
          .catch((error: Error) => {
            console.error('Navigate to chat detail failed: ' + error.message)
          })
      }, 100)
    }, 50)
  }
}
