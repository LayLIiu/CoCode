import { Theme } from '../common/Theme'

/**
 * 搜索栏组件 - 鸿蒙6.1.0液态玻璃效果
 * 精致液态玻璃：光泽感 + 通透感
 */
@Component
export struct SearchBar {
  @Link searchText: string
  placeholder: string = '搜索对话...'
  onSearchChange: () => void = () => {}

  build() {
    Stack() {
      // 底层：沉浸光感玻璃背景
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.GlassBackground)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(24)

      // 中层：光泽渐变层
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
    }
    .width('100%')
    .height(48)
    .borderRadius(24)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .shadow({
      radius: 12,
      color: 'rgba(0, 0, 0, 0.2)',
      offsetX: 0,
      offsetY: 3
    })
  }
}
