import { curves } from '@kit.ArkUI'
import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'

/**
 * 高级液态玻璃胶囊滑块Tab栏
 * 特性：
 * 1. 毛玻璃效果（barOverlap + barBackgroundBlurStyle）
 * 2. 流畅滑动切换动画（Stack + animateTo）
 * 3. 自定义下划线指示器
 */
@Entry
@Component
export struct LiquidGlassTabBarAdvanced {
  // Tab项配置
  private tabItems: Array<{label: string, icon: Resource, activeIcon: Resource}> = [
    { label: 'Claude', icon: $r('app.media.ic_claude'), activeIcon: $r('app.media.ic_claude_filled') },
    { label: 'Codex', icon: $r('app.media.ic_codex'), activeIcon: $r('app.media.ic_codex_filled') },
    { label: 'Open Code', icon: $r('app.media.ic_terminal'), activeIcon: $r('app.media.ic_terminal_filled') },
    { label: '设置', icon: $r('app.media.ic_settings'), activeIcon: $r('app.media.ic_settings') }
  ];
  
  @State currentIndex: number = 0;
  @State underlineTranslateX: number = 0;  // 下划线X轴偏移
  @State underlineScale: number = 1.0;     // 下划线缩放（液态效果）
  
  private tabWidth: number = 64;           // 每个Tab的宽度
  private tabSpacing: number = 12;         // Tab间距

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主内容区 - Tabs组件
      Tabs({ index: this.currentIndex }) {
        ForEach(this.tabItems, (item: {label: string, icon: Resource, activeIcon: Resource}, index: number) => {
          TabContent() {
            // 内容页面
            Column() {
              Text(item.label + ' 内容页')
                .fontSize(Theme.FontHeading)
                .fontColor(Theme.TextPrimary)
                .margin({ top: 40 })
              
              Text('这是 ' + item.label + ' 的详细内容')
                .fontSize(Theme.FontBody)
                .fontColor(Theme.TextSecondary)
                .margin({ top: 12 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(Theme.BackgroundPrimary)
          }
          .tabBar(item.label)  // 占位，实际会被隐藏
        })
      }
      .barHeight(0)  // 隐藏默认TabBar
      .barOverlap(true)  // 允许TabBar叠加在内容上
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)  // 沉浸光感模糊效果
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        // Tab切换时更新下划线位置
        this.updateUnderlinePosition(index, true);
      });

      // 自定义胶囊Tab栏（悬浮在底部）
      Stack() {
        // 下划线指示器（液态效果）
        Row()
          .width(this.tabWidth)
          .height(48)
          .backgroundColor('rgba(10, 132, 255, 0.2)')
          .borderRadius(24)
          .translate({ x: this.underlineTranslateX, y: 4 })
          .scale({ x: this.underlineScale, y: this.underlineScale })
          .animation({
            duration: 400,
            curve: Curve.FastOutSlowIn  // 液态流动效果
          });

        // Tab按钮层
        Row() {
          ForEach(this.tabItems, (item: {label: string, icon: Resource, activeIcon: Resource}, index: number) => {
            this.TabButton(index, item);
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .alignItems(VerticalAlign.Center)
      }
      .width('90%')
      .height(56)
      .backgroundColor(Theme.GlassBackground)  // 沉浸光感背景
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .borderRadius(28)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .margin({ bottom: Theme.SpacingLG })
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 5
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  aboutToAppear() {
    // 初始化下划线位置
    this.updateUnderlinePosition(this.currentIndex, false);
  }

  /**
   * 更新下划线位置
   * @param index 目标Tab索引
   * @param animate 是否启用动画
   */
  private updateUnderlinePosition(index: number, animate: boolean) {
    if (animate) {
      // 液态弹性效果 — 用弹簧曲线代替三段 setTimeout
      animateTo({
        curve: curves.responsiveSpringMotion(0.5, 0.55)
      }, () => {
        this.underlineTranslateX = index * (this.tabWidth + this.tabSpacing);
        this.underlineScale = 1.0;
      });
    } else {
      this.underlineTranslateX = index * (this.tabWidth + this.tabSpacing);
    }
  }

  /**
   * Tab按钮构建器
   */
  @Builder
  TabButton(index: number, item: {label: string, icon: Resource, activeIcon: Resource}) {
    Column() {
      Image(this.currentIndex === index ? item.activeIcon : item.icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? Theme.AccentBlue : Theme.TextSecondary)
        .animation({ duration: 200, curve: Curve.EaseInOut });

      Text(item.label)
        .fontSize(Theme.FontTiny)
        .fontColor(this.currentIndex === index ? Theme.AccentBlue : Theme.TextSecondary)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 4 })
        .animation({ duration: 200, curve: Curve.EaseInOut });
    }
    .width(this.tabWidth)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.currentIndex !== index) {
        // 液态弹跳效果 — 弹簧曲线自动处理回弹，无需 setTimeout 链
        animateTo({ curve: curves.responsiveSpringMotion(0.4, 0.3) }, () => {
          this.underlineScale = 0.85;
        });
        // 弹簧自动回弹到 1.0
        setTimeout(() => {
          animateTo({ curve: curves.responsiveSpringMotion(0.3, 0.6) }, () => {
            this.underlineScale = 1.0;
          });
        }, 60);

        // 更新当前Tab
        this.currentIndex = index;
        this.updateUnderlinePosition(index, true);
      }
    });
  }
}
