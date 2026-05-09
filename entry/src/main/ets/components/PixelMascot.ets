/**
 * 像素风格吉祥物组件 - 1:1 复刻 iOS 端实现
 * 支持动画：ZZZ 睡眠动画、呼吸动画、跳跃动画等
 */

// 吉祥物状态
export enum MascotStatus {
  IDLE = 'idle',
  PROCESSING = 'processing',
  WAITING_APPROVAL = 'waiting_approval',
  COMPLETED = 'completed'
}

// 吉祥物颜色
class MascotColors {
  static readonly COLORS: string[] = [
    '#E86B4A', '#2ECC71', '#9B59B6', '#E67E22',
    '#3498DB', '#E91E63', '#1ABC9C', '#F39C12'
  ]

  static getColorForId(id: string): string {
    let hash = 0
    for (let i = 0; i < id.length; i++) {
      const char = id.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    const index = Math.abs(hash) % MascotColors.COLORS.length
    return MascotColors.COLORS[index]
  }
}

@Component
export struct PixelMascot {
  @Prop @Watch('onStatusChange') mascotSize: number = 27
  @Prop @Watch('onStatusChange') status: MascotStatus = MascotStatus.IDLE
  @Prop @Watch('onColorChange') bodyColor: string = '#E86B4A'

  private readonly eyeColor: string = '#1a1a1a'
  private readonly alertColor: string = '#FF3D00'
  private readonly kbBaseColor: string = '#616e7a'
  private readonly kbKeyColor: string = '#9aa8b4'
  private readonly starColor: string = '#fbbf24'

  // 动画状态
  @State private zzzOffset1: number = 0
  @State private zzzOffset2: number = 0
  @State private zzzOffset3: number = 0
  @State private breatheValue: number = 0
  @State private bounceValue: number = 0
  @State private jumpValue: number = 0
  @State private armWaveValue: number = 0
  @State private starOpacityValue: number = 0.5
  @State private animationTime: number = 0  // 动画时间

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private animationTimer: number = -1
  private isCanvasReady: boolean = false
  private lastFrameTime: number = 0

  aboutToAppear(): void {
    // 启动动画定时器，每帧更新
    this.startAnimationTimer()
  }

  aboutToDisappear(): void {
    // 清理定时器
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer)
      this.animationTimer = -1
    }
  }

  // 状态变化回调
  onStatusChange(): void {
    console.info(`[PixelMascot] Status changed to: ${this.status}`)
    // 重置动画值
    this.bounceValue = 0
    this.jumpValue = 0
    this.armWaveValue = 0
    this.starOpacityValue = 0.5
    this.animationTime = 0
  }

  // 颜色变化回调
  onColorChange(): void {
    this.redrawCanvas()
  }

  // 启动动画定时器
  private startAnimationTimer(): void {
    this.lastFrameTime = Date.now()
    this.animationTimer = setInterval(() => {
      const now = Date.now()
      const delta = now - this.lastFrameTime
      this.lastFrameTime = now
      this.animationTime += delta

      // 更新各种动画值
      this.updateAnimationValues()

      // 重绘 Canvas
      this.redrawCanvas()
    }, 16)
  }

  // 更新动画值
  private updateAnimationValues(): void {
    const t = this.animationTime

    // 呼吸动画 - 周期 2000ms
    this.breatheValue = (Math.sin(t * Math.PI / 1000) + 1) / 2

    // ZZZ 动画 - 周期 3000ms
    this.zzzOffset1 = (t % 3000) / 3000
    this.zzzOffset2 = ((t + 900) % 3000) / 3000
    this.zzzOffset3 = ((t + 1800) % 3000) / 3000

    // 弹跳动画 - 周期 1000ms（工作状态）
    this.bounceValue = (Math.sin(t * 2 * Math.PI / 1000) + 1) / 2

    // 跳跃动画 - 周期 1750ms（警告状态）
    this.jumpValue = (t % 1750) / 1750

    // 手臂挥动动画 - 周期 600ms（完成状态）
    this.armWaveValue = (t % 600) / 600

    // 星星闪烁 - 周期 300ms（完成状态）
    this.starOpacityValue = 0.5 + 0.5 * Math.abs(Math.sin(t * Math.PI / 150))
  }

  // 重绘 Canvas
  private redrawCanvas(): void {
    if (!this.isCanvasReady || !this.context) return

    this.context.clearRect(0, 0, this.mascotSize, this.mascotSize)
    this.drawMascot()
  }

  build() {
    Stack() {
      Canvas(this.context)
        .width(this.mascotSize)
        .height(this.mascotSize)
        .onReady(() => {
          this.isCanvasReady = true
          this.drawMascot()
        })

      // ZZZ 睡眠符号 - 带动画
      if (this.status === MascotStatus.IDLE) {
        this.ZzzAnimatedView()
      }
    }
    .width(this.mascotSize)
    .height(this.mascotSize)
  }

  private drawMascot(): void {
    if (!this.context) return

    switch (this.status) {
      case MascotStatus.IDLE:
        this.drawSleepingMascot()
        break
      case MascotStatus.PROCESSING:
        this.drawWorkingMascot()
        break
      case MascotStatus.WAITING_APPROVAL:
        this.drawAlertMascot()
        break
      case MascotStatus.COMPLETED:
        this.drawCompletedMascot()
        break
    }
  }

  // 绘制像素矩形
  private drawPixelRect(x: number, y: number, w: number, h: number, color: string): void {
    this.context.fillStyle = color
    this.context.fillRect(x, y, w, h)
  }

  // 睡眠状态 - 带呼吸动画
  private drawSleepingMascot(): void {
    const size = this.mascotSize
    const s = size / 17
    const ox = (size - 17 * s) / 2
    const oy = (size - 7 * s) / 2 - 4 * s

    // 呼吸动画值
    const breathe = Math.sin(this.breatheValue * Math.PI)
    const puff = breathe * 0.25

    // 影子
    this.drawPixelRect(ox, oy + 15 * s, 17 * s, s, 'rgba(0,0,0,0.35)')

    // 腿
    const legXs = [3, 5, 9, 11]
    for (let i = 0; i < legXs.length; i++) {
      this.drawPixelRect(ox + legXs[i] * s, oy + 8.5 * s, s, 1.5 * s, this.bodyColor)
    }

    // 身体 - 呼吸效果
    const torsoH = 5 * (1.0 + puff)
    const torsoY = 15 - torsoH
    const torsoW = 13 * (1.0 + breathe * 0.015)
    const torsoX = 1 - (torsoW - 13) / 2
    this.drawPixelRect(ox + torsoX * s, oy + torsoY * s, torsoW * s, torsoH * s, this.bodyColor)

    // 手臂
    this.drawPixelRect(ox - s, oy + 13 * s, 2 * s, 2 * s, this.bodyColor)
    this.drawPixelRect(ox + 14 * s, oy + 13 * s, 2 * s, 2 * s, this.bodyColor)

    // 眼睛（闭着）
    const eyeY = 12.2 - puff * 2.5
    this.drawPixelRect(ox + 3 * s, oy + eyeY * s, 2.5 * s, s, this.eyeColor)
    this.drawPixelRect(ox + 9.5 * s, oy + eyeY * s, 2.5 * s, s, this.eyeColor)
  }

  // 工作状态 - 带弹跳动画
  private drawWorkingMascot(): void {
    const size = this.mascotSize
    const s = size / 16
    const ox = (size - 16 * s) / 2
    const oy = (size - 11 * s) / 2 - 2 * s

    // 弹跳动画
    const bounce = Math.sin(this.bounceValue * 2 * Math.PI * 4) * 1.5

    // 影子
    this.drawPixelRect(ox + 3 * s, oy + 15 * s, 9 * s, s, 'rgba(0,0,0,0.4)')

    // 腿
    const legXs = [3, 5, 9, 11]
    for (let i = 0; i < legXs.length; i++) {
      this.drawPixelRect(ox + legXs[i] * s, oy + 13 * s, s, 2 * s, this.bodyColor)
    }

    // 身体
    this.drawPixelRect(ox + 2 * s, oy + (6 + bounce) * s, 11 * s, 7 * s, this.bodyColor)

    // 眼睛
    this.drawPixelRect(ox + 4 * s, oy + (8 + bounce) * s, s, s, this.eyeColor)
    this.drawPixelRect(ox + 10 * s, oy + (8 + bounce) * s, s, s, this.eyeColor)

    // 键盘底座
    this.drawPixelRect(ox - 0.5 * s, oy + 11.8 * s, 16 * s, 3.5 * s, this.kbBaseColor)

    // 键盘按键
    for (let col = 0; col <= 5; col++) {
      const keyX = ox + (0.3 + col * 2.5) * s
      this.drawPixelRect(keyX, oy + 12.2 * s, 2 * s, 0.7 * s, this.kbKeyColor)
      this.drawPixelRect(keyX, oy + 13.2 * s, 2 * s, 0.7 * s, this.kbKeyColor)
    }

    // 手臂
    this.drawPixelRect(ox, oy + (9 + bounce) * s, 2 * s, 2 * s, this.bodyColor)
    this.drawPixelRect(ox + 13 * s, oy + (9 + bounce) * s, 2 * s, 2 * s, this.bodyColor)
  }

  // 警告状态 - 带跳跃动画
  private drawAlertMascot(): void {
    const size = this.mascotSize
    const s = size / 15
    const ox = (size - 15 * s) / 2
    const oy = (size - 12 * s) / 2 - 2 * s

    // 跳跃动画
    const jumpY = this.calculateJumpY(this.jumpValue)

    // 影子
    this.drawPixelRect(ox + 3 * s, oy + 15 * s, 9 * s, s, 'rgba(0,0,0,0.4)')

    // 腿
    const legXs = [3, 5, 9, 11]
    for (let i = 0; i < legXs.length; i++) {
      this.drawPixelRect(ox + legXs[i] * s, oy + (11 + jumpY) * s, s, 4 * s, this.bodyColor)
    }

    // 身体
    this.drawPixelRect(ox + 2 * s, oy + (6 + jumpY) * s, 11 * s, 7 * s, this.bodyColor)

    // 大眼睛
    this.drawPixelRect(ox + 4 * s, oy + (8 + jumpY) * s, s, 2.5 * s, this.eyeColor)
    this.drawPixelRect(ox + 10 * s, oy + (8 + jumpY) * s, s, 2.5 * s, this.eyeColor)

    // 手臂
    this.drawPixelRect(ox, oy + (4 + jumpY) * s, 2 * s, 2 * s, this.bodyColor)
    this.drawPixelRect(ox + 13 * s, oy + (4 + jumpY) * s, 2 * s, 2 * s, this.bodyColor)

    // 感叹号
    if (this.jumpValue > 0.03 && this.jumpValue < 0.55) {
      this.drawPixelRect(ox + 13 * s, oy + 2 * s, 2 * s, 3.5 * s, this.alertColor)
      this.drawPixelRect(ox + 13 * s, oy + 6 * s, 2 * s, 1.5 * s, this.alertColor)
    }
  }

  // 完成状态 - 带庆祝动画
  private drawCompletedMascot(): void {
    const size = this.mascotSize
    const s = size / 17
    const ox = (size - 17 * s) / 2
    const oy = (size - 14 * s) / 2 - 1 * s

    // 弹跳和手臂挥动动画
    const bounce = Math.sin(this.armWaveValue * 2 * Math.PI / 1.5) * 1
    const armWave = Math.sin(this.armWaveValue * 2 * Math.PI / 0.6) * 0.5

    // 影子
    this.drawPixelRect(ox + 3 * s, oy + 15 * s, 9 * s, s, 'rgba(0,0,0,0.3)')

    // 腿
    const legXs = [3, 5, 9, 11]
    for (let i = 0; i < legXs.length; i++) {
      this.drawPixelRect(ox + legXs[i] * s, oy + (11 + bounce * 0.3) * s, s, 3 * s, this.bodyColor)
    }

    // 身体
    this.drawPixelRect(ox + 2 * s, oy + (6 + bounce) * s, 11 * s, 6 * s, this.bodyColor)

    // 开心的眼睛
    this.drawPixelRect(ox + 3.5 * s, oy + (8 + bounce) * s, s, s, this.eyeColor)
    this.drawPixelRect(ox + 4.5 * s, oy + (7.5 + bounce) * s, 0.5 * s, 0.5 * s, this.eyeColor)
    this.drawPixelRect(ox + 9.5 * s, oy + (8 + bounce) * s, s, s, this.eyeColor)
    this.drawPixelRect(ox + 9 * s, oy + (7.5 + bounce) * s, 0.5 * s, 0.5 * s, this.eyeColor)

    // 微笑
    this.context.fillStyle = this.eyeColor
    this.context.beginPath()
    this.context.roundRect(ox + 6 * s, oy + (10 + bounce) * s, 3 * s, 0.8 * s, 0.4 * s)
    this.context.fill()

    // 举起的手臂
    this.drawPixelRect(ox - s, oy + (2 + bounce + armWave) * s, 2 * s, 5 * s, this.bodyColor)
    this.drawPixelRect(ox + 14 * s, oy + (2 + bounce - armWave) * s, 2 * s, 5 * s, this.bodyColor)

    // 星星
    this.context.globalAlpha = this.starOpacityValue
    this.drawPixelRect(ox - 2 * s, oy + s, s, s, this.starColor)
    this.drawPixelRect(ox + 16 * s, oy, 1.2 * s, 1.2 * s, this.starColor)
    this.context.globalAlpha = 1
  }

  // 计算跳跃 Y 值
  private calculateJumpY(pct: number): number {
    const keyframes = [
      [0, 0], [0.03, 0], [0.10, -1], [0.15, 1.5],
      [0.175, -10], [0.20, -10], [0.25, 1.5],
      [0.275, -8], [0.30, -8], [0.35, 1.2],
      [0.375, -5], [0.40, -5], [0.45, 1.0],
      [0.475, -3], [0.50, -3], [0.55, 0.5],
      [0.62, 0], [1.0, 0]
    ]

    for (let i = 1; i < keyframes.length; i++) {
      if (pct <= keyframes[i][0]) {
        const t = (pct - keyframes[i - 1][0]) / (keyframes[i][0] - keyframes[i - 1][0])
        return keyframes[i - 1][1] + (keyframes[i][1] - keyframes[i - 1][1]) * t
      }
    }
    return 0
  }

  // ZZZ 动画视图
  @Builder
  ZzzAnimatedView() {
    Stack() {
      // 第一个 z - 带动画偏移
      Text('z')
        .fontSize(this.mascotSize * 0.22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .opacity(this.zzzOffset1 < 0.8 ? 0.7 : (1 - this.zzzOffset1) * 3.5 * 0.7)
        .offset({
          x: this.mascotSize * 0.25,
          y: -this.mascotSize * 0.1 - this.zzzOffset1 * this.mascotSize * 0.5
        })

      // 第二个 z
      Text('z')
        .fontSize(this.mascotSize * 0.18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .opacity(this.zzzOffset2 < 0.8 ? 0.6 : (1 - this.zzzOffset2) * 3.5 * 0.6)
        .offset({
          x: this.mascotSize * 0.35,
          y: -this.mascotSize * 0.1 - this.zzzOffset2 * this.mascotSize * 0.5
        })

      // 第三个 z
      Text('z')
        .fontSize(this.mascotSize * 0.14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .opacity(this.zzzOffset3 < 0.8 ? 0.5 : (1 - this.zzzOffset3) * 3.5 * 0.5)
        .offset({
          x: this.mascotSize * 0.45,
          y: -this.mascotSize * 0.1 - this.zzzOffset3 * this.mascotSize * 0.5
        })
    }
  }
}

// 获取吉祥物颜色的辅助函数
export function getMascotColorForSession(sessionId: string): string {
  return MascotColors.getColorForId(sessionId)
}
