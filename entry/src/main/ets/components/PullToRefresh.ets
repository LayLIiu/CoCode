/**
 * 下拉刷新组件
 * 支持自定义刷新指示器和刷新回调
 */

import { Theme } from '../common/Theme'

@Component
export struct PullToRefresh {
  @BuilderParam content: () => void
  @Prop onRefresh: () => void = () => {}
  @State isRefreshing: boolean = false
  @State pullDistance: number = 0
  @State refreshThreshold: number = 80

  private startY: number = 0
  private isPulling: boolean = false

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 刷新指示器
      if (this.pullDistance > 0 || this.isRefreshing) {
        this.RefreshIndicator()
      }

      // 内容区域
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .translate({ y: this.isRefreshing ? this.refreshThreshold : this.pullDistance })
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionStart((event: GestureEvent) => {
            if (!this.isRefreshing) {
              this.startY = event.fingerList[0].localY
              this.isPulling = true
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isPulling && !this.isRefreshing) {
              const currentY = event.fingerList[0].localY
              const distance = Math.max(0, (currentY - this.startY) * 0.5)
              this.pullDistance = Math.min(distance, this.refreshThreshold * 1.5)
            }
          })
          .onActionEnd(() => {
            this.isPulling = false
            if (this.pullDistance >= this.refreshThreshold) {
              this.triggerRefresh()
            } else {
              this.pullDistance = 0
            }
          })
      )
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RefreshIndicator() {
    Row() {
      if (this.isRefreshing) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(Theme.AccentBlue)
      } else {
        Text(this.pullDistance >= this.refreshThreshold ? '松开刷新' : '下拉刷新')
          .fontSize(14)
          .fontColor(Theme.TextSecondary)
      }
    }
    .width('100%')
    .height(this.refreshThreshold)
    .justifyContent(FlexAlign.Center)
    .opacity(Math.min(1, this.pullDistance / this.refreshThreshold))
  }

  private triggerRefresh(): void {
    this.isRefreshing = true
    this.pullDistance = 0

    // 执行刷新回调
    this.onRefresh()

    // 模拟刷新完成（实际应由外部控制）
    setTimeout(() => {
      this.isRefreshing = false
    }, 2000)
  }

  // 供外部调用，结束刷新状态
  finishRefresh(): void {
    this.isRefreshing = false
    this.pullDistance = 0
  }
}
