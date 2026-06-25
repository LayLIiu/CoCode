import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';

/**
 * HdsGlassInput 液态玻璃输入框组件
 * 使用 HdsTabs 的沉浸光感作为背景，支持多行自适应高度
 * placeholder 流光扫描效果（复刻桌面端 shimmer-sweep-text）
 *
 * 流光原理：
 * 用一个比输入框宽 3 倍的线性渐变 Text 组件覆盖在 placeholder 位置，
 * 通过 translate 动画让渐变从右向左循环移动，模拟光带扫过文字。
 * 渐变结构：暗(30%) → 亮(90%) → 暗(30%)，与桌面端一致。
 */

// 流光动画周期（毫秒），与桌面端 1.8s 对齐
const SHIMMER_DURATION: number = 1800

@ComponentV2
export struct HdsGlassInput {
  @Param inputText: string = '';
  @Param placeholder: string = '发送消息...';
  @Param minHeight: number = 52;
  @Param maxHeight: number = 150;
  @Param onTextChange: ((text: string) => void) | undefined = undefined;

  @Local inputWidth: number = 1;
  @Local shimmerTranslateX: number = 0;
  private shimmerRunning: boolean = false

  private getInputWidth(): number {
    return this.inputWidth > 1 ? this.inputWidth : 1;
  }

  aboutToAppear(): void {
    this.startShimmer()
  }

  aboutToDisappear(): void {
    this.shimmerRunning = false
  }

  private startShimmer(): void {
    if (this.shimmerRunning) return
    this.shimmerRunning = true
    this.shimmerTranslateX = 0
    this.runShimmerLoop()
  }

  private runShimmerLoop(): void {
    if (!this.shimmerRunning) return
    // 先瞬间重置到起始位
    this.shimmerTranslateX = 0
    // 下一帧开始动画
    setTimeout(() => {
      if (!this.shimmerRunning) return
      animateTo({
        duration: SHIMMER_DURATION,
        curve: Curve.EaseInOut,
        iterations: 1,
        onFinish: () => {
          // 循环
          this.runShimmerLoop()
        }
      }, () => {
        // 从右端（输入框宽度）扫到左端（-2倍输入框宽度）
        // 渐变本身是 3 倍输入框宽，这样光带完整从左到右扫过
        this.shimmerTranslateX = -this.getInputWidth() * 2
      })
    }, 16)
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
      TextArea({ placeholder: '', text: this.inputText })
        .width('100%')
        .constraintSize({ minHeight: this.minHeight, maxHeight: this.maxHeight })
        .backgroundColor(Color.Transparent)
        .fontColor(Color.White)
        .fontSize(14)
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .caretColor(Color.White)
        .onChange((value: string) => {
          if (this.onTextChange) {
            this.onTextChange(value);
          }
        })

      // 流光 placeholder 层：输入框为空时显示
      if (!this.inputText) {
        // 裁剪容器：隐藏超出输入框的部分
        Stack() {
          // 流光文字：3 倍宽度，通过 translate 动画移动
          Text(this.placeholder)
            .fontSize(14)
            .fontColor(Color.Transparent)
            .width(this.getInputWidth() * 3)
            .textAlign(TextAlign.Start)
            .padding({ left: 16, top: 14 })
            .linearGradient({
              angle: 90,
              colors: [
                ['rgba(255,255,255,0.30)', 0.00],
                ['rgba(255,255,255,0.30)', 0.35],
                ['rgba(255,255,255,0.55)', 0.43],
                ['rgba(255,255,255,0.90)', 0.49],
                ['rgba(255,255,255,0.90)', 0.51],
                ['rgba(255,255,255,0.55)', 0.57],
                ['rgba(255,255,255,0.30)', 0.65],
                ['rgba(255,255,255,0.30)', 1.00],
              ]
            })
            .translate({ x: this.shimmerTranslateX })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(this.minHeight)
        .alignContent(Alignment.TopStart)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
      }
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
