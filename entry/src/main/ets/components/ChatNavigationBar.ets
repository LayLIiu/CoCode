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
        // 返回按钮 - 左箭头形状的玻璃胶囊，视觉重心靠左
        Row({ space: 2 }) {
          Image($r('app.media.ic_back'))
            .width(18)
            .height(18)
            .fillColor(Theme.TextPrimary)
          Text('返回')
            .fontSize(13)
            .fontColor(Theme.TextSecondary)
            .maxLines(1)
        }
        .height(32)
        .padding({ left: 10, right: 12 })
        .backgroundColor(Theme.GlassBackground)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(16)
        .border({ width: 0.5, color: Theme.GlassBorder })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
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
        
        // 功能按钮 - 更小的圆形玻璃胶囊，视觉上不喧宾夺主
        Column() {
          Image($r('app.media.ic_menu'))
            .width(16)
            .height(16)
            .fillColor(Theme.TextSecondary)
        }
        .width(28)
        .height(28)
        .backgroundColor(Theme.GlassBackground)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(14)
        .border({ width: 0.5, color: Theme.GlassBorder })
        .justifyContent(FlexAlign.Center)
        .opacity(0.7)
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
