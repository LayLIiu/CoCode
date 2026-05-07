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
      // 和tab栏一样的液态玻璃效果
      .backgroundColor('rgba(28, 28, 30, 0.75)')
      .backdropBlur(20)
      .borderRadius(18)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
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
        setTimeout(() => {
          this.addButtonScale = 1.1
          setTimeout(() => {
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
      // 和tab栏一样的液态玻璃效果
      .backgroundColor('rgba(28, 28, 30, 0.75)')
      .backdropBlur(20)
      .borderRadius(18)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
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
      // 和tab栏一样的液态玻璃效果
      .backgroundColor('rgba(28, 28, 30, 0.75)')
      .backdropBlur(20)
      .borderRadius(18)
      .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
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
          setTimeout(() => {
            this.sendButtonScale = 1.15
            setTimeout(() => {
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
