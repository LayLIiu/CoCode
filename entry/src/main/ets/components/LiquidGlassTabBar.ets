import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';
import { Theme } from '../common/Theme'
import { Constants, TabIndex } from '../common/Constants'

/**
 * 液态玻璃胶囊滑块Tab栏 - 完整实现
 * 结合了胶囊形状、毛玻璃效果和流畅滑动切换动画
 */
@Entry
@Component
export struct LiquidGlassTabBar {
  // Tab数据
  private tabList: string[] = ['Claude', '设置'];

  // 状态管理
  @State currentIndex: number = 0;
  @State tabSelectedIndexes: number[] = [0];

  // SegmentButton配置
  @State tabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: 'Claude' },
      { text: '设置' }
    ] as ItemRestriction<SegmentButtonTextItem>,
    textPadding: 6
  });

  build() {
    Column() {
      // 胶囊SegmentButton
      SegmentButton({
        selectedIndexes: $tabSelectedIndexes,
        onItemClicked: (index: number) => {
 this.currentIndex = index;
        }
      })
      .width('80%')
      .margin({ top: 16 });

      // Tabs内容区，隐藏默认TabBar
      Tabs({ index: this.currentIndex }) {
        ForEach(this.tabList, (item: string, index: number) => {
          TabContent() {
            // 内容区域
            Column() {
              Text(item)
                .fontSize(Theme.FontHeading)
                .fontColor(Theme.TextPrimary)
                .margin({ top: 20 });
              
              Text('这是 ' + item + ' 的内容区域')
                .fontSize(Theme.FontBody)
                .fontColor(Theme.TextSecondary)
                .margin({ top: 12 });
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Start)
            .alignItems(HorizontalAlign.Center);
          };
        });
      }
      .barHeight(0)  // 隐藏默认TabBar
      .backgroundColor(Theme.BackgroundPrimary)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        // 同步SegmentButton状态
        this.currentIndex = index;
        this.tabSelectedIndexes = [index];
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start);
  }
}
