import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * HdsGlassInput 液态玻璃输入框组件
 * 使用 HdsTabs 的沉浸光感作为背景，支持多行自适应高度
 * 注意：HdsTabs 内部会处理触摸事件，但不影响外部组件
 */
@ComponentV2
export struct HdsGlassInput {
  @Param inputText: string = '';
  @Param placeholder: string = '发送消息...';
  @Param minHeight: number = 52;
  @Param maxHeight: number = 150;
  @Param onTextChange: ((text: string) => void) | undefined = undefined;

  @Local inputWidth: number = 1;

  private getInputWidth(): number {
    return this.inputWidth > 1 ? this.inputWidth : 1;
  }

  @Builder
  glassBarContent() {
    Row()
      .width(this.getInputWidth())
      .height(this.minHeight)
      .backgroundColor(Color.Transparent)
  }

  build() {
    Stack() {
      // 底层：沉浸光感材质层（HdsTabs）
      HdsTabs() {
        TabContent()
          .tabBar(this.glassBarContent())
      }
      .width(this.getInputWidth())
      .height(this.minHeight)
      .barWidth(this.getInputWidth())
      .barHeight(this.minHeight)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .scrollable(false)
      .animationDuration(0)
      .barFloatingStyle({
        gradientMask: {
          maskColor: 'rgba(0,0,0,0)'
        },
        barBottomMargin: 0,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        }
      })
      .backgroundColor(Color.Transparent)
      .border({ width: 0 })
      .shadow({ radius: 0 })
      .hitTestBehavior(HitTestMode.Transparent)

      // 上层：透明输入框
      TextArea({ placeholder: this.placeholder, text: this.inputText })
        .width('100%')
        .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
        .backgroundColor(Color.Transparent)
        .fontColor(Color.White)
        .placeholderColor('rgba(255,255,255,0.5)')
        .fontSize(14)
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .caretColor(Color.White)
        .onChange((value: string) => {
          if (this.onTextChange) {
            this.onTextChange(value);
          }
        })
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.15)' })
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.inputWidth = newArea.width as number;
    })
  }
}
