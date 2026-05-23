/**
 * 运行状态指示器组件 - 参考 codex-relay RunningThreadIndicator
 * 在对话列表中显示运行中对话的动画效果
 */

import { Theme } from '../common/Theme'

@Component
export struct RunningIndicator {
  @State dot1Opacity: number = 0.3
  @State dot2Opacity: number = 0.3
  @State dot3Opacity: number = 0.3
  @State rotation: number = 0

  private animationTimer: number = -1

  aboutToAppear(): void {
    this.startAnimation()
  }

  aboutToDisappear(): void {
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer)
      this.animationTimer = -1
    }
  }

  private startAnimation(): void {
    let step = 0
    this.animationTimer = setInterval(() => {
      step = (step + 1) % 4
      switch (step) {
        case 0:
          this.dot1Opacity = 1.0
          this.dot2Opacity = 0.3
          this.dot3Opacity = 0.3
          break
        case 1:
          this.dot1Opacity = 0.3
          this.dot2Opacity = 1.0
          this.dot3Opacity = 0.3
          break
        case 2:
          this.dot1Opacity = 0.3
          this.dot2Opacity = 0.3
          this.dot3Opacity = 1.0
          break
        case 3:
          this.dot1Opacity = 1.0
          this.dot2Opacity = 1.0
          this.dot3Opacity = 1.0
          break
      }
      this.rotation += 30
    }, 200)
  }

  build() {
    Row({ space: 3 }) {
      Circle()
        .width(5)
        .height(5)
        .fill(Theme.AccentGreen)
        .opacity(this.dot1Opacity)
        .animation({ duration: 200, curve: Curve.EaseInOut })

      Circle()
        .width(5)
        .height(5)
        .fill(Theme.AccentGreen)
        .opacity(this.dot2Opacity)
        .animation({ duration: 200, curve: Curve.EaseInOut })

      Circle()
        .width(5)
        .height(5)
        .fill(Theme.AccentGreen)
        .opacity(this.dot3Opacity)
        .animation({ duration: 200, curve: Curve.EaseInOut })
    }
    .height(8)
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 脉冲圆点指示器
 */
@Component
export struct PulseIndicator {
  @Prop color: string = Theme.AccentGreen
  @Prop size: number = 8
  @State scale: number = 1.0
  @State opacity: number = 1.0

  private animationTimer: number = -1

  aboutToAppear(): void {
    this.startPulse()
  }

  aboutToDisappear(): void {
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer)
      this.animationTimer = -1
    }
  }

  private startPulse(): void {
    let expanding = true
    this.animationTimer = setInterval(() => {
      if (expanding) {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.scale = 1.3
          this.opacity = 0.6
        })
      } else {
        animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
          this.scale = 1.0
          this.opacity = 1.0
        })
      }
      expanding = !expanding
    }, 600)
  }

  build() {
    Circle()
      .width(this.size)
      .height(this.size)
      .fill(this.color)
      .scale({ x: this.scale, y: this.scale })
      .opacity(this.opacity)
  }
}

/**
 * 圆环进度指示器（小型）
 */
@Component
export struct RingActivityIndicator {
  @Prop size: number = 16
  @Prop strokeWidth: number = 2
  @Prop color: string = Theme.PrimaryColor
  @State rotation: number = 0

  private animationTimer: number = -1

  aboutToAppear(): void {
    this.startRotation()
  }

  aboutToDisappear(): void {
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer)
      this.animationTimer = -1
    }
  }

  private startRotation(): void {
    this.animationTimer = setInterval(() => {
      this.rotation = (this.rotation + 15) % 360
    }, 30)
  }

  build() {
    Stack() {
      // 背景环
      Circle()
        .width(this.size)
        .height(this.size)
        .fill('transparent')
        .stroke('rgba(255, 255, 255, 0.1)', { width: this.strokeWidth })

      // 进度弧（模拟）
      Row() {
        Circle()
          .width(this.size * 0.5)
          .height(this.size * 0.5)
          .fill(this.color)
      }
      .width(this.size)
      .height(this.size)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Top)
      .padding({ top: this.strokeWidth })
      .rotate({ angle: this.rotation })
      .clip(new Circle({ width: this.size, height: this.size }))
    }
    .width(this.size)
    .height(this.size)
  }
}

/**
 * 状态徽章组件
 */
@Component
export struct StatusBadge {
  @Prop status: 'idle' | 'running' | 'waiting' | 'completed' | 'error' = 'idle'
  @Prop showLabel: boolean = false

  private getStatusColor(): string {
    switch (this.status) {
      case 'running':
        return Theme.AccentGreen
      case 'waiting':
        return Theme.WarningColor
      case 'completed':
        return Theme.SuccessColor
      case 'error':
        return Theme.ErrorColor
      default:
        return Theme.TextTertiary
    }
  }

  private getStatusLabel(): string {
    switch (this.status) {
      case 'running':
        return '运行中'
      case 'waiting':
        return '等待中'
      case 'completed':
        return '已完成'
      case 'error':
        return '错误'
      default:
        return '空闲'
    }
  }

  build() {
    Row({ space: 4 }) {
      if (this.status === 'running') {
        RunningIndicator()
      } else {
        Circle()
          .width(6)
          .height(6)
          .fill(this.getStatusColor())
      }

      if (this.showLabel) {
        Text(this.getStatusLabel())
          .fontSize(10)
          .fontColor(this.getStatusColor())
      }
    }
    .height(12)
    .alignItems(VerticalAlign.Center)
  }
}
