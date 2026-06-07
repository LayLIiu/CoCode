/**
 * 像素风格吉祥物组件 - 支持 Claude 像素猫 & Codex 像素风云朵
 * 1:1 复刻 iOS/macOS 端实现
 */

// 吉祥物状态
export enum MascotStatus {
  IDLE = 'idle',
  PROCESSING = 'processing',
  WAITING_APPROVAL = 'waiting_approval',
  COMPLETED = 'completed'
}

// 吉祥物类型
export enum MascotType {
  CLAUDE = 'claude',
  CODEX = 'codex',
  OPEN_CODE = 'opencode'
}

// Dex 坐标系辅助类
class DexV {
  s: number = 0
  ox: number = 0
  oy: number = 0
  y0: number = 0

  constructor(sz: number, svgW: number = 15, svgH: number = 10, svgY0: number = 6) {
    this.s = Math.min(sz / svgW, sz / svgH)
    this.ox = (sz - svgW * this.s) / 2
    this.oy = (sz - svgH * this.s) / 2
    this.y0 = svgY0
  }
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
  @Prop mascotType: MascotType = MascotType.CLAUDE

  // Claude 配色
  private readonly eyeColor: string = '#000000'
  private readonly alertColor: string = '#FF3D00'
  private readonly kbBaseColor: string = '#616e7a'
  private readonly kbKeyColor: string = '#9aa8b4'
  private readonly starColor: string = '#fbbf24'

  // Dex (Codex) 配色 - 基础色调会被 bodyColor 替换
  private readonly DEX_PROMPT: string = '#000000'
  private readonly DEX_ALERT_C: string = '#FF8800'
  private readonly DEX_KB_BASE: string = '#2E2E32'
  private readonly DEX_KB_KEY: string = '#66666A'
  private readonly DEX_KB_HI: string = '#FFFFFF'

  // OpBot (OpenCode) 配色 - 基础色调会被 bodyColor 替换
  private readonly OC_FRAME: string = '#000000'
  private readonly OC_FACE: string = '#000000'
  private readonly OC_ALERT_C: string = '#FF8800'
  private readonly OC_KB_BASE: string = '#1E1E24'
  private readonly OC_KB_KEY: string = '#4D4D52'
  private readonly OC_KB_HI: string = '#FFFFFF'

  // ZZZ 动画变量（@State 驱动 Text 组件更新）
  @State private zzzOffset1: number = 0
  @State private zzzOffset2: number = 0
  @State private zzzOffset3: number = 0
  // Claude 动画变量
  private breatheValue: number = 0
  private bounceValue: number = 0
  private jumpValue: number = 0
  private armWaveValue: number = 0
  private starOpacityValue: number = 0.5
  private animationTime: number = 0
  // Claude 手臂旋转（工作状态）
  private claudeArmL: number = 0
  private claudeArmR: number = 0
  // Claude 眨眼/扫视（工作状态）
  private claudeEyeScale: number = 0.5
  private claudeEyeDY: number = 1.0
  // Dex 动画变量
  private dexFloatValue: number = 0
  private dexBounceValue: number = 0
  private dexJumpValue: number = 0
  private dexCursorOn: boolean = true
  private dexKeyPhase: number = 0

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private animationTimer: number = -1
  private isCanvasReady: boolean = false
  private lastFrameTime: number = 0
  // 跳帧计数器：IDLE 状态只每 3 帧重绘一次
  private frameSkipCounter: number = 0
  private readonly FRAME_SKIP_IDLE: number = 3
  private readonly FRAME_SKIP_ACTIVE: number = 2

  aboutToAppear(): void {
    this.startAnimationLoop()
  }

  aboutToDisappear(): void {
    this.pauseAnimation()
  }

  private pauseAnimation(): void {
    if (this.animationTimer !== -1) {
      clearTimeout(this.animationTimer)
      this.animationTimer = -1
    }
  }

  private resumeAnimation(): void {
    if (this.animationTimer !== -1) return
    this.startAnimationLoop()
  }

  onStatusChange(): void {
    this.bounceValue = 0
    this.jumpValue = 0
    this.armWaveValue = 0
    this.starOpacityValue = 0.5
    this.animationTime = 0
    this.dexBounceValue = 0
    this.dexJumpValue = 0
  }

  onColorChange(): void {
    this.redrawCanvas()
  }

  private startAnimationLoop(): void {
    this.lastFrameTime = Date.now()
    this.frameSkipCounter = 0
    this.animationLoop()
  }

  private animationLoop(): void {
    const now = Date.now()
    const delta = now - this.lastFrameTime
    this.lastFrameTime = now
    this.animationTime += delta

    this.updateAnimationValues()

    // 跳帧：前 2 帧始终绘制，之后 IDLE 每 3 帧绘一次，其他状态每 2 帧绘一次
    this.frameSkipCounter++
    const skipMod = this.frameSkipCounter < 3 ? 1 :
      (this.status === MascotStatus.IDLE ? this.FRAME_SKIP_IDLE : this.FRAME_SKIP_ACTIVE)
    if (this.frameSkipCounter % skipMod === 0) {
      this.redrawCanvas()
    }

    this.animationTimer = setTimeout(() => { this.animationLoop() }, 16)
  }

  private updateAnimationValues(): void {
    const t = this.animationTime

    // Claude 动画
    // 睡眠呼吸：4.5s 周期，前40%呼吸
    const sleepPhase = (t % 4500) / 4500
    this.breatheValue = sleepPhase < 0.4 ? Math.sin(sleepPhase / 0.4 * Math.PI) : 0
    this.zzzOffset1 = (t % 3000) / 3000
    this.zzzOffset2 = ((t + 900) % 3000) / 3000
    this.zzzOffset3 = ((t + 1800) % 3000) / 3000
    // 工作弹跳：0.35s
    this.bounceValue = Math.sin(t * 2 * Math.PI / 350) * 1.2
    // 工作手臂旋转打字（左0.15s/右0.12s周期）
    const armLRaw = Math.sin(t * 2 * Math.PI / 150)
    this.claudeArmL = armLRaw * 22.5 - 32.5   // -55 to -10
    const armRRaw = Math.sin(t * 2 * Math.PI / 120)
    this.claudeArmR = armRRaw * 22.5 + 32.5   // 10 to 55
    // 工作眨眼/扫视
    const scanPhase = (t % 10000) / 10000
    this.claudeEyeScale = (scanPhase > 0.57 && scanPhase < 0.69) ? 1.0 : 0.5
    this.claudeEyeDY = this.claudeEyeScale < 0.8 ? 1.0 : -0.5
    const blinkPhase = (t % 3500) / 3500
    this.claudeEyeScale = (blinkPhase > 0.4 && blinkPhase < 0.44) ? 0.1 : this.claudeEyeScale
    // 警告跳跃
    this.jumpValue = (t % 3500) / 3500
    // 完成
    this.armWaveValue = (t % 600) / 600
    this.starOpacityValue = 0.5 + 0.5 * Math.abs(Math.sin(t * Math.PI / 150))

    // Dex 动画
    this.dexFloatValue = Math.sin((t % 4000) / 4000 * 2 * Math.PI) * 0.8
    this.dexBounceValue = Math.sin(t * 2 * Math.PI / 400) * 1.0
    this.dexJumpValue = (t % 3500) / 3500

    // Dex 光标闪烁
    if (this.status === MascotStatus.IDLE) {
      // 慢闪：1.2s 周期，0.6s 亮
      this.dexCursorOn = (t % 1200) < 600
    } else if (this.status === MascotStatus.PROCESSING) {
      // 快闪：0.3s 周期，0.15s 亮
      this.dexCursorOn = (t % 300) < 150
    } else {
      this.dexCursorOn = true
    }

    // Dex 键盘按键闪烁
    this.dexKeyPhase = Math.floor(t / 100) % 6
  }

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
        .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
          if (isVisible) {
            this.resumeAnimation()
          } else {
            this.pauseAnimation()
          }
        })

      // ZZZ 睡眠符号
      if (this.status === MascotStatus.IDLE) {
        this.ZzzAnimatedView()
      }
    }
    .width(this.mascotSize)
    .height(this.mascotSize)
  }

  private drawMascot(): void {
    if (!this.context) return

    if (this.mascotType === MascotType.CODEX) {
      this.drawDexMascot()
    } else if (this.mascotType === MascotType.OPEN_CODE) {
      this.drawOpenCodeMascot()
    } else {
      this.drawClaudeMascot()
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Claude 像素猫（原有逻辑）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  private drawClaudeMascot(): void {
    switch (this.status) {
      case MascotStatus.IDLE:
        this.drawClaudeSleep()
        break
      case MascotStatus.PROCESSING:
        this.drawClaudeWork()
        break
      case MascotStatus.WAITING_APPROVAL:
        this.drawClaudeAlert()
        break
      case MascotStatus.COMPLETED:
        this.drawClaudeCompleted()
        break
    }
  }

  private drawPixelRect(x: number, y: number, w: number, h: number, color: string): void {
    this.context.fillStyle = color
    this.context.fillRect(x, y, w, h)
  }

  // Claude 手臂旋转多边形（绕 pivot 旋转一个矩形）
  private drawClaudeArm(v: DexV, x: number, y: number, w: number, h: number,
    pivotX: number, pivotY: number, angle: number, dy: number): void {
    const a = angle * Math.PI / 180
    const ca = Math.cos(a)
    const sa = Math.sin(a)
    const corners: number[][] = [
      [x - pivotX, y - pivotY],
      [x + w - pivotX, y - pivotY],
      [x + w - pivotX, y + h - pivotY],
      [x - pivotX, y + h - pivotY],
    ]
    this.context.fillStyle = this.bodyColor
    this.context.beginPath()
    for (let i = 0; i < 4; i++) {
      const cx = corners[i][0]
      const cy = corners[i][1]
      const rx = cx * ca - cy * sa + pivotX
      const ry = cx * sa + cy * ca + pivotY
      const px = v.ox + rx * v.s
      const py = v.oy + (ry - v.y0 + dy) * v.s
      if (i === 0) {
        this.context.moveTo(px, py)
      } else {
        this.context.lineTo(px, py)
      }
    }
    this.context.closePath()
    this.context.fill()
  }

  // ── Claude 睡眠：sploot 趴姿 + 呼吸 ──
  private drawClaudeSleep(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 17, 7, 9)
    const breathe = this.breatheValue

    // 影子（随呼吸变大）
    const shadowScale = 1.0 + breathe * 0.03
    const rect = this.dexRect(v, -1, 15, 17 * shadowScale, 1)
    this.context.fillStyle = `rgba(0,0,0,${0.35 + breathe * 0.08})`
    this.context.fillRect(rect[0], rect[1], rect[2], rect[3])

    // 腿朝天
    for (const x of [3, 5, 9, 11]) {
      const r = this.dexRect(v, x, 8.5, 1, 1.5)
      this.drawPixelRect(r[0], r[1], r[2], r[3], this.bodyColor)
    }

    // 身体膨胀
    const puff = Math.max(0, breathe) * 0.25
    const torsoH = 5 * (1.0 + puff)
    const torsoY = 15 - torsoH
    const torsoW = 13 * (1.0 + breathe * 0.015)
    const torsoX = 1 - (torsoW - 13) / 2
    const tr = this.dexRect(v, torsoX, torsoY, torsoW, torsoH)
    this.drawPixelRect(tr[0], tr[1], tr[2], tr[3], this.bodyColor)

    // 手臂摊开
    const r1 = this.dexRect(v, -1, 13, 2, 2)
    this.drawPixelRect(r1[0], r1[1], r1[2], r1[3], this.bodyColor)
    const r2 = this.dexRect(v, 14, 13, 2, 2)
    this.drawPixelRect(r2[0], r2[1], r2[2], r2[3], this.bodyColor)

    // 闭眼
    const eyeY = 12.2 - puff * 2.5
    const e1 = this.dexRect(v, 3, eyeY, 2.5, 1.0)
    this.drawPixelRect(e1[0], e1[1], e1[2], e1[3], this.eyeColor)
    const e2 = this.dexRect(v, 9.5, eyeY, 2.5, 1.0)
    this.drawPixelRect(e2[0], e2[1], e2[2], e2[3], this.eyeColor)
  }

  // ── Claude 工作：弹跳 + 手臂旋转打字 + 键盘 ──
  private drawClaudeWork(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 16, 11, 5.5)
    const dy = this.bounceValue
    const breathe = Math.sin(this.animationTime * 2 * Math.PI / 3200)

    // 手臂命中判断
    const armLRaw = Math.sin(this.animationTime * 2 * Math.PI / 150)
    const armRRaw = Math.sin(this.animationTime * 2 * Math.PI / 120)
    const leftHit = armLRaw > 0.3
    const rightHit = armRRaw > 0.3
    const leftKeyCol = Math.floor(this.animationTime / 150) % 3
    const rightKeyCol = 3 + Math.floor(this.animationTime / 120) % 3

    // 影子
    const shadowW = 9 - Math.abs(dy) * 0.3
    const sr = this.dexRect(v, 3 + (9 - shadowW) / 2, 15, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${Math.max(0.1, 0.4 - Math.abs(dy) * 0.03)})`
    this.context.fillRect(sr[0], sr[1], sr[2], sr[3])

    // 腿
    for (const x of [3, 5, 9, 11]) {
      const r = this.dexRect(v, x, 13, 1, 2)
      this.drawPixelRect(r[0], r[1], r[2], r[3], this.bodyColor)
    }

    // 身体
    const bScale = 1.0 + breathe * 0.015
    const torsoW = 11 * bScale
    const tr = this.dexRect(v, 2 - (torsoW - 11) / 2, 6, torsoW, 7, dy)
    this.drawPixelRect(tr[0], tr[1], tr[2], tr[3], this.bodyColor)

    // 眼睛
    const eyeH = 2 * this.claudeEyeScale
    const eyeY = 8 + (2 - eyeH) / 2 + this.claudeEyeDY
    const e1 = this.dexRect(v, 4, eyeY, 1, eyeH, dy)
    this.drawPixelRect(e1[0], e1[1], e1[2], e1[3], this.eyeColor)
    const e2 = this.dexRect(v, 10, eyeY, 1, eyeH, dy)
    this.drawPixelRect(e2[0], e2[1], e2[2], e2[3], this.eyeColor)

    // 键盘底座
    const kb = this.dexRect(v, -0.5, 11.8, 16, 3.5)
    this.drawPixelRect(kb[0], kb[1], kb[2], kb[3], this.kbBaseColor)
    // 键盘按键 3行6列
    for (let row = 0; row < 3; row++) {
      for (let col = 0; col < 6; col++) {
        const kx = 0.3 + col * 2.5
        const ky = 12.2 + row * 1.0
        const w = (col === 2 && row === 1) ? 4.5 : 2.0
        const kr = this.dexRect(v, kx, ky, w, 0.7)
        this.drawPixelRect(kr[0], kr[1], kr[2], kr[3], this.kbKeyColor)
      }
    }
    // 按键闪烁
    if (leftHit) {
      const row = leftKeyCol % 3
      const kx = 0.3 + leftKeyCol * 2.5
      const ky = 12.2 + row * 1.0
      const fr = this.dexRect(v, kx, ky, 2.0, 0.7)
      this.context.globalAlpha = 0.9
      this.drawPixelRect(fr[0], fr[1], fr[2], fr[3], '#FFFFFF')
      this.context.globalAlpha = 1
    }
    if (rightHit) {
      const row = (rightKeyCol - 3) % 3
      const kx = 0.3 + rightKeyCol * 2.5
      const ky = 12.2 + row * 1.0
      const fr = this.dexRect(v, kx, ky, 2.0, 0.7)
      this.context.globalAlpha = 0.9
      this.drawPixelRect(fr[0], fr[1], fr[2], fr[3], '#FFFFFF')
      this.context.globalAlpha = 1
    }

    // 手臂旋转打字
    this.drawClaudeArm(v, 0, 9, 2, 2, 2, 10, this.claudeArmL, dy)
    this.drawClaudeArm(v, 13, 9, 2, 2, 13, 10, this.claudeArmR, dy)
  }

  // ── Claude 警告：跳跃 + squash/stretch + 手臂挥舞 ──
  private drawClaudeAlert(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 15, 12, 4)
    const pct = this.jumpValue

    const jumpY = this.calculateJumpY(pct)

    // squash/stretch
    const scaleX = jumpY > 0.5 ? 1.0 + jumpY * 0.05 : 1.0
    const scaleY = jumpY > 0.5 ? 1.0 - jumpY * 0.04 : 1.0

    // 手臂关键帧
    const armL = this.lerpDex([
      [0, 0], [0.03, 0], [0.10, 25],
      [0.15, 30], [0.20, 155], [0.25, 115],
      [0.30, 140], [0.35, 100], [0.40, 115],
      [0.45, 80], [0.50, 80], [0.55, 40],
      [0.62, 0], [1.0, 0]
    ], pct)
    const armR = -this.lerpDex([
      [0, 0], [0.03, 0], [0.10, 30],
      [0.15, 30], [0.20, 155], [0.25, 115],
      [0.30, 140], [0.35, 100], [0.40, 115],
      [0.45, 80], [0.50, 80], [0.55, 40],
      [0.62, 0], [1.0, 0]
    ], pct)

    // 眼睛惊吓
    const eyeScale = (pct > 0.03 && pct < 0.15) ? 1.3 : 1.0
    const eyeDY = (pct > 0.03 && pct < 0.15) ? -0.5 : 0

    // 影子
    const shadowW = 9 * (1.0 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const shadowOp = Math.max(0.08, 0.5 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const sr = this.dexRect(v, 3 + (9 - shadowW) / 2, 15, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${shadowOp})`
    this.context.fillRect(sr[0], sr[1], sr[2], sr[3])

    // 腿
    for (const x of [3, 5, 9, 11]) {
      const r = this.dexRect(v, x, 11, 1, 4)
      this.drawPixelRect(r[0], r[1], r[2], r[3], this.bodyColor)
    }

    // 身体（squash/stretch）
    const torsoW = 11 * scaleX
    const torsoH = 7 * scaleY
    const torsoX = 2 - (torsoW - 11) / 2
    const torsoY = 6 + (7 - torsoH)
    const tr = this.dexRect(v, torsoX, torsoY, torsoW, torsoH, jumpY)
    this.drawPixelRect(tr[0], tr[1], tr[2], tr[3], this.bodyColor)

    // 眼睛
    const eyeH = 2 * eyeScale
    const eyeY = 8 + (2 - eyeH) / 2 + eyeDY
    const e1 = this.dexRect(v, 4, eyeY, 1, eyeH, jumpY)
    this.drawPixelRect(e1[0], e1[1], e1[2], e1[3], this.eyeColor)
    const e2 = this.dexRect(v, 10, eyeY, 1, eyeH, jumpY)
    this.drawPixelRect(e2[0], e2[1], e2[2], e2[3], this.eyeColor)

    // 手臂挥舞
    this.drawClaudeArm(v, 0, 9, 2, 2, 2, 10, armL, jumpY)
    this.drawClaudeArm(v, 13, 9, 2, 2, 13, 10, armR, jumpY)

    // 感叹号
    const bangOp = this.lerpDex([
      [0, 0], [0.03, 1], [0.10, 1], [0.55, 1], [0.62, 0], [1.0, 0]
    ], pct)
    const bangScale = this.lerpDex([
      [0, 0.3], [0.03, 1.3], [0.10, 1.0], [0.55, 1.0], [0.62, 0.6], [1.0, 0.6]
    ], pct)
    if (bangOp > 0.01) {
      const bw = 2 * bangScale
      const bx = 13
      const by = 4.5 + jumpY * 0.15
      this.context.globalAlpha = bangOp
      const br1 = this.dexRect(v, bx, by, bw, 3.5 * bangScale)
      this.drawPixelRect(br1[0], br1[1], br1[2], br1[3], this.alertColor)
      const br2 = this.dexRect(v, bx, by + 4.0 * bangScale, bw, 1.5 * bangScale)
      this.drawPixelRect(br2[0], br2[1], br2[2], br2[3], this.alertColor)
      this.context.globalAlpha = 1
    }
  }

  // ── Claude 完成：弹跳 + 手臂挥动 + 微笑 ──
  private drawClaudeCompleted(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 17, 14, 5)
    const bounce = Math.sin(this.armWaveValue * 2 * Math.PI / 1.5) * 1
    const armWave = Math.sin(this.armWaveValue * 2 * Math.PI / 0.6) * 0.5

    // 影子
    const sr = this.dexRect(v, 3, 15, 9, 1)
    this.context.fillStyle = 'rgba(0,0,0,0.3)'
    this.context.fillRect(sr[0], sr[1], sr[2], sr[3])

    // 腿
    for (const x of [3, 5, 9, 11]) {
      const r = this.dexRect(v, x, 11 + bounce * 0.3, 1, 3)
      this.drawPixelRect(r[0], r[1], r[2], r[3], this.bodyColor)
    }

    // 身体
    const tr = this.dexRect(v, 2, 6 + bounce, 11, 6)
    this.drawPixelRect(tr[0], tr[1], tr[2], tr[3], this.bodyColor)

    // 开心眼睛
    const e1 = this.dexRect(v, 3.5, 8 + bounce, 1, 1)
    this.drawPixelRect(e1[0], e1[1], e1[2], e1[3], this.eyeColor)
    const e1t = this.dexRect(v, 4.5, 7.5 + bounce, 0.5, 0.5)
    this.drawPixelRect(e1t[0], e1t[1], e1t[2], e1t[3], this.eyeColor)
    const e2 = this.dexRect(v, 9.5, 8 + bounce, 1, 1)
    this.drawPixelRect(e2[0], e2[1], e2[2], e2[3], this.eyeColor)
    const e2t = this.dexRect(v, 9, 7.5 + bounce, 0.5, 0.5)
    this.drawPixelRect(e2t[0], e2t[1], e2t[2], e2t[3], this.eyeColor)

    // 微笑
    const sm = this.dexRect(v, 6, 10 + bounce, 3, 0.8)
    this.context.fillStyle = this.eyeColor
    this.context.beginPath()
    this.context.roundRect(sm[0], sm[1], sm[2], sm[3], 0.4 * v.s)
    this.context.fill()

    // 举起手臂
    const a1 = this.dexRect(v, -1, 2 + bounce + armWave, 2, 5)
    this.drawPixelRect(a1[0], a1[1], a1[2], a1[3], this.bodyColor)
    const a2 = this.dexRect(v, 14, 2 + bounce - armWave, 2, 5)
    this.drawPixelRect(a2[0], a2[1], a2[2], a2[3], this.bodyColor)

    // 星星
    this.context.globalAlpha = this.starOpacityValue
    const s1 = this.dexRect(v, -2, 1, 1, 1)
    this.drawPixelRect(s1[0], s1[1], s1[2], s1[3], this.starColor)
    const s2 = this.dexRect(v, 16, 0, 1.2, 1.2)
    this.drawPixelRect(s2[0], s2[1], s2[2], s2[3], this.starColor)
    this.context.globalAlpha = 1
  }

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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Dex — Codex 像素风云朵（移植自 DexView.swift）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  private drawDexMascot(): void {
    switch (this.status) {
      case MascotStatus.IDLE:
        this.drawDexSleep()
        break
      case MascotStatus.PROCESSING:
        this.drawDexWork()
        break
      case MascotStatus.WAITING_APPROVAL:
        this.drawDexAlert()
        break
      case MascotStatus.COMPLETED:
        this.drawDexCompleted()
        break
    }
  }

  // Dex 坐标系辅助（对应 iOS V 结构体）
  private dexV(sz: number): DexV {
    return new DexV(sz, 15, 10, 6)
  }

  // Dex 大号坐标（工作/警告状态需要键盘）
  private dexVLarge(sz: number): DexV {
    return new DexV(sz, 16, 14, 3)
  }

  // 映射矩形到实际坐标
  private dexRect(v: DexV,
    x: number, y: number, w: number, h: number, dy: number = 0): number[] {
    return [
      v.ox + x * v.s,
      v.oy + (y - v.y0 + dy) * v.s,
      w * v.s,
      h * v.s
    ]
  }

  // 绘制像素风云朵身体
  private drawDexCloud(v: DexV,
    dy: number, squashX: number = 1, squashY: number = 1): void {
    const cx = 7.5
    // 云朵像素行定义
    const rows: number[][] = [
      [14, 4, 7],       // bottom
      [13, 3, 9],
      [12, 2, 11],
      [11, 1, 13],      // widest
      [10, 1, 13],
      [9, 1, 13],
      [8, 2, 11],
      [7, 2, 11],
      // Top bumps (cloud silhouette)
      [6, 3, 3],        // left bump
      [6, 6, 3],        // center bump
      [6, 9, 3],        // right bump
      [5, 4, 2],        // left bump top
      [5, 6.5, 2],      // center bump top
      [5, 9, 2],        // right bump top
    ]

    for (const row of rows) {
      let rx = row[1]
      let rw = row[2]
      let ry = row[0]
      let rh = 1
      // 应用 squash
      rx = cx + (rx - cx) * squashX
      rw = rw * squashX
      ry = ry * squashY + (1 - squashY) * 10
      rh = rh * squashY

      const rect = this.dexRect(v, rx, ry, rw, rh, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
    }
  }

  // 绘制 >_ 终端提示符
  private drawDexPrompt(v: DexV,
    dy: number, color: string = this.DEX_PROMPT, cursorOn: boolean = true): void {
    // `>` chevron — 3个像素方块组成V形
    let rect = this.dexRect(v, 3, 10, 1, 1, dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], color)
    rect = this.dexRect(v, 4, 11, 1, 1, dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], color)
    rect = this.dexRect(v, 3, 12, 1, 1, dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], color)

    // `_` cursor
    if (cursorOn) {
      rect = this.dexRect(v, 6, 12, 3, 1, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], color)
    }
  }

  // 绘制阴影
  private drawDexShadow(v: DexV,
    width: number = 9, opacity: number = 0.3): void {
    const rect = this.dexRect(v, 7.5 - width / 2, 15, width, 1)
    this.context.fillStyle = `rgba(0,0,0,${opacity})`
    this.context.fillRect(rect[0], rect[1], rect[2], rect[3])
  }

  // 绘制小短腿
  private drawDexLegs(v: DexV): void {
    let rect = this.dexRect(v, 5, 14.5, 1, 1.5)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
    rect = this.dexRect(v, 9, 14.5, 1, 1.5)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
  }

  // ── Dex 睡眠：浮动 + 光标慢闪 ──
  private drawDexSleep(): void {
    const sz = this.mascotSize
    const v = this.dexV(sz)
    const dy = this.dexFloatValue

    this.drawDexShadow(v, 7 + Math.abs(dy) * 0.3, 0.2)
    this.drawDexLegs(v)
    this.drawDexCloud(v, dy)

    // 睡眠：只显示暗淡光标（不显示 > 号，= 嘴巴闭着）
    if (this.dexCursorOn) {
      const rect = this.dexRect(v, 6, 12, 3, 1, dy)
      this.context.fillStyle = 'rgba(0,0,0,0.3)'
      this.context.fillRect(rect[0], rect[1], rect[2], rect[3])
    }
  }

  // ── Dex 工作：弹跳 + 键盘 + 光标快闪 ──
  private drawDexWork(): void {
    const sz = this.mascotSize
    const v = this.dexVLarge(sz)
    const dy = this.dexBounceValue

    // 影子
    const shadowW = 8 - Math.abs(dy) * 0.3
    const shadowRect = this.dexRect(v, 4 + (8 - shadowW) / 2, 16, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${Math.max(0.1, 0.35 - Math.abs(dy) * 0.03)})`
    this.context.fillRect(shadowRect[0], shadowRect[1], shadowRect[2], shadowRect[3])

    this.drawDexLegs(v)

    // 键盘底座
    let rect = this.dexRect(v, 0, 13, 15, 3)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.DEX_KB_BASE)

    // 键盘按键
    for (let row = 0; row < 2; row++) {
      for (let col = 0; col < 6; col++) {
        const kx = 0.5 + col * 2.4
        const ky = 13.5 + row * 1.2
        rect = this.dexRect(v, kx, ky, 1.8, 0.7)
        this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.DEX_KB_KEY)
      }
    }

    // 按键闪烁
    const flashRow = Math.floor(this.dexKeyPhase / 3)
    const flashCol = this.dexKeyPhase % 6
    const fkx = 0.5 + flashCol * 2.4
    const fky = 13.5 + flashRow * 1.2
    rect = this.dexRect(v, fkx, fky, 1.8, 0.7)
    this.context.globalAlpha = 0.9
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.DEX_KB_HI)
    this.context.globalAlpha = 1

    this.drawDexCloud(v, dy)
    this.drawDexPrompt(v, dy, this.DEX_PROMPT, this.dexCursorOn)
  }

  // ── Dex 警告：跳跃 + 抖动 + 提示符闪烁 ──
  private drawDexAlert(): void {
    const sz = this.mascotSize
    const v = this.dexVLarge(sz)
    const pct = this.dexJumpValue

    // 跳跃关键帧
    const jumpY = this.calculateDexJumpY(pct)

    // 挤压拉伸
    const squashX = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
    const squashY = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0

    // 水平抖动
    const shakeX = (pct > 0.15 && pct < 0.55) ? Math.sin(pct * 80) * 0.6 : 0

    // 提示符颜色闪烁（黑/琥珀色）
    const flash = (pct > 0.03 && pct < 0.55) ? Math.sin(pct * 25) * 0.5 + 0.5 : 0.0
    const promptColor = flash > 0.5 ? this.DEX_ALERT_C : this.DEX_PROMPT

    // 感叹号
    const bangOp = this.lerpDex([
      [0, 0], [0.03, 1], [0.10, 1], [0.55, 1], [0.62, 0], [1.0, 0]
    ], pct)
    const bangScale = this.lerpDex([
      [0, 0.3], [0.03, 1.3], [0.10, 1.0], [0.55, 1.0], [0.62, 0.6], [1.0, 0.6]
    ], pct)

    // 影子
    const shadowW = 8 * (1.0 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const shadowOp = Math.max(0.08, 0.4 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const shadowRect = this.dexRect(v, 4 + (8 - shadowW) / 2, 16, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${shadowOp})`
    this.context.fillRect(shadowRect[0], shadowRect[1], shadowRect[2], shadowRect[3])

    this.drawDexLegs(v)

    // 云朵身体（带抖动偏移）
    this.context.save()
    this.context.translate(shakeX * v.s, 0)
    this.drawDexCloud(v, jumpY, squashX, squashY)
    this.drawDexPrompt(v, jumpY, promptColor, true)
    this.context.restore()

    // 感叹号
    if (bangOp > 0.01) {
      const bw = 2 * bangScale
      const bx = 13
      const by = 4 + jumpY * 0.15
      let rect = this.dexRect(v, bx, by, bw, 3.5 * bangScale)
      this.context.globalAlpha = bangOp
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.DEX_ALERT_C)
      rect = this.dexRect(v, bx, by + 4.0 * bangScale, bw, 1.5 * bangScale)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.DEX_ALERT_C)
      this.context.globalAlpha = 1
    }
  }

  // ── Dex 完成：弹跳 + 星星闪烁 ──
  private drawDexCompleted(): void {
    const sz = this.mascotSize
    const v = this.dexVLarge(sz)
    const bounce = Math.sin(this.armWaveValue * 2 * Math.PI / 1.5) * 1

    // 影子
    this.drawDexShadow(v, 8, 0.3)
    this.drawDexLegs(v)
    this.drawDexCloud(v, bounce)
    this.drawDexPrompt(v, bounce, this.DEX_PROMPT, true)

    // 星星
    this.context.globalAlpha = this.starOpacityValue
    const v2 = this.dexV(sz)
    let rect = this.dexRect(v2, 0, 3, 1, 1, bounce)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.starColor)
    rect = this.dexRect(v2, 13, 2, 1.2, 1.2, bounce)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.starColor)
    this.context.globalAlpha = 1
  }

  // Dex 跳跃关键帧
  private calculateDexJumpY(pct: number): number {
    const keyframes = [
      [0, 0], [0.03, 0], [0.10, -1], [0.15, 1.5],
      [0.175, -8], [0.20, -8], [0.25, 1.5],
      [0.275, -6], [0.30, -6], [0.35, 1.0],
      [0.375, -4], [0.40, -4], [0.45, 0.8],
      [0.475, -2], [0.50, -2], [0.55, 0.3],
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

  // Dex 关键帧插值
  private lerpDex(keyframes: number[][], pct: number): number {
    if (keyframes.length === 0) return 0
    if (pct <= keyframes[0][0]) return keyframes[0][1]
    for (let i = 1; i < keyframes.length; i++) {
      if (pct <= keyframes[i][0]) {
        const t = (pct - keyframes[i - 1][0]) / (keyframes[i][0] - keyframes[i - 1][0])
        return keyframes[i - 1][1] + (keyframes[i][1] - keyframes[i - 1][1]) * t
      }
    }
    return keyframes[keyframes.length - 1][1]
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // OpBot — OpenCode 暗色代码块 + { } 大括号脸
  // （移植自 OpenCodeView.swift）
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  private drawOpenCodeMascot(): void {
    switch (this.status) {
      case MascotStatus.IDLE:
        this.drawOCSleep()
        break
      case MascotStatus.PROCESSING:
        this.drawOCWork()
        break
      case MascotStatus.WAITING_APPROVAL:
        this.drawOCAlert()
        break
      case MascotStatus.COMPLETED:
        this.drawOCCompleted()
        break
    }
  }

  // 绘制暗色方块身体
  private drawOCBlock(v: DexV, dy: number, squashX: number = 1, squashY: number = 1): void {
    const cx = 7.5
    const bodyRows: number[][] = [
      [5, 3, 9],    // top
      [6, 2, 11],
      [7, 2, 11],
      [8, 2, 11],
      [9, 2, 11],
      [10, 2, 11],
      [11, 2, 11],
      [12, 2, 11],
      [13, 3, 9],   // bottom
    ]

    for (const row of bodyRows) {
      let rx = cx + (row[1] - cx) * squashX
      let rw = row[2] * squashX
      let ry = row[0] * squashY + (1 - squashY) * 10
      let rh = 1 * squashY
      const rect = this.dexRect(v, rx, ry, rw, rh, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
    }

    // 内边框 — 顶部和底部
    const frameRows: number[][] = [
      [6, 3, 9],
      [12, 3, 9],
    ]
    for (const row of frameRows) {
      let rx = cx + (row[1] - cx) * squashX
      let rw = row[2] * squashX
      let ry = row[0] * squashY + (1 - squashY) * 10
      let rh = 0.7 * squashY
      const rect = this.dexRect(v, rx, ry, rw, rh, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FRAME)
    }

    // 内边框 — 左右
    for (let y = 7; y < 12; y++) {
      let lx = cx + (3 - cx) * squashX
      let rx = cx + (11.3 - cx) * squashX
      let ry = y * squashY + (1 - squashY) * 10
      let rect = this.dexRect(v, lx, ry, 0.7 * squashX, 1 * squashY, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FRAME)
      rect = this.dexRect(v, rx, ry, 0.7 * squashX, 1 * squashY, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FRAME)
    }
  }

  // 绘制 { } 大括号脸
  private drawOCFace(v: DexV, dy: number, eyeScale: number = 1.0): void {
    const eyeH = Math.max(0.3, 2.0 * eyeScale)
    const eyeY = 8.5 + (2.0 - eyeH) / 2

    // 左括号 {
    let rect = this.dexRect(v, 4.5, eyeY, 0.8, eyeH, dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FACE)
    rect = this.dexRect(v, 4.0, eyeY + eyeH * 0.3, 0.7, Math.max(0.3, eyeH * 0.4), dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FACE)

    // 右括号 }
    rect = this.dexRect(v, 9.7, eyeY, 0.8, eyeH, dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FACE)
    rect = this.dexRect(v, 10.2, eyeY + eyeH * 0.3, 0.7, Math.max(0.3, eyeH * 0.4), dy)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FACE)

    // 中间圆点光标
    if (eyeScale > 0.5) {
      rect = this.dexRect(v, 7.1, 9.2, 0.8, 0.8, dy)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_FACE)
    }
  }

  // OC 阴影
  private drawOCShadow(v: DexV, width: number = 9, opacity: number = 0.3): void {
    const rect = this.dexRect(v, 7.5 - width / 2, 14.5, width, 1)
    this.context.fillStyle = `rgba(0,0,0,${opacity})`
    this.context.fillRect(rect[0], rect[1], rect[2], rect[3])
  }

  // OC 小短腿
  private drawOCLegs(v: DexV): void {
    let rect = this.dexRect(v, 4, 13.5, 1, 1.5)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
    rect = this.dexRect(v, 10, 13.5, 1, 1.5)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.bodyColor)
  }

  // ── OC 睡眠：浮动 + 半闭眼 ──
  private drawOCSleep(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 15, 12, 4)
    const dy = this.dexFloatValue

    this.drawOCShadow(v, 7 + Math.abs(dy) * 0.3, 0.2)
    this.drawOCLegs(v)
    this.drawOCBlock(v, dy)
    // 睡眠：半闭眼
    this.context.globalAlpha = 0.4
    this.drawOCFace(v, dy, 0.3)
    this.context.globalAlpha = 1
  }

  // ── OC 工作：弹跳 + 键盘 + 眨眼 ──
  private drawOCWork(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 16, 14, 3)
    const dy = this.dexBounceValue

    // 眨眼
    const blinkCycle = (this.animationTime % 3000) / 3000
    const blink = (blinkCycle > 0.86 && blinkCycle < 0.91) ? 0.1 : 1.0

    // 影子
    const shadowW = 8 - Math.abs(dy) * 0.3
    const shadowRect = this.dexRect(v, 4 + (8 - shadowW) / 2, 16, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${Math.max(0.1, 0.35 - Math.abs(dy) * 0.03)})`
    this.context.fillRect(shadowRect[0], shadowRect[1], shadowRect[2], shadowRect[3])

    this.drawOCLegs(v)

    // 键盘
    let rect = this.dexRect(v, 0, 13, 15, 3)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_KB_BASE)
    for (let row = 0; row < 2; row++) {
      for (let col = 0; col < 6; col++) {
        const kx = 0.5 + col * 2.4
        const ky = 13.5 + row * 1.2
        rect = this.dexRect(v, kx, ky, 1.8, 0.7)
        this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_KB_KEY)
      }
    }

    // 按键闪烁
    const flashCol = this.dexKeyPhase % 6
    const flashRow = Math.floor(this.dexKeyPhase / 3)
    const fkx = 0.5 + flashCol * 2.4
    const fky = 13.5 + flashRow * 1.2
    rect = this.dexRect(v, fkx, fky, 1.8, 0.7)
    this.context.globalAlpha = 0.9
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_KB_HI)
    this.context.globalAlpha = 1

    this.drawOCBlock(v, dy)
    this.drawOCFace(v, dy, blink)
  }

  // ── OC 警告：跳跃 + 抖动 + 感叹号 ──
  private drawOCAlert(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 16, 14, 3)
    const pct = this.dexJumpValue

    const jumpY = this.calculateDexJumpY(pct)
    const squashX = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
    const squashY = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0
    const shakeX = (pct > 0.15 && pct < 0.55) ? Math.sin(pct * 80) * 0.6 : 0

    const bangOp = this.lerpDex([
      [0, 0], [0.03, 1], [0.10, 1], [0.55, 1], [0.62, 0], [1.0, 0]
    ], pct)
    const bangScale = this.lerpDex([
      [0, 0.3], [0.03, 1.3], [0.10, 1.0], [0.55, 1.0], [0.62, 0.6], [1.0, 0.6]
    ], pct)

    // 影子
    const shadowW = 8 * (1.0 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const shadowOp = Math.max(0.08, 0.4 - Math.abs(Math.min(0, jumpY)) * 0.04)
    const shadowRect = this.dexRect(v, 4 + (8 - shadowW) / 2, 16, shadowW, 1)
    this.context.fillStyle = `rgba(0,0,0,${shadowOp})`
    this.context.fillRect(shadowRect[0], shadowRect[1], shadowRect[2], shadowRect[3])

    this.drawOCLegs(v)

    // 身体（带抖动偏移）
    this.context.save()
    this.context.translate(shakeX * v.s, 0)
    this.drawOCBlock(v, jumpY, squashX, squashY)
    // 警告时眼睛放大
    const eyeScale = (pct > 0.03 && pct < 0.15) ? 1.3 : 1.0
    this.drawOCFace(v, jumpY, eyeScale)
    this.context.restore()

    // 感叹号
    if (bangOp > 0.01) {
      const bw = 2 * bangScale
      const bx = 13
      const by = 4 + jumpY * 0.15
      let rect = this.dexRect(v, bx, by, bw, 3.5 * bangScale)
      this.context.globalAlpha = bangOp
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_ALERT_C)
      rect = this.dexRect(v, bx, by + 4.0 * bangScale, bw, 1.5 * bangScale)
      this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.OC_ALERT_C)
      this.context.globalAlpha = 1
    }
  }

  // ── OC 完成：弹跳 + 星星 ──
  private drawOCCompleted(): void {
    const sz = this.mascotSize
    const v = new DexV(sz, 16, 14, 3)
    const bounce = Math.sin(this.armWaveValue * 2 * Math.PI / 1.5) * 1

    this.drawOCShadow(v, 8, 0.3)
    this.drawOCLegs(v)
    this.drawOCBlock(v, bounce)
    this.drawOCFace(v, bounce, 1.0)

    // 星星
    this.context.globalAlpha = this.starOpacityValue
    const v2 = new DexV(sz, 15, 12, 4)
    let rect = this.dexRect(v2, 0, 3, 1, 1, bounce)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.starColor)
    rect = this.dexRect(v2, 13, 2, 1.2, 1.2, bounce)
    this.drawPixelRect(rect[0], rect[1], rect[2], rect[3], this.starColor)
    this.context.globalAlpha = 1
  }

  // ZZZ 动画视图
  @Builder
  ZzzAnimatedView() {
    Stack() {
      Text('z')
        .fontSize(this.mascotSize * 0.22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .opacity(this.zzzOffset1 < 0.8 ? 0.7 : (1 - this.zzzOffset1) * 3.5 * 0.7)
        .offset({
          x: this.mascotSize * 0.25,
          y: -this.mascotSize * 0.1 - this.zzzOffset1 * this.mascotSize * 0.5
        })

      Text('z')
        .fontSize(this.mascotSize * 0.18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .opacity(this.zzzOffset2 < 0.8 ? 0.6 : (1 - this.zzzOffset2) * 3.5 * 0.6)
        .offset({
          x: this.mascotSize * 0.35,
          y: -this.mascotSize * 0.1 - this.zzzOffset2 * this.mascotSize * 0.5
        })

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

// 根据 providerId 获取吉祥物类型
export function getMascotTypeForProvider(providerId: string): MascotType {
  const pid = (providerId || '').toLowerCase()
  if (pid.includes('codex') || pid.includes('openai')) return MascotType.CODEX
  if (pid.includes('opencode') || pid.includes('local')) return MascotType.OPEN_CODE
  return MascotType.CLAUDE
}
