/**
 * 权限快速审批浮动栏
 *
 * 当有未处理的权限请求时，在聊天页面底部输入区上方显示浮动栏，
 * 支持一键允许/拒绝，无需滚动到权限消息位置。
 *
 * 使用方式：
 *   PermissionQuickActionBar({
 *     pendingMessages: pendingPermissionMessages,
 *     onApprove: (msg) => { ... },
 *     onAlwaysApprove: (msg) => { ... },
 *     onReject: (msg) => { ... },
 *     onExpand: () => { ... }
 *   })
 */

import { Theme } from '../common/Theme'
import { Message } from '../models/Models'
import { hapticFeedback } from '../services/HapticFeedback'
import { curves } from '@kit.ArkUI'

// 工具图标信息（简化版，用于浮动栏）
class QuickToolIcon {
  symbol: Resource = $r('sys.symbol.lock_shield_fill')
  color: string = Theme.AccentOrange

  constructor(symbol: Resource, color: string) {
    this.symbol = symbol
    this.color = color
  }
}

function getQuickToolIcon(toolName: string): QuickToolIcon {
  switch (toolName) {
    case 'Edit':
      return new QuickToolIcon($r('sys.symbol.square_and_pencil'), Theme.WarningColor)
    case 'Write':
      return new QuickToolIcon($r('sys.symbol.doc_text'), Theme.AccentGreen)
    case 'Bash':
      return new QuickToolIcon($r('sys.symbol.gearshape'), Theme.AccentOrange)
    case 'Read':
      return new QuickToolIcon($r('sys.symbol.doc_text'), Theme.AccentBlue)
    case 'Glob':
      return new QuickToolIcon($r('sys.symbol.folder'), Theme.AccentPurple)
    case 'Grep':
      return new QuickToolIcon($r('sys.symbol.magnifyingglass'), Theme.AccentPurple)
    default:
      return new QuickToolIcon($r('sys.symbol.lock_shield_fill'), Theme.AccentOrange)
  }
}

@Component
export struct PermissionQuickActionBar {
  // 待审批的权限消息列表
  @Prop pendingMessages: Message[] = []

  // 回调
  onApprove: (message: Message) => void = () => {}
  onAlwaysApprove: (message: Message) => void = () => {}
  onReject: (message: Message) => void = () => {}
  onExpand: () => void = () => {}

  // 内部状态
  @State currentIndex: number = 0
  @State barScale: number = 1.0
  @State pulseOpacity: number = 0.6
  private pulseTimer: number = -1

  aboutToAppear(): void {
    // 脉冲动画
    this.startPulseAnimation()
  }

  aboutToDisappear(): void {
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer)
      this.pulseTimer = -1
    }
  }

  private startPulseAnimation(): void {
    this.pulseTimer = setInterval(() => {
      animateTo({ duration: 800, curve: Curve.EaseInOut }, () => {
        this.pulseOpacity = this.pulseOpacity > 0.5 ? 0.3 : 0.8
      })
    }, 800)
  }

  // 获取当前展示的权限消息
  private getCurrentMessage(): Message | null {
    if (this.pendingMessages.length === 0) return null
    const idx = Math.min(this.currentIndex, this.pendingMessages.length - 1)
    return this.pendingMessages[idx]
  }

  // 获取简短描述
  private getShortTitle(msg: Message): string {
    const toolName = msg.toolName || '操作'
    const input = msg.toolInput as Record<string, Object> | undefined
    const filePath = input?.['file_path'] as string || ''
    const fileName = filePath ? filePath.split('/').pop() || filePath : ''

    switch (toolName) {
      case 'Edit':
        return fileName ? `编辑 ${fileName}` : '编辑文件'
      case 'Write':
        return fileName ? `写入 ${fileName}` : '写入文件'
      case 'Bash':
        return '执行命令'
      case 'Read':
        return fileName ? `读取 ${fileName}` : '读取文件'
      default:
        return `${toolName} 请求权限`
    }
  }

  build() {
    if (this.pendingMessages.length === 0) {
      Row()
      return
    }

    Stack() {
      // 背景模糊层
      Column()
        .width('100%')
        .height(56)
        .backgroundColor('rgba(255, 138, 69, 0.12)')
        .borderRadius(14)
        .border({ width: 1, color: 'rgba(255, 138, 69, 0.3)' })

      // 内容行
      Row({ space: 8 }) {
        // 左侧：工具图标 + 计数 + 标题
        Row({ space: 6 }) {
          // 脉冲指示器
          Circle()
            .width(8)
            .height(8)
            .fill(Theme.AccentOrange)
            .opacity(this.pulseOpacity)

          // 工具图标
          if (this.getCurrentMessage()) {
            SymbolGlyph(getQuickToolIcon(this.getCurrentMessage()!.toolName || '').symbol)
              .fontSize(16)
              .fontColor([getQuickToolIcon(this.getCurrentMessage()!.toolName || '').color])
          }

          // 标题
          if (this.getCurrentMessage()) {
            Text(this.getShortTitle(this.getCurrentMessage()!))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TextPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }

          // 多个请求时显示计数
          if (this.pendingMessages.length > 1) {
            Text(`${this.currentIndex + 1}/${this.pendingMessages.length}`)
              .fontSize(11)
              .fontColor(Theme.AccentOrange)
              .backgroundColor('rgba(255, 138, 69, 0.15)')
              .borderRadius(8)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }
        .layoutWeight(1)

        // 右侧：操作按钮
        Row({ space: 6 }) {
          // 拒绝按钮
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([Theme.TextSecondary])
          }
          .width(32)
          .height(32)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(16)
          .onClick(() => {
            hapticFeedback.tap()
            const msg = this.getCurrentMessage()
            if (msg) {
              this.onReject(msg)
              this.advanceToNext()
            }
          })

          // 允许按钮
          Button() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([Theme.TextOnPrimary])
          }
          .width(32)
          .height(32)
          .backgroundColor(Theme.PrimaryColor)
          .borderRadius(16)
          .onClick(() => {
            hapticFeedback.submit()
            const msg = this.getCurrentMessage()
            if (msg) {
              this.onApprove(msg)
              this.advanceToNext()
            }
          })

          // 始终允许按钮
          Button() {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([Theme.AccentGreen])
          }
          .width(32)
          .height(32)
          .backgroundColor('rgba(52,199,89,0.15)')
          .borderRadius(16)
          .onClick(() => {
            hapticFeedback.submit()
            const msg = this.getCurrentMessage()
            if (msg) {
              this.onAlwaysApprove(msg)
              this.advanceToNext()
            }
          })

          // 展开按钮（查看详情）
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(12)
              .fontColor([Theme.TextTertiary])
          }
          .width(28)
          .height(28)
          .backgroundColor('rgba(255,255,255,0.06)')
          .borderRadius(14)
          .onClick(() => {
            this.onExpand()
          })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(56)
    .scale({ x: this.barScale, y: this.barScale })
    .gesture(
      PanGesture({ fingers: 1, direction: Axis.Horizontal })
        .onActionEnd((event: GestureEvent) => {
          // 左右滑动切换不同的权限请求
          if (event.offsetX < -30 && this.currentIndex < this.pendingMessages.length - 1) {
            // 左滑：下一个
            this.currentIndex++
          } else if (event.offsetX > 30 && this.currentIndex > 0) {
            // 右滑：上一个
            this.currentIndex--
          }
        })
    )
  }

  // 处理完一个后自动切换到下一个
  private advanceToNext(): void {
    // 延迟切换，等动画完成
    setTimeout(() => {
      if (this.currentIndex >= this.pendingMessages.length) {
        this.currentIndex = Math.max(0, this.pendingMessages.length - 1)
      }
    }, 200)
  }
}
