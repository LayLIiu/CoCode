import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'

/**
 * Tab项配置接口
 */
interface TabItem {
  index: TabIndex
  label: string
  icon: Resource
  activeIcon: Resource
}

/**
 * 底部Tab栏组件 - 悬浮胶囊样式
 */
@Component
export struct TabBar {
  @Prop currentTab: TabIndex = TabIndex.CLAUDE
  onTabChange: (tabIndex: TabIndex) => void = () => {}
  @State scaleValue: number = 1.0
  @State offsetY: number = 0
  @State sliderTranslateX: number = 0  // 滑块X轴平移
  @State sliderScale: number = 1.0  // 滑块缩放（Duang效果）

  private tabItems: TabItem[] = [
    {
      index: TabIndex.CLAUDE,
      label: Constants.TAB_CLAUDE,
      icon: $r('app.media.ic_claude'),
      activeIcon: $r('app.media.ic_claude_filled')
    },
    {
      index: TabIndex.SETTINGS,
      label: Constants.TAB_SETTINGS,
      icon: $r('app.media.ic_settings'),
      activeIcon: $r('app.media.ic_settings')
    }
  ]

  // 计算滑块位置
  private getSliderOffset(): number {
    // 计算滑块偏移：考虑SpaceEvenly布局的实际间距
    const tabWidth = 64
    const gap = 12  // 每个tab之间的间距（近似值）
    const currentIndex = this.currentTab as number
    return currentIndex * (tabWidth + gap)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 滑块指示器（全局滑动）
      Row()
        .width(64)
        .height(48)
        .backgroundColor('rgba(10, 132, 255, 0.15)')
        .borderRadius(24)
        .translate({ x: this.sliderTranslateX, y: 4 })  // 向下偏移4，垂直居中
        .scale({ x: this.sliderScale, y: this.sliderScale })
        .animation({
          duration: 400,
          curve: Curve.EaseOut
        })

      // Tab项（上层）
      Row() {
        ForEach(this.tabItems, (item: TabItem) => {
          this.TabBarItem(item)
        }, (item: TabItem) => item.index.toString())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
    }
    .width('90%')
    .height(56)
    .backgroundColor(Theme.GlassBackground)  // 液态玻璃背景
    .backdropBlur(20)
    .borderRadius(28)
    .border({ width: 1, color: Theme.GlassBorder })  // 添加玻璃边框
    .margin({ bottom: Theme.SpacingLG })
    .shadow({
      radius: 20,
      color: 'rgba(0, 0, 0, 0.3)',
      offsetX: 0,
      offsetY: 5
    })
    .scale({ x: this.scaleValue, y: this.scaleValue })
    .translate({ y: this.offsetY })
    .animation({
      duration: 300,
      curve: Curve.EaseInOut
    })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical })
        .onActionStart(() => {
          this.scaleValue = 0.95
        })
        .onActionUpdate((event: GestureEvent) => {
          this.offsetY = event.offsetY
        })
        .onActionEnd(() => {
          this.scaleValue = 1.0
          this.offsetY = 0
        })
    )
  }

  aboutToAppear() {
    // 初始化滑块位置
    this.sliderTranslateX = this.getSliderOffset()
  }

  // 监听currentTab变化，更新滑块位置
  aboutToUpdate() {
    this.sliderTranslateX = this.getSliderOffset()
  }

  @Builder
  TabBarItem(item: TabItem) {
      Column() {
        Image(this.currentTab === item.index ? item.activeIcon : item.icon)
          .width(24)
          .height(24)
          .fillColor(this.currentTab === item.index ? Theme.AccentBlue : Theme.TextSecondary)
          .animation({
            duration: Theme.DurationFast,
            curve: Curve.EaseInOut
          })
        
        Text(item.label)
          .fontSize(Theme.FontTiny)
          .fontColor(this.currentTab === item.index ? Theme.AccentBlue : Theme.TextSecondary)
          .fontWeight(this.currentTab === item.index ? FontWeight.Medium : FontWeight.Normal)
          .margin({ top: Theme.SpacingXS })
          .animation({
            duration: Theme.DurationFast,
            curve: Curve.EaseInOut
          })
      }
      .width(64)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    .width(64)
    .height(48)
    .onClick(() => {
      if (this.currentTab !== item.index) {
        // Duang弹跳效果：先缩放再回弹
        this.sliderScale = 0.8
        setTimeout(() => {
          this.sliderScale = 1.2
          setTimeout(() => {
            this.sliderScale = 1.0
          }, 150)
        }, 100)

        this.onTabChange(item.index)
      }
    })
  }
}
