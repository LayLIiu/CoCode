/**
 * EnhancedMessageBubbles - 增强版消息气泡
 * 用户/AI消息差异化显示，渐变边框，状态图标等视觉优化
 */

import { Theme } from '../common/Theme'
import { Message } from '../models/Models'
import { MarkdownRenderer } from './MarkdownRenderer'

// ─────────────────────────────────────────────────────────────
// 渐变边框容器
// ─────────────────────────────────────────────────────────────

@Component
export struct GradientBorderContainer {
  @Prop borderColor1: string = 'rgba(10, 132, 255, 0.5)'
  @Prop borderColor2: string = 'rgba(175, 82, 222, 0.3)'
  @Prop gradientBackgroundColor: string = '#0E0E10'
  @Prop gradientBorderRadius: number = 18
  @Prop gradientBorderWidth: number = 1
  @BuilderParam content: () => void = () => {}

  build() {
    Stack() {
      // 渐变边框层
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.gradientBorderRadius)
        .linearGradient({
          angle: 135,
          colors: [[this.borderColor1, 0], [this.borderColor2, 1]]
        })

      // 内容层
      Column() {
        this.content()
      }
      .width('100%')
      .padding(this.gradientBorderWidth)
      .backgroundColor(this.gradientBackgroundColor)
      .borderRadius(this.gradientBorderRadius - 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 增强版用户消息气泡
// 特点：靠右对齐，蓝色渐变边框，深色背景
// ─────────────────────────────────────────────────────────────

@Component
export struct EnhancedUserBubble {
  @Prop message: Message
  @Link activeCopyMessageId: string
  onTranslate: (content: string) => void = () => {}
  onCopy: (text: string) => void = () => {}

  build() {
    Row() {
      Blank()
      Column() {
        GradientBorderContainer({
          borderColor1: 'rgba(10, 132, 255, 0.4)',
          borderColor2: 'rgba(48, 209, 88, 0.2)',
          gradientBackgroundColor: '#1E3A2F',
          gradientBorderRadius: 18,
          gradientBorderWidth: 1
        }) {
          Column({ space: 4 }) {
            // 消息内容
            Text(this.message.content)
              .fontSize(15)
              .fontColor(Theme.TextPrimary)
              .lineHeight(22)

            // 操作按钮
            if (this.activeCopyMessageId === this.message.id) {
              Row({ space: 6 }) {
                this.ActionButton(
                  $r('sys.symbol.doc_text'),
                  '复制',
                  Theme.TextPrimary,
                  () => {
                    this.onCopy(this.message.content)
                    this.activeCopyMessageId = ''
                  }
                )
                this.ActionButton(
                  $r('sys.symbol.character'),
                  '翻译',
                  Theme.AccentBlue,
                  () => {
                    this.activeCopyMessageId = ''
                    this.onTranslate(this.message.content)
                  }
                )
              }
              .margin({ top: 8 })
            }
          }
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
      }
      .gesture(
        LongPressGesture()
          .onAction(() => {
            if (this.activeCopyMessageId === this.message.id) {
              this.activeCopyMessageId = ''
            } else {
              this.activeCopyMessageId = this.message.id
            }
          })
      )
    }
    .width('100%')
  }

  @Builder ActionButton(icon: Resource, label: string, color: ResourceColor, action: () => void) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(11)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor(color)
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(12)
    .onClick(action)
  }
}

// ─────────────────────────────────────────────────────────────
// 增强版 AI 助手消息气泡
// 特点：靠左对齐，微妙渐变，代码块语法高亮
// ─────────────────────────────────────────────────────────────

@Component
export struct EnhancedAssistantBubble {
  @Prop message: Message
  @Link activeCopyMessageId: string
  onLinkClick: (url: string) => void = () => {}
  onTranslate: (content: string) => void = () => {}
  onCopy: (text: string) => void = () => {}

  private shouldHideContent(content: string): boolean {
    const trimmed = content.trim()
    if (!trimmed.startsWith('[{')) return false
    return trimmed.includes('"tool_use_id"') || trimmed.includes('"tool_result"')
  }

  build() {
    Row() {
      Column() {
        Column({ space: 4 }) {
          // AI 标识头
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.sparkles'))
              .fontSize(12)
              .fontColor([Theme.AccentPurple])
            Text('Claude')
              .fontSize(10)
              .fontColor(Theme.TextTertiary)
          }
          .width('100%')
          .padding({ bottom: 6 })

          // 消息内容
          if (!this.shouldHideContent(this.message.content)) {
            MarkdownRenderer({
              content: this.message.content,
              onLinkClick: this.onLinkClick
            })
          }

          // 操作按钮
          if (this.activeCopyMessageId === this.message.id) {
            Row({ space: 6 }) {
              this.ActionButton(
                $r('sys.symbol.doc_text'),
                '复制',
                Theme.TextPrimary,
                () => {
                  this.onCopy(this.message.content)
                  this.activeCopyMessageId = ''
                }
              )
              this.ActionButton(
                $r('sys.symbol.character'),
                '翻译',
                Theme.AccentBlue,
                () => {
                  this.activeCopyMessageId = ''
                  this.onTranslate(this.message.content)
                }
              )
            }
            .margin({ top: 8 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#0C0C0E')
        .borderRadius(18)
        .border({
          width: 0.5,
          color: 'rgba(255,255,255,0.08)'
        })
      }
      .gesture(
        LongPressGesture()
          .onAction(() => {
            if (this.activeCopyMessageId === this.message.id) {
              this.activeCopyMessageId = ''
            } else {
              this.activeCopyMessageId = this.message.id
            }
          })
      )

      Blank()
    }
    .width('100%')
  }

  @Builder ActionButton(icon: Resource, label: string, color: ResourceColor, action: () => void) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(11)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor(color)
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(12)
    .onClick(action)
  }
}

// ─────────────────────────────────────────────────────────────
// 增强版工具执行气泡
// 特点：左侧彩色状态条，展开/折叠动画
// ─────────────────────────────────────────────────────────────

@Component
export struct EnhancedToolBubble {
  @Prop message: Message
  @Prop toolName: string = ''
  @Prop toolStatus: string = 'pending'
  @Link expandedIds: Set<string>
  onToggle: (id: string) => void = () => {}

  private isExpanded(): boolean {
    return this.expandedIds.has(this.message.id)
  }

  private getStatusColor(): string {
    switch (this.toolStatus) {
      case 'running': return Theme.AccentBlue
      case 'completed': return Theme.SuccessColor
      case 'failed': return Theme.ErrorColor
      default: return Theme.TextTertiary
    }
  }

  private getStatusIcon(): Resource {
    switch (this.toolStatus) {
      case 'running': return $r('sys.symbol.arrow_clockwise')
      case 'completed': return $r('sys.symbol.checkmark_circle_fill')
      case 'failed': return $r('sys.symbol.xmark_circle_fill')
      default: return $r('sys.symbol.circle')
    }
  }

  private getToolIcon(): Resource {
    switch (this.toolName) {
      case 'Bash': return $r('sys.symbol.terminal')
      case 'Read': return $r('sys.symbol.doc_text')
      case 'Write': return $r('sys.symbol.square_and_pencil')
      case 'Edit': return $r('sys.symbol.pencil_circle')
      case 'Glob': return $r('sys.symbol.folder')
      case 'Grep': return $r('sys.symbol.magnifyingglass')
      default: return $r('sys.symbol.gearshape')
    }
  }

  build() {
    Row() {
      // 左侧状态条
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(this.getStatusColor())

      Column({ space: 0 }) {
        // 头部
        Row({ space: 10 }) {
          // 工具图标
          Column() {
            SymbolGlyph(this.getToolIcon())
              .fontSize(16)
              .fontColor([this.getStatusColor()])
          }
          .width(32)
          .height(32)
          .backgroundColor(this.getStatusColor() + '20')
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)

          // 工具信息
          Column({ space: 2 }) {
            Text(this.toolName || '工具')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TextPrimary)

            Text(this.getStatusText())
              .fontSize(11)
              .fontColor(this.getStatusColor())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 状态图标
          if (this.toolStatus === 'running') {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(this.getStatusColor())
          } else {
            SymbolGlyph(this.getStatusIcon())
              .fontSize(18)
              .fontColor([this.getStatusColor()])
          }

          // 展开箭头
          SymbolGlyph(this.isExpanded() ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([Theme.TextSecondary])
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })

        // 展开内容
        if (this.isExpanded()) {
          Divider()
            .color('rgba(255,255,255,0.08)')

          Column() {
            Text('展开内容...')
              .fontSize(12)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .padding(12)
        }
      }
      .layoutWeight(1)
      .backgroundColor('rgba(32, 33, 36, 0.95)')
      .borderRadius({ topRight: 12, bottomRight: 12 })
      .onClick(() => this.onToggle(this.message.id))
    }
    .width('100%')
    .backgroundColor('rgba(32, 33, 36, 0.5)')
    .borderRadius(14)
    .margin({ bottom: Theme.SpacingMD })
  }

  private getStatusText(): string {
    switch (this.toolStatus) {
      case 'running': return '执行中...'
      case 'completed': return '已完成'
      case 'failed': return '失败'
      default: return '等待执行'
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 状态徽章组件
// ─────────────────────────────────────────────────────────────

@Component
export struct StatusBadge {
  @Prop status: 'idle' | 'thinking' | 'streaming' | 'completed' | 'error' = 'idle'
  @Prop text: string = ''
  @Prop showIcon: boolean = true

  private getStatusConfig(): { color: string; bgColor: string; icon: Resource } {
    switch (this.status) {
      case 'thinking':
        return {
          color: Theme.AccentBlue,
          bgColor: 'rgba(10, 132, 255, 0.14)',
          icon: $r('sys.symbol.brain')
        }
      case 'streaming':
        return {
          color: Theme.AccentBlue,
          bgColor: 'rgba(10, 132, 255, 0.14)',
          icon: $r('sys.symbol.waveform')
        }
      case 'completed':
        return {
          color: Theme.SuccessColor,
          bgColor: 'rgba(48, 209, 88, 0.12)',
          icon: $r('sys.symbol.checkmark_circle_fill')
        }
      case 'error':
        return {
          color: Theme.ErrorColor,
          bgColor: 'rgba(255, 59, 48, 0.13)',
          icon: $r('sys.symbol.exclamationmark_triangle_fill')
        }
      default:
        return {
          color: Theme.TextTertiary,
          bgColor: 'rgba(255, 255, 255, 0.06)',
          icon: $r('sys.symbol.circle')
        }
    }
  }

  build() {
    Row({ space: 4 }) {
      if (this.showIcon) {
        if (this.status === 'thinking' || this.status === 'streaming') {
          LoadingProgress()
            .width(12)
            .height(12)
            .color(this.getStatusConfig().color)
        } else {
          SymbolGlyph(this.getStatusConfig().icon)
            .fontSize(12)
            .fontColor([this.getStatusConfig().color])
        }
      }

      Text(this.text || this.getStatusText())
        .fontSize(11)
        .fontColor(this.getStatusConfig().color)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.getStatusConfig().bgColor)
    .borderRadius(8)
  }

  private getStatusText(): string {
    switch (this.status) {
      case 'thinking': return '思考中'
      case 'streaming': return '输出中'
      case 'completed': return '已完成'
      case 'error': return '出错'
      default: return '空闲'
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 消息时间戳组件
// ─────────────────────────────────────────────────────────────

@Component
export struct MessageTimestamp {
  @Prop timestamp: string = ''
  @Prop alignRight: boolean = false

  private formatTime(isoString: string): string {
    try {
      const date = new Date(isoString)
      const hours = date.getHours().toString().padStart(2, '0')
      const minutes = date.getMinutes().toString().padStart(2, '0')
      return `${hours}:${minutes}`
    } catch (e) {
      return ''
    }
  }

  build() {
    Text(this.formatTime(this.timestamp))
      .fontSize(10)
      .fontColor(Theme.TextTertiary)
      .width('100%')
      .textAlign(this.alignRight ? TextAlign.End : TextAlign.Start)
      .margin({ top: 2 })
  }
}
