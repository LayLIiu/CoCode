import { curves } from '@kit.ArkUI'
import { Theme } from '../common/Theme'

/**
 * 底部输入区域组件 - 原生风格
 * 使用系统标准背景色和简洁布局，无玻璃模糊效果
 */
@Component
export struct InputArea {
  @Link inputText: string
  onSend: (text: string) => void = () => {}
  onAddClick: () => void = () => {}
  @State sendButtonScale: number = 1.0
  @State addButtonScale: number = 1.0

  // 弹簧点击动画
  private springPress(): void {
    animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.4) }, () => {
      this.sendButtonScale = 0.88
    })
    setTimeout(() => {
      animateTo({ curve: curves.responsiveSpringMotion(0.4, 0.6) }, () => {
        this.sendButtonScale = 1.0
      })
    }, 80)
  }

  private springPressAdd(): void {
    animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.4) }, () => {
      this.addButtonScale = 0.88
    })
    setTimeout(() => {
      animateTo({ curve: curves.responsiveSpringMotion(0.4, 0.6) }, () => {
        this.addButtonScale = 1.0
      })
    }, 80)
  }

  build() {
    Row() {
      // 加号按钮
      Column() {
        Image($r('app.media.ic_add'))
          .width(22)
          .height(22)
          .fillColor(Theme.TextPrimary)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.addButtonScale, y: this.addButtonScale })
      .animation({ duration: 200, curve: Curve.EaseInOut })
      .onClick(() => {
        this.springPressAdd()
        this.onAddClick()
      })

      // 输入框 — 不用显式 height，由 Row 撑开，确保整片可点
      TextInput({ placeholder: '发送消息...', text: this.inputText })
        .layoutWeight(1)
        .backgroundColor(Theme.BackgroundTertiary)
        .placeholderColor(Theme.TextTertiary)
        .placeholderFont({ size: Theme.FontBody })
        .fontColor(Theme.TextPrimary)
        .fontSize(Theme.FontBody)
        .caretColor(Theme.AccentBlue)
        .borderRadius(Theme.RadiusMedium)
        .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })
        .onChange((value: string) => {
          this.inputText = value
        })
        .onSubmit(() => {
          this.sendMessage()
        })

      // 发送按钮
      Column() {
        Image($r('app.media.ic_send'))
          .width(22)
          .height(22)
          .fillColor(this.inputText.length > 0 ? Theme.AccentBlue : Theme.TextTertiary)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .scale({ x: this.sendButtonScale, y: this.sendButtonScale })
      .animation({ duration: 300, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.inputText.trim().length > 0) {
          this.springPress()
          this.sendMessage()
        }
      })
    }
    .width('100%')
    .height(40)
    .padding({ left: Theme.SpacingSM, right: Theme.SpacingSM })
    .backgroundColor(Theme.BackgroundSecondary)
    .alignItems(VerticalAlign.Center)
  }

  private sendMessage() {
    if (this.inputText.trim().length > 0) {
      this.onSend(this.inputText.trim())
      this.inputText = ''
    }
  }
}