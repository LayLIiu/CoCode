import { Theme } from '../common/Theme'
import { hdsEffect } from '@kit.UIDesignKit'
import { curves, RectShape } from '@kit.ArkUI'

/**
 * 搜索栏组件 - 沉浸光感效果
 * 使用 hdsEffect 点光源实现手指追光
 */
@Component
export struct SearchBar {
  @Link searchText: string
  placeholder: string = '搜索对话...'
  onSearchChange: () => void = () => {}

  // 沉浸光感追光状态
  @State lightIntensity: number = 0
  @State lightFingerX: number = 0
  @State lightFingerY: number = 0

  build() {
    Stack() {
      // 光泽渐变层
      Row()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .linearGradient({
          angle: 145,
          colors: [
            ['rgba(255, 255, 255, 0.18)', 0.0],
            ['rgba(255, 255, 255, 0.03)', 0.4],
            ['rgba(255, 255, 255, 0.01)', 0.6],
            ['rgba(255, 255, 255, 0.12)', 1.0]
          ]
        })

      // 内容层
      Row() {
        // 搜索图标
        Image($r('app.media.ic_search'))
          .width(20)
          .height(20)
          .fillColor(Theme.TextSecondary)
          .margin({ right: Theme.SpacingSM })

        // 输入框
        TextInput({ placeholder: this.placeholder, text: this.searchText })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .placeholderColor(Theme.TextSecondary)
          .placeholderFont({ size: Theme.FontBody })
          .fontColor(Theme.TextPrimary)
          .fontSize(Theme.FontBody)
          .caretColor(Theme.AccentBlue)
          .onChange((value: string) => {
            this.searchText = value
            this.onSearchChange()
          })

        // 清除按钮
        if (this.searchText.length > 0) {
          Image($r('app.media.ic_clear'))
            .width(18)
            .height(18)
            .fillColor(Theme.TextSecondary)
            .onClick(() => {
              this.searchText = ''
              this.onSearchChange()
            })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })

      // 沉浸光感追光组件
      if (this.lightIntensity > 0) {
        Flex()
          .size({ width: 1, height: 1 })
          .backgroundColor(Color.Transparent)
          .visualEffect(
            new hdsEffect.HdsEffectBuilder()
              .pointLight({
                options: {
                  color: Color.White,
                  intensity: this.lightIntensity,
                  height: 100
                }
              })
              .buildEffect()
          )
          .position({ x: this.lightFingerX, y: this.lightFingerY })
      }
    }
    .width('100%')
    .height(48)
    .borderRadius(24)
    .clip(true)
    .clipShape(new RectShape({
      width: '100%',
      height: '100%',
      radius: 24
    }))
    .backgroundColor('#08FFFFFF')
    .backdropBlur(24)
    .border({ width: 0.5, color: '#30FFFFFF' })
    .visualEffect(
      new hdsEffect.HdsEffectBuilder()
        .pointLight({
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
        })
        .buildEffect()
    )
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
          this.lightIntensity = 2.5
        })
        this.lightFingerX = event.touches[0].x
        this.lightFingerY = event.touches[0].y
      } else if (event.type === TouchType.Move) {
        animateTo({
          curve: curves.responsiveSpringMotion(0.5, 0.5)
        }, () => {
          this.lightFingerX = event.touches[0].x
          this.lightFingerY = event.touches[0].y
        })
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.lightIntensity = 0
        })
      }
    })
  }
}
