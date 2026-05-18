/**
 * 点阵背景组件 - 复刻桌面端 NoiseDotBackground 效果
 * 深色背景上绘制动态噪声点阵，缓慢慢速旋转产生流动感
 * 触控穿透触控，不影响列表滑动和按钮点击
 */

// 伪噪声函数：输入坐标和时间，返回 0~1 之间的平滑值
function pseudoNoise(x: number, y: number, z: number): number {
  const nx = x * 0.004
  const ny = y * 0.004
  const v = Math.sin(nx + Math.cos(ny + z)) * Math.cos(nx * 1.5 - z)
    + Math.sin(ny * 2.0 + z * 0.5)
    + Math.cos(Math.sqrt(nx * nx + ny * ny) - z)
  return (v + 2) / 4
}

const DOT_RADIUS = 1
const SPACING = 16
const DISPLACEMENT = 4
const TIME_SPEED = 0.018
const ROTATION_SPEED = 0.3
const FPS_INTERVAL = 16

@Component
export struct DotMatrixBackground {
  @Prop active: boolean = true
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private time: number = 0
  private animId: number = -1
  private isAnimating: boolean = false
  private w: number = 0
  private h: number = 0
  private hasDrawnOnce: boolean = false

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        if (this.active) {
          this.startAnimation()
        }
      })
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
        if (isVisible && this.active) {
          this.resumeAnimation()
        } else {
          this.pauseAnimation()
        }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.w = newArea.width as number
        this.h = newArea.height as number
      })
  }

  private startAnimation(): void {
    if (this.isAnimating) return
    this.isAnimating = true
    this.time = 0
    this.animId = setTimeout(() => { this.animate() }, FPS_INTERVAL)
  }

  private pauseAnimation(): void {
    this.isAnimating = false
    if (this.animId >= 0) {
      clearTimeout(this.animId)
      this.animId = -1
    }
  }

  private resumeAnimation(): void {
    if (this.isAnimating) return
    if (this.hasDrawnOnce) {
      // 恢复后重新开始动画循环
      this.isAnimating = true
      this.animId = setTimeout(() => { this.animate() }, FPS_INTERVAL)
    }
  }

  private animate(): void {
    if (!this.isAnimating) return
    this.drawFrame()
    this.hasDrawnOnce = true
    this.animId = setTimeout(() => { this.animate() }, FPS_INTERVAL)
  }

  private drawFrame(): void {
    const w = this.w
    const h = this.h
    if (w <= 0 || h <= 0) {
      return
    }

    this.ctx.clearRect(0, 0, w, h)

    this.time += TIME_SPEED
    const cx = w / 2
    const cy = h / 2

    for (let gx = SPACING / 2; gx < w; gx += SPACING) {
      for (let gy = SPACING / 2; gy < h; gy += SPACING) {
        const dx = gx - cx
        const dy = gy - cy
        const angle = Math.atan2(dy, dx)
        const dist = Math.sqrt(dx * dx + dy * dy)
        const rotatedAngle = angle + this.time * ROTATION_SPEED
        const sx = cx + Math.cos(rotatedAngle) * dist
        const sy = cy + Math.sin(rotatedAngle) * dist

        const n = pseudoNoise(sx, sy, this.time)
        const opacity = 0.005 + n * 0.15

        const dx2 = pseudoNoise(sx + 100, sy, this.time) - 0.5
        const dy2 = pseudoNoise(sx, sy + 100, this.time + 50) - 0.5
        const px = gx + dx2 * DISPLACEMENT
        const py = gy + dy2 * DISPLACEMENT

        this.ctx.beginPath()
        this.ctx.arc(px, py, DOT_RADIUS, 0, Math.PI * 2)
        this.ctx.fillStyle = `rgba(255,255,255,${opacity})`
        this.ctx.fill()
      }
    }
  }

  aboutToDisappear(): void {
    this.isAnimating = false
    if (this.animId >= 0) {
      clearTimeout(this.animId)
      this.animId = -1
    }
  }
}