import { Theme } from '../common/Theme'
import { hdsMaterial } from '@hms.hds.hdsMaterial'

/**
 * 搜索栏组件 - 沉浸光感液态玻璃效果
 */
@Component
export struct SearchBar {
  @Link searchText: string
  placeholder: string = '搜索对话...'
  onSearchChange: () => void = () => {}

  build() {
    Row() {
      Image($r('app.media.ic_search'))
        .width(20)
        .height(20)
        .fillColor(Theme.TextSecondary)
        .margin({ right: Theme.SpacingSM })
      
      TextInput({ placeholder: this.placeholder, text: this.searchText })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(Color.Transparent) // 透明背景，让容器材质透出
        .placeholderColor(Theme.TextSecondary)
        .placeholderFont({ size: Theme.FontBody })
        .fontColor(Theme.TextPrimary)
        .fontSize(Theme.FontBody)
        .caretColor(Theme.AccentBlue)
        .onChange((value: string) => {
          this.searchText = value
          this.onSearchChange()
        })
      
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
    .height(44)
    .padding({ left: Theme.SpacingMD, right: Theme.SpacingMD })
    // 沉浸光感液态玻璃核心效果
    .backgroundColor('rgba(255, 255, 255, 0.08)') // 半透明白色背景
    .backgroundBlurStyle(BlurStyle.Regular) // 常规背景模糊
    .borderRadius(Theme.RadiusLarge)
    .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' }) // 玻璃边缘高光
  }
}
