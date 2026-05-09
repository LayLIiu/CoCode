import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'
import { TabType } from '../viewmodel/ConversationModel'
import { ConversationListPage } from './ConversationListPage'
import { SettingsPage } from './SettingsPage'

/**
 * 液态玻璃胶囊滑块Tab栏演示页面
 * 完整实现方案：
 * 1. 胶囊形状（自定义Stack布局）
 * 2. 毛玻璃效果（backdropBlur + 半透明背景）
 * 3. 流畅滑动切换动画（animateTo + 液态弹跳）
 * 4. 自定义下划线指示器（跟随Tab移动）
 */
@Entry
@Component
struct LiquidGlassDemoPage {
  // Tab项配置
  private tabItems: Array<{
    index: TabIndex,
    label: string,
    icon: Resource,
    activeIcon: Resource
  }> = [
    {
      index: TabIndex.CLAUDE,
      label: Constants.TAB_CLAUDE,
      icon: $r('app.media.ic_claude'),
      activeIcon: $r('app.media.ic_claude_filled')
    },
    {
      index: TabIndex.CODEX,
      label: Constants.TAB_CODEX,
      icon: $r('app.media.ic_codex'),
      activeIcon: $r('app.media.ic_codex_filled')
    },
    {
      index: TabIndex.OPEN_CODE,
      label: Constants.TAB_OPEN_CODE,
      icon: $r('app.media.ic_terminal'),
      activeIcon: $r('app.media.ic_terminal_filled')
    },
    {
      index: TabIndex.SETTINGS,
      label: Constants.TAB_SETTINGS,
      icon: $r('app.media.ic_settings'),
      activeIcon: $r('app.media.ic_settings')
    }
  ];

  @State currentIndex: number = 0;
  @State sliderTranslateX: number = 0;  // 滑块X轴平移
  @State sliderScale: number = 1.0;     // 滑块缩放（液态弹跳效果）
  
  private tabWidth: number = 64;        // 每个Tab的宽度
  private tabSpacing: number = 12;      // Tab间距

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 主内容区域
      Tabs({ index: this.currentIndex }) {
        ForEach(this.tabItems, (item: {
          index: TabIndex,
          label: string,
          icon: Resource,
          activeIcon: Resource
        }) => {
          TabContent() {
            if (item.index === TabIndex.SETTINGS) {
              SettingsPage()
            } else {
              ConversationListPage({
                tabType: this.getTabType(item.index),
                pageTitle: this.getPageTitle(item.index)
              })
            }
          }
          .tabBar('')  // 占位，实际会被隐藏
        })
      }
      .barHeight(0)  // 隐藏默认TabBar
      .barOverlap(true)  // 允许TabBar叠加在内容上
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)  // 沉浸光感模糊效果
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        // Tab滑动切换时更新滑块位置
        this.updateSliderPosition(index, true);
      });

      // 液态玻璃胶囊Tab栏（悬浮在底部）
      Stack() {
        // 滑块指示器（液态效果）
        Row()
          .width(this.tabWidth)
          .height(48)
          .backgroundColor('rgba(10, 132, 255, 0.2)')
          .borderRadius(24)
          .translate({ x: this.sliderTranslateX, y: 4 })
          .scale({ x: this.sliderScale, y: this.sliderScale })
          .animation({
            duration: 400,
            curve: Curve.FastOutSlowIn  // 液态流动效果
          });

        // Tab按钮层（上层）
        Row() {
          ForEach(this.tabItems, (item: {
            index: TabIndex,
            label: string,
            icon: Resource,
            activeIcon: Resource
          }) => {
            this.TabButton(item);
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
      .borderRadius(28)  // 胶囊形状
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
    // 初始化滑块位置
    this.updateSliderPosition(this.currentIndex, false);
  }

  /**
   * 更新滑块位置
   * @param index 目标Tab索引
   * @param animate 是否启用动画
   */
  private updateSliderPosition(index: number, animate: boolean) {
    if (animate) {
      // 液态弹跳动画
      animateTo({
        duration: 400,
        curve: Curve.FastOutSlowIn
      }, () => {
        this.sliderTranslateX = index * (this.tabWidth + this.tabSpacing);
        this.sliderScale = 1.0;
      });
    } else {
      this.sliderTranslateX = index * (this.tabWidth + this.tabSpacing);
    }
  }

  /**
   * Tab按钮构建器
   */
  @Builder
  TabButton(item: {
    index: TabIndex,
    label: string,
    icon: Resource,
    activeIcon: Resource
  }) {
    Column() {
      Image(this.currentIndex === item.index ? item.activeIcon : item.icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === item.index ? Theme.AccentBlue : Theme.TextSecondary)
        .animation({ duration: 200, curve: Curve.EaseInOut });
      
      Text(item.label)
        .fontSize(Theme.FontTiny)
        .fontColor(this.currentIndex === item.index ? Theme.AccentBlue : Theme.TextSecondary)
        .fontWeight(this.currentIndex === item.index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 4 })
        .animation({ duration: 200, curve: Curve.EaseInOut });
    }
    .width(this.tabWidth)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.currentIndex !== item.index) {
        // 液态弹跳动画：先缩放 -> 再回弹 -> 恢复
        animateTo({ duration: 100 }, () => {
          this.sliderScale = 0.85;
        });
        
        setTimeout(() => {
          animateTo({ duration: 150 }, () => {
            this.sliderScale = 1.15;
          });
          
          setTimeout(() => {
            animateTo({ duration: 100 }, () => {
              this.sliderScale = 1.0;
            });
          }, 150);
        }, 100);
        
        // 更新当前Tab
        this.currentIndex = item.index;
        this.updateSliderPosition(item.index, true);
      }
    });
  }

  /**
   * 获取Tab类型
   */
  private getTabType(tabIndex: TabIndex): TabType {
    switch (tabIndex) {
      case TabIndex.CLAUDE:
        return TabType.CLAUDE;
      case TabIndex.CODEX:
        return TabType.CODEX;
      case TabIndex.OPEN_CODE:
        return TabType.OPEN_CODE;
      default:
        return TabType.CLAUDE;
    }
  }

  /**
   * 获取页面标题
   */
  private getPageTitle(tabIndex: TabIndex): string {
    switch (tabIndex) {
      case TabIndex.CLAUDE:
        return Constants.TITLE_CLAUDE;
      case TabIndex.CODEX:
        return Constants.TITLE_CODEX;
      case TabIndex.OPEN_CODE:
        return Constants.TITLE_OPEN_CODE;
      default:
        return Constants.TITLE_CLAUDE;
    }
  }
}
