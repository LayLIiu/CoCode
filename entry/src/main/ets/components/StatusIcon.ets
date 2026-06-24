/**
 * 状态图标组件 — Canvas 绘制 Claude 触手动画
 * 完全复刻桌面端：思考=螺旋旋转、等待权限=呼吸、空闲=静态
 */

export enum WorkStatus {
  IDLE = 'idle',
  THINKING = 'thinking',
  STREAMING = 'streaming',
  TOOL_EXECUTING = 'tool_executing',
  PERMISSION_PENDING = 'permission_pending',
  QUESTION_PENDING = 'question_pending',
  COMPLETED = 'completed'
}

// 触手数据（来自桌面端 ClaudeLogo.tsx）
const CORE_RADIUS = 27.2
const ROOT_WIDTH_SCALE = 1.1
const TIP_WIDTH_SCALE = 1.3
const COLOR = '#D97757'

class Tentacle {
  id: number
  angle: number
  length: number
  baseW: number
  tipW: number
  animLength: number
  animBaseW: number
  animTipW: number
  jL: number

  constructor(id: number, angle: number, length: number, baseW: number, tipW: number) {
    this.id = id
    this.angle = angle
    this.length = length
    this.baseW = baseW * ROOT_WIDTH_SCALE
    this.tipW = tipW * TIP_WIDTH_SCALE
    this.animLength = length
    this.animBaseW = baseW * ROOT_WIDTH_SCALE
    this.animTipW = tipW * TIP_WIDTH_SCALE
    this.jL = 0
  }
}

const INITIAL_TENTACLES: Tentacle[] = [
  new Tentacle(1, -176.8, 82.0, 10.0, 11.2),
  new Tentacle(2, -144.1, 83.6, 16.5, 19.1),
  new Tentacle(3, -117.6, 89.2, 17.9, 23.6),
  new Tentacle(4, -82.1, 73.2, 13.2, 16.6),
  new Tentacle(5, -50.8, 73.4, 26.5, 21.5),
  new Tentacle(6, -10.9, 67.7, 15.2, 13.7),
  new Tentacle(7, 9.1, 69.3, 9.8, 18.2),
  new Tentacle(8, 40.6, 71.1, 13.4, 8.9),
  new Tentacle(9, 56.2, 68.2, 18.0, 15.3),
  new Tentacle(10, 98.5, 73.8, 9.8, 15.7),
  new Tentacle(11, 128.1, 77.6, 13.5, 11.8),
  new Tentacle(12, 148.1, 75.0, 13.6, 14.4)
]

const STATUS_ICON_FRAME_INTERVAL_MS = 120

@Component
export struct StatusIcon {
  @Prop @Watch('onStatusChange') status: WorkStatus = WorkStatus.IDLE
  @Prop iconSize: number = 28
  private animTimer: number = -1
  private startTime: number = 0
  private tentacles: Tentacle[] = INITIAL_TENTACLES.map(t =>
    new Tentacle(t.id, t.angle, t.length, t.baseW / ROOT_WIDTH_SCALE, t.tipW / TIP_WIDTH_SCALE)
  )
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D()
  private breathScale: number = 1.0  // 整体呼吸缩放值

  aboutToAppear(): void {
    this.startAnimation()
  }

  aboutToDisappear(): void {
    this.stopAnimation()
  }

  onStatusChange(): void {
    this.startAnimation()
  }

  private startAnimation(): void {
    this.stopAnimation()
    this.startTime = Date.now()
    this.tick()
  }

  private stopAnimation(): void {
    if (this.animTimer !== -1) {
      clearTimeout(this.animTimer)
      this.animTimer = -1
    }
  }

  private isAnimatedStatus(status: WorkStatus): boolean {
    return status === WorkStatus.THINKING ||
      status === WorkStatus.STREAMING ||
      status === WorkStatus.TOOL_EXECUTING ||
      status === WorkStatus.PERMISSION_PENDING ||
      status === WorkStatus.QUESTION_PENDING
  }

  private tick(): void {
    const now = Date.now()
    const elapsed = now - this.startTime
    const mode = this.status
    const isThinking = mode === WorkStatus.THINKING
    const isWaiting = mode === WorkStatus.STREAMING || mode === WorkStatus.TOOL_EXECUTING
    const isBreathing = mode === WorkStatus.PERMISSION_PENDING || mode === WorkStatus.QUESTION_PENDING

    // 整体呼吸脉动
    if (isThinking) {
      // 思考状态只有螺旋旋转，呼吸回到 1.0 不叠加
      this.breathScale += (1.0 - this.breathScale) * 0.2
    } else if (isWaiting) {
      // 等待状态呼吸：收缩 250ms，膨胀 550ms，暂停 250ms
      const breathPeriod = 1050
      const breathProgress = elapsed % breathPeriod
      const tShrink = 250
      const tExpand = 550

      let rawBreath: number
      if (breathProgress < tShrink) {
        rawBreath = Math.cos((breathProgress / tShrink) * Math.PI / 2)
      } else if (breathProgress < tShrink + tExpand) {
        rawBreath = Math.sin(((breathProgress - tShrink) / tExpand) * Math.PI / 2)
      } else {
        rawBreath = 1
      }
      // 0.85 ~ 1.0 之间脉动
      this.breathScale += (0.85 + rawBreath * 0.15 - this.breathScale) * 0.15
    } else if (isBreathing) {
      this.breathScale += (1.0 - this.breathScale) * 0.2
    } else {
      this.breathScale += (1.0 - this.breathScale) * 0.2
    }

    // 更新触手物理
    for (let i = 0; i < this.tentacles.length; i++) {
      const t = this.tentacles[i]
      const rad = t.angle * Math.PI / 180

      if (isThinking) {
        // 螺旋旋转 — 完全复刻桌面端
        const rotSpeed = elapsed / 140
        let spiralPhase = (rad - rotSpeed) % (Math.PI * 2)
        if (spiralPhase < 0) spiralPhase += Math.PI * 2
        const normPhase = spiralPhase / (Math.PI * 2)

        let smoothK: number
        if (normPhase < 0.85) {
          smoothK = 0.45 + 0.85 * (normPhase / 0.85)
        } else {
          const p = (normPhase - 0.85) / 0.15
          smoothK = 1.3 - 0.85 * p
        }
        const STEPS = 12
        const k = Math.round(smoothK * STEPS) / STEPS
        const targetLength = t.length * k
        const w_k = 0.9 + 0.25 * (k - 0.45)
        const targetBaseW = t.baseW * w_k
        const targetTipW = t.tipW * w_k

        t.animLength += (targetLength - t.animLength) * 0.6
        t.animBaseW += (targetBaseW - t.animBaseW) * 0.6
        t.animTipW += (targetTipW - t.animTipW) * 0.6
        t.jL = (Math.random() - 0.5) * 0.05
        t.animLength *= (1 + t.jL)
      } else if (isWaiting || isBreathing) {
        // 呼吸动画 — 等待/权限请求状态
        const t_shrink = 250
        const t_expand = 550
        const t_pause = 250
        const total_cycle = t_shrink + t_expand + t_pause
        const progress = elapsed % total_cycle

        let raw_k: number
        if (progress < t_shrink) raw_k = Math.cos((progress / t_shrink) * Math.PI / 2)
        else if (progress < t_shrink + t_expand) raw_k = Math.sin(((progress - t_shrink) / t_expand) * Math.PI / 2)
        else raw_k = 1

        const k = Math.round(raw_k * 10) / 10
        const targetLength = t.length * k
        t.animLength += (targetLength - t.animLength) * 0.45
        t.animBaseW = t.baseW
        t.animTipW = t.tipW
      } else {
        // IDLE / COMPLETED — 平滑回归原始形态
        t.animLength += (t.length - t.animLength) * 0.2
        t.animBaseW += (t.baseW - t.animBaseW) * 0.2
        t.animTipW += (t.tipW - t.animTipW) * 0.2
        t.jL = 0
      }
    }

    this.drawCanvas()
    if (this.isAnimatedStatus(mode)) {
      this.animTimer = setTimeout(() => { this.tick() }, STATUS_ICON_FRAME_INTERVAL_MS)
    }
  }

  private drawCanvas(): void {
    const ctx = this.ctx
    if (!ctx) return

    const size = this.iconSize
    const cx = size / 2
    const cy = size / 2
    const canvasScale = size / 240 * 0.85 * this.breathScale

    ctx.clearRect(0, 0, size, size)
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(canvasScale, canvasScale)

    const fillet = 6.0

    ctx.fillStyle = COLOR
    ctx.strokeStyle = COLOR
    ctx.lineWidth = 0

    for (let i = 0; i < this.tentacles.length; i++) {
      const t = this.tentacles[i]
      const rad = t.angle * Math.PI / 180
      const dirX = Math.cos(rad)
      const dirY = Math.sin(rad)
      const normX = -Math.sin(rad)
      const normY = Math.cos(rad)

      const rRoot = CORE_RADIUS
      const rTip = CORE_RADIUS + Math.max(0, t.animLength)
      const f = fillet
      const hw = Math.min(t.animBaseW / 2, rRoot * 0.95)
      const theta = Math.asin(hw / rRoot)

      const B1x = rRoot * Math.cos(rad + theta)
      const B1y = rRoot * Math.sin(rad + theta)
      const B2x = rRoot * Math.cos(rad - theta)
      const B2y = rRoot * Math.sin(rad - theta)

      const Tip1x = dirX * rTip + normX * (t.animTipW / 2)
      const Tip1y = dirY * rTip + normY * (t.animTipW / 2)
      const Tip2x = dirX * rTip - normX * (t.animTipW / 2)
      const Tip2y = dirY * rTip - normY * (t.animTipW / 2)

      const len1 = Math.sqrt((Tip1x - B1x) * (Tip1x - B1x) + (Tip1y - B1y) * (Tip1y - B1y)) || 1
      const U1x = (Tip1x - B1x) / len1
      const U1y = (Tip1y - B1y) / len1

      const len2 = Math.sqrt((Tip2x - B2x) * (Tip2x - B2x) + (Tip2y - B2y) * (Tip2y - B2y)) || 1
      const U2x = (Tip2x - B2x) / len2
      const U2y = (Tip2y - B2y) / len2

      ctx.beginPath()
      ctx.moveTo(rRoot * Math.cos(rad + theta + f / rRoot), rRoot * Math.sin(rad + theta + f / rRoot))
      ctx.quadraticCurveTo(B1x, B1y, B1x + U1x * f, B1y + U1y * f)
      ctx.lineTo(Tip1x, Tip1y)

      const segments = 3 + (t.id % 3)
      for (let j = 1; j < segments; j++) {
        const ang = (rad + Math.PI / 2) + (-Math.PI) * (j / segments)
        ctx.lineTo(dirX * rTip + Math.cos(ang) * (t.animTipW / 2), dirY * rTip + Math.sin(ang) * (t.animTipW / 2))
      }

      ctx.lineTo(Tip2x, Tip2y)
      ctx.lineTo(B2x + U2x * f, B2y + U2y * f)
      ctx.quadraticCurveTo(B2x, B2y, rRoot * Math.cos(rad - theta - f / rRoot), rRoot * Math.sin(rad - theta - f / rRoot))
      ctx.closePath()
      ctx.fill()
    }

    // 中心圆
    ctx.beginPath()
    ctx.arc(0, 0, CORE_RADIUS, 0, Math.PI * 2)
    ctx.fill()

    ctx.restore()
  }

  build() {
    Canvas(this.ctx)
      .width(this.iconSize)
      .height(this.iconSize)
  }
}
