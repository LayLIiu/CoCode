/**
 * SkeletonLoading - 骨架屏组件
 * 用于会话列表和聊天页面的加载占位效果
 */

import { Theme } from '../common/Theme'

// ─────────────────────────────────────────────────────────────
// 会话列表骨架屏
// ─────────────────────────────────────────────────────────────

@Component
export struct ConversationListSkeleton {
  @State private animationProgress: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.startAnimation()
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private startAnimation(): void {
    this.timer = setInterval(() => {
      this.animationProgress = (this.animationProgress + 0.02) % 1.0
    }, 16)
  }

  private getShimmerOpacity(): number {
    // 创建闪烁效果
    const wave = Math.sin(this.animationProgress * Math.PI * 2) * 0.3 + 0.7
    return wave
  }

  build() {
    Column({ space: 0 }) {
      // 顶部导航栏骨架
      Row() {
        Column()
          .width(120)
          .height(28)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(8)
        Blank()
        Row({ space: 12 }) {
          Column()
            .width(28)
            .height(28)
            .backgroundColor('rgba(255,255,255,0.08)')
            .borderRadius(14)
          Column()
            .width(28)
            .height(28)
            .backgroundColor('rgba(255,255,255,0.08)')
            .borderRadius(14)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })

      // 搜索栏骨架
      Row() {
        Column()
          .width('100%')
          .height(40)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(12)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })

      // 会话项目骨架
      List({ space: 0 }) {
        ForEach([1, 2, 3, 4, 5, 6, 7, 8], (item: number) => {
          ListItem() {
            this.ConversationItemSkeleton()
          }
        }, (item: number) => `skeleton-${item}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  @Builder ConversationItemSkeleton() {
    Row({ space: 12 }) {
      // 左侧状态指示条
      Column()
        .width(3)
        .height(46)
        .borderRadius(2)
        .backgroundColor('rgba(255,255,255,0.12)')

      // 吉祥物占位
      Column()
        .width(46)
        .height(46)
        .backgroundColor('rgba(255,255,255,0.06)')
        .borderRadius(12)

      // 内容区域
      Column({ space: 8 }) {
        // 标题
        Column()
          .width('70%')
          .height(16)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(6)

        // 副标题
        Row({ space: 6 }) {
          Column()
            .width(14)
            .height(14)
            .backgroundColor('rgba(255,255,255,0.06)')
            .borderRadius(4)

          Column()
            .width('50%')
            .height(12)
            .backgroundColor('rgba(255,255,255,0.06)')
            .borderRadius(4)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧状态
      Column({ space: 8 }) {
        Column()
          .width(40)
          .height(20)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(8)

        Column()
          .width(30)
          .height(12)
          .backgroundColor('rgba(255,255,255,0.04)')
          .borderRadius(4)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(16)
    .margin({ left: 16, right: 16, top: 4, bottom: 4 })
  }
}

// ─────────────────────────────────────────────────────────────
// 聊天页面骨架屏
// ─────────────────────────────────────────────────────────────

@Component
export struct ChatDetailSkeleton {
  @State private animationProgress: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.startAnimation()
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private startAnimation(): void {
    this.timer = setInterval(() => {
      this.animationProgress = (this.animationProgress + 0.02) % 1.0
    }, 16)
  }

  build() {
    Column({ space: 0 }) {
      // 顶部导航栏骨架
      Row() {
        Column()
          .width(28)
          .height(28)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(14)

        Blank()

        Column()
          .width(100)
          .height(20)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(6)

        Blank()

        Column()
          .width(28)
          .height(28)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(14)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })

      // 消息列表骨架
      Column({ space: 16 }) {
        // AI 消息
        this.MessageSkeleton(false)

        // 用户消息
        this.MessageSkeleton(true)

        // AI 消息
        this.MessageSkeleton(false)

        // 工具执行消息
        this.ToolMessageSkeleton()
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 16 })

      Blank()

      // 底部输入区域骨架
      Row({ space: 8 }) {
        Column()
          .width(40)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(20)

        Column()
          .layoutWeight(1)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(12)

        Column()
          .width(40)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BackgroundPrimary)
  }

  @Builder MessageSkeleton(isUser: boolean) {
    Row() {
      if (isUser) {
        Blank()
      }

      Column({ space: 6 }) {
        Column()
          .width(isUser ? '80%' : '90%')
          .height(16)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(6)

        Column()
          .width(isUser ? '60%' : '75%')
          .height(16)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(6)

        Column()
          .width(isUser ? '40%' : '60%')
          .height(16)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(6)
      }
      .padding(14)
      .backgroundColor(isUser ? '#16161A' : '#0E0E10')
      .borderRadius(18)

      if (!isUser) {
        Blank()
      }
    }
    .width('100%')
  }

  @Builder ToolMessageSkeleton() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column()
          .width(20)
          .height(20)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(6)

        Column()
          .width(60)
          .height(14)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(4)

        Blank()

        Column()
          .width(40)
          .height(18)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(6)
      }
      .width('100%')

      Column()
        .width('80%')
        .height(12)
        .backgroundColor('rgba(255,255,255,0.04)')
        .borderRadius(4)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('rgba(32, 33, 36, 0.92)')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }
}

// ─────────────────────────────────────────────────────────────
// 简单的脉冲动画骨架
// ─────────────────────────────────────────────────────────────

@Component
export struct PulseSkeleton {
  @Prop skeletonWidth: string | number = '100%'
  @Prop skeletonHeight: string | number = 16
  @Prop skeletonBorderRadius: number = 6
  @State private skeletonOpacity: number = 0.6
  private timer: number = -1

  aboutToAppear(): void {
    this.startPulse()
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private startPulse(): void {
    let increasing = false
    this.timer = setInterval(() => {
      if (increasing) {
        this.skeletonOpacity += 0.05
        if (this.skeletonOpacity >= 0.8) increasing = false
      } else {
        this.skeletonOpacity -= 0.05
        if (this.skeletonOpacity <= 0.4) increasing = true
      }
    }, 30)
  }

  build() {
    Column()
      .width(this.skeletonWidth)
      .height(this.skeletonHeight)
      .backgroundColor(`rgba(255,255,255,${this.skeletonOpacity * 0.1})`)
      .borderRadius(this.skeletonBorderRadius)
  }
}

// ─────────────────────────────────────────────────────────────
// 卡片骨架
// ─────────────────────────────────────────────────────────────

@Component
export struct CardSkeleton {
  @Prop showAvatar: boolean = true
  @Prop lines: number = 3

  build() {
    Row({ space: 12 }) {
      if (this.showAvatar) {
        Column()
          .width(46)
          .height(46)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(12)
      }

      Column({ space: 8 }) {
        ForEach(Array.from({ length: this.lines }), (_: Object, idx: number) => {
          Column()
            .width(idx === this.lines - 1 ? '40%' : `${70 + Math.random() * 20}%`)
            .height(14)
            .backgroundColor('rgba(255,255,255,0.06)')
            .borderRadius(4)
        }, (_: Object, idx: number) => `line-${idx}`)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('rgba(255,255,255,0.02)')
    .borderRadius(16)
  }
}
