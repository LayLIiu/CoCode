import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * HdsGlassInput 液态玻璃输入框组件
 * 使用 HdsTabs 的沉浸光感作为背景，支持多行自适应高度
 */
@ComponentV2
export struct HdsGlassInput {
  @Param inputText: string = '';
  @Param placeholder: string = '发送消息...';
  @Param minHeight: number = 36;
  @Param maxHeight: number = 120;
  @Param onTextChange: ((text: string) => void) | undefined = undefined;

  build() {
    Row() {
      HdsTabs() {
        TabContent() {
          TextArea({ placeholder: this.placeholder, text: this.inputText })
            .width('100%')
            .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
            .backgroundColor(Color.Transparent)
            .fontColor(Color.White)
            .placeholderColor('rgba(255,255,255,0.3)')
            .fontSize(14)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .caretColor(Color.White)
            .onChange((value: string) => {
              if (this.onTextChange) {
                this.onTextChange(value);
              }
            })
        }
        .tabBar('')
      }
      .barWidth('100%')
      .barHeight(this.minHeight)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .scrollable(false)
      .animationDuration(0)
      .barFloatingStyle({
        gradientMask: {
          maskColor: 'rgba(0,0,0,0)'  // 完全透明，隐藏方框
        },
        barBottomMargin: 0,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .backgroundColor(Color.Transparent)
      .border({ width: 0 })
      .shadow({ radius: 0 })
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
    .backgroundColor(Color.Transparent)
    .borderRadius(18)
    .clip(false)
  }
}
