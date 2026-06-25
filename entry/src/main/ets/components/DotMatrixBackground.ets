/**
 * 点阵背景组件 - 复刻桌面端 DotGridShader 螺旋臂 + 涟漪效果
 *
 * 效果原理（与桌面端 WebGL 着色器等价）：
 * 1. 网格点阵：固定间距排列的圆点
 * 2. 螺旋臂旋转：2 条螺旋臂从中心向外旋转，臂上的点更大更亮
 * 3. 涟漪扰动：两个方向的正弦波让点产生轻微位移，形成水面涟漪
 * 4. 中心漂移：螺旋原点在中心附近缓慢漂移
 *
 * 移动端适配：间距/半径/涟漪幅度针对小屏调优，
 * 使用真实时间差驱动动画保证流畅度。
 */

// ---- 移动端适配参数 ----
const GAP = 10              // 间距更小，点更密
const DOT_R = 1.2           // 亮点
const R_MIN = 0.6           // 暗点
const RIPPLE_AMP = 1.5      // 涟漪幅度

// ---- 着色器参数（屏幕无关，直接复用桌面端） ----
const ARMS = 2.0
const PITCH = 0.08
const SPIN = 0.25
const DRIFT = 0.035
const WIDTH = 0.7           // 更宽的螺旋臂，过渡更柔和
const GAMMA = 2.5           // 更陡的衰减，配合宽臂降低峰值
const MAX_ALPHA = 0.2       // 限制最大亮度，整体更暗更柔和
const RIPPLE_FREQ = 0.020
const RIPPLE_VEL = 0.12
const RIPPLE_TURN = 0.015

// ---- 渲染控制 ----
const TWO_PI = Math.PI * 2
const FRAME_INTERVAL = 16       // ~60fps requestAnimationFrame 节拍
const ECO_INTERVAL = 50         // 不可见时降频

@Component
export struct DotMatrixBackground {
  @Prop active: boolean = true
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private time: number = 0
  private lastTs: number = 0
  private animId: number = -1
  private isAnimating: boolean = false
  private w: number = 0
  private h: number = 0
  private hasDrawnOnce: boolean = false
  private isVisible: boolean = false

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        if (this.active) {
          this.isVisible = true
          this.startAnimation()
        }
      })
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, _currentRatio: number) => {
        this.isVisible = isVisible
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
    this.lastTs = Date.now()
    this.scheduleNext()
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
      this.isAnimating = true
      this.lastTs = Date.now()
      this.scheduleNext()
    }
  }

  private scheduleNext(): void {
    const interval = (!this.isVisible || !this.active)
      ? ECO_INTERVAL
      : FRAME_INTERVAL
    this.animId = setTimeout(() => { this.tick() }, interval)
  }

  private tick(): void {
    if (!this.isAnimating) return

    // 用真实时间差驱动动画，与帧率解耦
    const now = Date.now()
    const dt = (now - this.lastTs) * 0.001  // 秒
    this.lastTs = now
    this.time += dt

    this.drawFrame()
    this.hasDrawnOnce = true
    this.scheduleNext()
  }

  private drawFrame(): void {
    const w = this.w
    const h = this.h
    if (w <= 0 || h <= 0) return

    const t = this.time
    const ctx = this.ctx
    ctx.clearRect(0, 0, w, h)

    // ---- 涟漪方向向量 ----
    const rh = t * RIPPLE_TURN
    const k1x = Math.cos(rh)
    const k1y = Math.sin(rh)
    const k2x = Math.cos(rh + 1.05)
    const k2y = Math.sin(rh + 1.05)

    // ---- 螺旋臂中心漂移 ----
    const gridW = w / GAP
    const gridH = h / GAP
    const originX = gridW * 0.5 + gridW * 0.35 * Math.sin(t * DRIFT * 3.0)
    const originY = gridH * 0.5 + gridH * 0.35 * Math.cos(t * DRIFT * 2.0)

    // ---- 颜色 ----
    const baseR = 255
    const baseG = 255
    const baseB = 255

    // ---- 逐行逐列绘制 ----
    const cols = Math.ceil(w / GAP) + 1
    const rows = Math.ceil(h / GAP) + 1

    for (let ci = 0; ci <= cols; ci++) {
      const cellX = ci - 0.5

      for (let ri = 0; ri <= rows; ri++) {
        const cellY = ri - 0.5

        // ---- 涟漪位移 ----
        const s1 = Math.sin((cellX * k1x + cellY * k1y) * RIPPLE_FREQ * TWO_PI - t * RIPPLE_VEL)
        const s2 = Math.sin((cellX * k2x + cellY * k2y) * RIPPLE_FREQ * TWO_PI - t * RIPPLE_VEL * 0.8)
        const dispX = (k1x * s1 + k2x * s2) * RIPPLE_AMP * 0.5
        const dispY = (k1y * s1 + k2y * s2) * RIPPLE_AMP * 0.5

        // ---- 点像素位置 ----
        const px = (ci + 0.5) * GAP + dispX
        const py = (ri + 0.5) * GAP + dispY

        // ---- 螺旋臂亮度 ----
        const dx = cellX - originX
        const dy = cellY - originY
        const rad = Math.sqrt(dx * dx + dy * dy)
        const ang = Math.atan2(dy, dx)
        const phase = ang * ARMS + rad * PITCH - t * SPIN
        const dArm = Math.acos(Math.cos(phase)) / Math.PI
        const tArm = Math.max(1.0 - dArm / WIDTH, 0.0)
        const alpha = Math.min(MAX_ALPHA, Math.pow(tArm, GAMMA))

        // ---- 半径插值 ----
        const radius = R_MIN + (DOT_R - R_MIN) * tArm

        if (alpha > 0.005) {
          ctx.beginPath()
          ctx.arc(px, py, radius, 0, TWO_PI)
          ctx.fillStyle = `rgba(${baseR},${baseG},${baseB},${alpha.toFixed(3)})`
          ctx.fill()
        }
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
