/**
 * 权限审批卡片组件
 *
 * 从 ChatDetailPage.PermissionBubble 拆分而来，独立成可复用组件。
 * 显示 AI 工具的权限请求，支持允许/始终允许/拒绝操作。
 *
 * 使用方式：
 *   PermissionApprovalCard({
 *     message: permissionMessage,
 *     onApprove: (msg) => { ... },
 *     onAlwaysApprove: (msg) => { ... },
 *     onReject: (msg) => { ... }
 *   })
 */

import { Theme } from '../common/Theme'
import { Message } from '../models/Models'
import { PermissionDiffPreview } from './PermissionDiffPreview'
import { sessionStore } from '../stores/SessionStore'
import { hapticFeedback } from '../services/HapticFeedback'

// 工具图标信息
class ToolIconInfo {
  symbol: Resource = $r('sys.symbol.gearshape')
  label: string = ''
  color: string = ''

  constructor(symbol: Resource, label: string, color: string) {
    this.symbol = symbol
    this.label = label
    this.color = color
  }
}

function getPermissionToolIcon(toolName: string): ToolIconInfo {
  switch (toolName) {
    case 'Edit':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), '编辑文件', Theme.WarningColor)
    case 'Write':
      return new ToolIconInfo($r('sys.symbol.doc_text'), '写入文件', Theme.AccentGreen)
    case 'Bash':
      return new ToolIconInfo($r('sys.symbol.gearshape'), '执行命令', Theme.AccentOrange)
    case 'Read':
      return new ToolIconInfo($r('sys.symbol.doc_text'), '读取文件', Theme.AccentBlue)
    case 'Glob':
      return new ToolIconInfo($r('sys.symbol.folder'), '搜索文件', Theme.AccentPurple)
    case 'Grep':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), '搜索内容', Theme.AccentPurple)
    default:
      return new ToolIconInfo($r('sys.symbol.lock_shield_fill'), toolName, Theme.AccentOrange)
  }
}

function getPermissionTitle(toolName: string, input?: Record<string, Object>): string {
  const obj = input || {}
  const filePath = obj['file_path'] as string || ''
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
      return `权限请求: ${toolName}`
  }
}

@Component
export struct PermissionApprovalCard {
  // 审批消息
  @Prop message: Message
  // 紧凑模式（用于浮动快速审批栏）
  @Prop compact: boolean = false
  // 强调高亮（有新权限请求待审批时脉冲提示）
  @Prop highlighted: boolean = false

  // 回调
  onApprove: (message: Message) => void = () => {}
  onAlwaysApprove: (message: Message) => void = () => {}
  onReject: (message: Message) => void = () => {}

  // 内部状态
  @State approveButtonScale: number = 1.0
  @State rejectButtonScale: number = 1.0
  @State highlightPulse: number = 0

  private toolIconInfo: ToolIconInfo = new ToolIconInfo($r('sys.symbol.lock_shield_fill'), '', Theme.AccentOrange)

  aboutToAppear(): void {
    this.toolIconInfo = getPermissionToolIcon(this.message.toolName || '')
  }

  build() {
    Column({ space: this.compact ? 8 : 12 }) {
      // Header
      Row({ space: 8 }) {
        SymbolGlyph(this.toolIconInfo.symbol)
          .fontSize(this.compact ? 16 : 20)
          .fontColor([this.toolIconInfo.color])

        Text(getPermissionTitle(this.message.toolName || '', this.message.toolInput))
          .fontSize(this.compact ? Theme.FontCaption : Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)

        if (this.message.isPermissionHandled) {
          Text(this.message.permissionResult ? '已允许' : '已拒绝')
            .fontSize(Theme.FontTiny)
            .fontColor(this.message.permissionResult ? Theme.SuccessColor : Theme.ErrorColor)
            .backgroundColor(this.message.permissionResult ? 'rgba(52,199,89,0.15)' : 'rgba(255,69,58,0.15)')
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else if (this.highlighted) {
          // 未处理 + 高亮：脉冲指示器
          Circle()
            .width(8)
            .height(8)
            .fill(Theme.AccentOrange)
            .opacity(0.6 + this.highlightPulse * 0.4)
        }
      }

      // 描述
      if (this.message.permissionDescription && !this.compact) {
        Text(this.message.permissionDescription)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      // Diff 预览（Edit/Write 工具）
      if (!this.compact &&
        (this.message.toolName === 'Edit' || this.message.toolName === 'Write') &&
        this.message.toolInput) {
        PermissionDiffPreview({
          toolName: this.message.toolName || '',
          input: this.message.toolInput as Record<string, Object>
        })
      }

      // Bash 命令预览
      if (this.message.toolName === 'Bash' && this.message.toolInput) {
        const command = (this.message.toolInput as Record<string, Object>)['command']
        if (command) {
          Row() {
            Text('$ ')
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.AccentGreen)
            Text(command as string)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(8)
          .backgroundColor(Theme.BackgroundTertiary)
          .borderRadius(8)
        }
      }

      // 操作按钮
      if (!this.message.isPermissionHandled) {
        this.ActionButtons()
      }
    }
    .width('100%')
    .padding(this.compact ? 12 : Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
    .border({
      width: 1,
      color: this.message.isPermissionHandled
        ? Theme.GlassBorder
        : (this.highlighted ? Theme.AccentOrange : Theme.AccentOrange)
    })
    .opacity(this.message.isPermissionHandled ? 0.7 : 1.0)
    .animation({ duration: 200, curve: Curve.EaseInOut })
  }

  @Builder
  ActionButtons() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // 允许按钮
        Button('允许')
          .fontSize(this.compact ? Theme.FontTiny : Theme.FontCaption)
          .fontColor(Theme.TextOnPrimary)
          .backgroundColor(Theme.PrimaryColor)
          .borderRadius(8)
          .layoutWeight(1)
          .scale({ x: this.approveButtonScale, y: this.approveButtonScale })
          .onClick(() => {
            hapticFeedback.submit()
            animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
              this.approveButtonScale = 0.92
            })
            setTimeout(() => {
              animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
                this.approveButtonScale = 1.0
              })
            }, 80)
            this.onApprove(this.message)
          })

        // 始终允许按钮
        Button('始终允许')
          .fontSize(this.compact ? Theme.FontTiny : Theme.FontCaption)
          .fontColor(Theme.PrimaryColor)
          .backgroundColor('rgba(0,122,255,0.15)')
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            hapticFeedback.submit()
            this.onAlwaysApprove(this.message)
          })
      }
      .width('100%')

      // 拒绝按钮
      Button('拒绝')
        .fontSize(this.compact ? Theme.FontTiny : Theme.FontCaption)
        .fontColor(Theme.TextSecondary)
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(8)
        .width('100%')
        .scale({ x: this.rejectButtonScale, y: this.rejectButtonScale })
        .onClick(() => {
          hapticFeedback.tap()
          animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
            this.rejectButtonScale = 0.92
          })
          setTimeout(() => {
            animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
              this.rejectButtonScale = 1.0
            })
          }, 80)
          this.onReject(this.message)
        })
    }
  }
}
