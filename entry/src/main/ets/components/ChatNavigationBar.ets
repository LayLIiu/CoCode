import { Theme } from '../common/Theme'

/**
 * 对话详情页顶部导航栏 - 沉浸光感液态玻璃效果
 */
@Component
export struct ChatNavigationBar {
  @Prop title: string
  @Prop statusText: string = '工具执行中'
  @Prop showStatus: boolean = true
  onBackClick: () => void = () => {}
  onMenuClick: () => void = () => {}

  build() {
    Column() {
      // 顶部导航
      Row() {
        // 返回按钮 - 液态玻璃效果
        Column() {
          Image($r('app.media.ic_back'))
            .width(20)
            .height(20)
            .fillColor(Theme.TextPrimary)
        }
        .width(36)
        .height(36)
        .backgroundColor('rgba(255, 255, 255, 0.1)')
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onBackClick()
        })
        
        // 标题
        Text(this.title)
          .fontSize(Theme.FontBody)
          .fontColor(Theme.TextPrimary)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        
        // 功能按钮 - 液态玻璃效果
        Column() {
          Image($r('app.media.ic_menu'))
            .width(20)
            .height(20)
            .fillColor(Theme.TextPrimary)
        }
        .width(36)
        .height(36)
        .backgroundColor('rgba(255, 255, 255, 0.1)')
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(18)
        .border({ width: 1, color: 'rgba(255, 255, 255, 0.1)' })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onMenuClick()
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .alignItems(VerticalAlign.Center)
      
      // 状态栏
      if (this.showStatus) {
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(Theme.AccentBlue)
            .margin({ right: Theme.SpacingSM })
          
          Text(this.statusText)
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: Theme.SpacingXS, bottom: Theme.SpacingXS })
      }
    }
    .width('100%')
    .backgroundColor(Theme.BackgroundPrimary)
    // 关键：使用expandSafeArea确保内容不被安全区遮挡
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    // 添加顶部padding以适应安全区
    .padding({ top: 56 }) // 增加顶部padding，确保标题在安全区内
  }
}
