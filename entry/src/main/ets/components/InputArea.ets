import { Theme } from '../common/Theme'

/**
 * 底部输入区域组件 - 三个独立的液态玻璃胶囊
 */
@Component
export struct InputArea {
  @Link inputText: string
  onSend: (text: string) => void = () => {}
  onAddClick: () => void = () => {}
  @State sendButtonScale: number = 1.0
  @State addButtonScale: number = 1.0

  // 追踪所有 setTimeout，组件销毁时清理
  private pendingTimers: number[] = []
  private isDestroyed: boolean = false

  aboutToDisappear(): void {
    this.isDestroyed = true
    this.pendingTimers.forEach(id => clearTimeout(id))
    this.pendingTimers = []
  }

  private scheduleTimer(callback: () => void, delay: number): void {
    const id = setTimeout(() => {
      // 从追踪列表中移除已触发的 timer
      const idx = this.pendingTimers.indexOf(id)
      if (idx >= 0) {
        this.pendingTimers.splice(idx, 1)
      }
      // 组件已销毁则不执行回调
      if (!this.isDestroyed) {
        callback()
      }
    }, delay)
    this.pendingTimers.push(id)
  }

  build() {
    Row() {
      // 加号按钮 - 圆形液态玻璃胶囊
      Column() {
        Image($r('app.media.ic_add'))
          .width(20)
          .height(20)
          .fillColor(Theme.TextPrimary)
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      // 沉浸光感玻璃效果
      .backgroundColor(Theme.GlassBackground)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .borderRadius(18)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 5
      })
      .scale({ x: this.addButtonScale, y: this.addButtonScale })
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })
      .onClick(() => {
        this.addButtonScale = 0.85
        this.scheduleTimer(() => {
          this.addButtonScale = 1.1
          this.scheduleTimer(() => {
            this.addButtonScale = 1.0
            this.onAddClick()
          }, 100)
        }, 100)
      })
      
      // 输入框 - 长条形液态玻璃胶囊
      Row() {
        TextInput({ placeholder: '发送消息...', text: this.inputText })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Color.Transparent)
          .placeholderColor(Theme.TextSecondary)
          .placeholderFont({ size: Theme.FontBody })
          .fontColor(Theme.TextPrimary)
          .fontSize(Theme.FontBody)
          .caretColor(Theme.AccentBlue)
          .onChange((value: string) => {
            this.inputText = value
          })
          .onSubmit(() => {
            this.sendMessage()
          })
      }
      .layoutWeight(1)
      .height(36)
      .padding({ left: Theme.SpacingMD, right: Theme.SpacingSM })
      // 沉浸光感玻璃效果
      .backgroundColor(Theme.GlassBackground)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .borderRadius(18)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 5
      })
      .margin({ left: Theme.SpacingSM, right: Theme.SpacingSM })
      
      // 发送按钮 - 圆形液态玻璃胶囊
      Column() {
        Image($r('app.media.ic_send'))
          .width(20)
          .height(20)
          .fillColor(this.inputText.length > 0 ? Theme.AccentBlue : Theme.TextSecondary)
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      // 沉浸光感玻璃效果
      .backgroundColor(Theme.GlassBackground)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .borderRadius(18)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 5
      })
      .scale({ x: this.sendButtonScale, y: this.sendButtonScale })
      .animation({
        duration: 300,
        curve: Curve.EaseInOut
      })
      .onClick(() => {
        if (this.inputText.trim().length > 0) {
          this.sendButtonScale = 0.85
          this.scheduleTimer(() => {
            this.sendButtonScale = 1.15
            this.scheduleTimer(() => {
              this.sendButtonScale = 1.0
              this.sendMessage()
            }, 100)
          }, 100)
        }
      })
    }
    .width('100%')
    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD, top: Theme.SpacingMD, bottom: Theme.SpacingMD })
    .alignItems(VerticalAlign.Center)
  }

  private sendMessage() {
    if (this.inputText.trim().length > 0) {
      this.onSend(this.inputText.trim())
      this.inputText = ''
    }
  }
}
