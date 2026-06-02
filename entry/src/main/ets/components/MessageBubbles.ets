/**
 * MessageBubbles - 消息气泡组件集合
 * 从 ChatDetailPage 提取的消息渲染组件
 */

import { Theme } from '../common/Theme'
import { Message, MessageImage, TaskItem } from '../models/Models'
import { MarkdownRenderer } from './MarkdownRenderer'
import { FileAttachmentBubble } from './FileAttachmentBubble'
import { getToolIcon, ToolIconInfo } from '../viewmodel/ChatDetailViewModel'

// ─────────────────────────────────────────────────────────────
// 用户消息气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct UserBubble {
  @Prop message: Message
  @Link activeCopyMessageId: string
  onTranslate: (content: string) => void = () => {}
  onCopy: (text: string) => void = () => {}

  build() {
    Column({ space: 4 }) {
      Text(this.message.content)
        .fontSize(15)
        .fontColor(Theme.TextPrimary)
        .lineHeight(22)

      if (this.activeCopyMessageId === this.message.id) {
        Row({ space: 4 }) {
          this.CopyButton()
          this.TranslateButton()
        }
      }
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('#3A3A3C')
    .borderRadius(18)
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

  @Builder CopyButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(11)
        .fontColor([Theme.TextPrimary])
      Text('复制')
        .fontSize(11)
        .fontColor(Theme.TextPrimary)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(10)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .onClick(() => {
      this.onCopy(this.message.content)
      this.activeCopyMessageId = ''
    })
  }

  @Builder TranslateButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.character'))
        .fontSize(11)
        .fontColor([Theme.AccentBlue])
      Text('翻译')
        .fontSize(11)
        .fontColor(Theme.AccentBlue)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(10)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .onClick(() => {
      this.activeCopyMessageId = ''
      this.onTranslate(this.message.content)
    })
  }
}

// ─────────────────────────────────────────────────────────────
// AI 助手消息气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct AssistantBubble {
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
    Column({ space: 4 }) {
      if (!this.shouldHideContent(this.message.content)) {
        MarkdownRenderer({
          content: this.message.content,
          onLinkClick: this.onLinkClick
        })
      }

      if (this.activeCopyMessageId === this.message.id) {
        Row({ space: 4 }) {
          this.CopyButton()
          this.TranslateButton()
        }
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor('#2C2C2E')
    .borderRadius(18)
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

  @Builder CopyButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(11)
        .fontColor([Theme.TextPrimary])
      Text('复制')
        .fontSize(11)
        .fontColor(Theme.TextPrimary)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(10)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .onClick(() => {
      this.onCopy(this.message.content)
      this.activeCopyMessageId = ''
    })
  }

  @Builder TranslateButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.character'))
        .fontSize(11)
        .fontColor([Theme.AccentBlue])
      Text('翻译')
        .fontSize(11)
        .fontColor(Theme.AccentBlue)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(Theme.GlassBackground)
    .borderRadius(10)
    .border({ width: 0.5, color: Theme.GlassBorder })
    .onClick(() => {
      this.activeCopyMessageId = ''
      this.onTranslate(this.message.content)
    })
  }
}

// ─────────────────────────────────────────────────────────────
// 思考消息气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct ThinkingBubble {
  @Prop message: Message
  @Link expandedIds: Set<string>
  onToggle: (id: string) => void = () => {}

  private isExpanded(): boolean {
    return this.expandedIds.has(this.message.id)
  }

  private getThinkingSummary(content: string): string {
    const lines = content.split('\n')
    let firstLine = ''
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim()
      if (trimmed) {
        firstLine = trimmed
        break
      }
    }
    return firstLine.length > 60 ? firstLine.substring(0, 60) + '...' : firstLine
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(12)
          .fontColor([Theme.AccentOrange])

        Text('thinking')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        if (!this.isExpanded() && this.message.content) {
          Text(this.getThinkingSummary(this.message.content))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        SymbolGlyph(this.isExpanded() ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(9)
          .fontColor([Theme.TextTertiary])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      if (this.isExpanded() && this.message.content) {
        Scroll() {
          Text(this.message.content)
            .fontSize(11)
            .fontColor(Theme.TextSecondary)
            .fontFamily('monospace')
            .width('100%')
        }
        .height(Math.max(100, Math.min(400, this.message.content.split('\n').length * 22)))
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .onClick(() => this.onToggle(this.message.id))
    .backgroundColor('#2C2C2E')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
  }
}

// ─────────────────────────────────────────────────────────────
// 流式思考气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct StreamingThinkingBubble {
  @Prop content: string
  @Link isExpanded: boolean
  scroller: Scroller = new Scroller()

  build() {
    Row() {
      Column({ space: 0 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(12)
            .fontColor([Theme.AccentOrange])

          Text('thinking...')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TextSecondary)

          Blank()

          SymbolGlyph(this.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(9)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: this.isExpanded ? 6 : 10 })
        .onClick(() => { this.isExpanded = !this.isExpanded })

        if (this.isExpanded) {
          Scroll(this.scroller) {
            Text(this.content)
              .fontSize(11)
              .fontColor(Theme.TextSecondary)
              .fontFamily('monospace')
              .width('100%')
          }
          .height(Math.max(60, Math.min(200, this.content.split('\n').length * 20)))
          .scrollBar(BarState.Off)
          .padding({ left: 12, right: 12, bottom: 10 })
        }
      }
      .width('100%')
      .backgroundColor('#2C2C2E')
      .borderRadius(10)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
    }
    .width('100%')
  }
}

// ─────────────────────────────────────────────────────────────
// 工具使用气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct ToolUseBubble {
  @Prop message: Message
  @Link expandedToolIds: Set<string>
  onToggle: (id: string) => void = () => {}
  onFileTap: (src: string, alt: string, name: string) => void = () => {}
  onLinkClick: (url: string) => void = () => {}

  private isExpanded(): boolean {
    return this.expandedToolIds.has(this.message.id)
  }

  private isExpandable(): boolean {
    return this.isToolExpandable(this.message.toolName) ||
      (this.message.toolResult !== undefined && this.message.toolResult.length > 0)
  }

  private isToolExpandable(toolName?: string): boolean {
    return toolName === 'Bash' || toolName === 'Read' || toolName === 'Edit' || toolName === 'Write'
  }

  private getToolDisplayName(toolName?: string): string {
    switch (toolName) {
      case 'Bash': return '命令'
      case 'Read': return '读取'
      case 'Write': return '写入'
      case 'Edit': return '编辑'
      case 'Grep': return '搜索'
      case 'Glob': return '查找'
      case 'WebFetch': return '网页'
      case 'Agent': return '代理'
      default: return toolName || '工具'
    }
  }

  private getToolInputSummary(toolName: string, input: Record<string, Object>): string {
    if (toolName === 'Bash') {
      const cmd = input['command']
      if (typeof cmd === 'string') {
        return cmd.length > 120 ? cmd.substring(0, 72) + '...' : cmd
      }
    } else if (toolName === 'Read' || toolName === 'Write' || toolName === 'Edit') {
      const filePath = input['file_path']
      if (typeof filePath === 'string') {
        const parts = filePath.split('/')
        if (parts.length > 0) {
          return parts[parts.length - 1]
        }
        return filePath
      }
    } else if (toolName === 'Glob' || toolName === 'Grep') {
      const pattern = input['pattern']
      if (typeof pattern === 'string') {
        return pattern
      }
    }
    return ''
  }

  private getBashCommand(): string {
    if (!this.message.toolInput) return ''
    const cmd = this.message.toolInput['command']
    return typeof cmd === 'string' ? cmd : ''
  }

  private getToolFilePath(): string {
    if (!this.message.toolInput) return ''
    const fp = this.message.toolInput['file_path']
    return typeof fp === 'string' ? fp : ''
  }

  private truncateToolResult(): string {
    if (!this.message.toolResult) return ''
    return this.message.toolResult.length > 2000
      ? this.message.toolResult.substring(0, 2000) + '...'
      : this.message.toolResult
  }

  private getToolStatusText(status?: string): string {
    switch (status) {
      case 'running': return '运行中'
      case 'completed': return '完成'
      case 'failed': return '失败'
      case 'pending': return '等待'
      default: return '等待'
    }
  }

  private getToolStatusColor(status?: string): string {
    switch (status) {
      case 'running': return Theme.AccentBlue
      case 'completed': return Theme.SuccessColor
      case 'failed': return Theme.ErrorColor
      default: return Theme.TextTertiary
    }
  }

  private getToolStatusBgColor(status?: string): string {
    switch (status) {
      case 'running': return 'rgba(10, 132, 255, 0.14)'
      case 'completed': return 'rgba(48, 209, 88, 0.12)'
      case 'failed': return 'rgba(255, 59, 48, 0.13)'
      default: return 'rgba(255, 255, 255, 0.06)'
    }
  }

  private getToolResultLineCount(): string {
    if (!this.message.toolResult || this.message.toolStatus !== 'completed') return ''
    const lines = this.message.toolResult.split('\n').length
    if (lines <= 1) return ''
    return lines + ' 行输出'
  }

  private getDiffStatText(): string {
    const diff = this.message.toolResult || ''
    if (diff.length === 0) return ''
    const lines = diff.split('\n')
    let added = 0
    let removed = 0
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (line.startsWith('+++') || line.startsWith('---')) continue
      if (line.startsWith('+')) added++
      if (line.startsWith('-')) removed++
    }
    if (added === 0 && removed === 0) return ''
    return '+' + added + ' / -' + removed
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        SymbolGlyph(getToolIcon(this.message.toolName || 'Tool').symbol)
          .fontSize(16)
          .fontColor([getToolIcon(this.message.toolName || 'Tool').color])

        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text(this.getToolDisplayName(this.message.toolName))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TextPrimary)

            Text(this.getToolStatusText(this.message.toolStatus))
              .fontSize(9)
              .fontColor(this.getToolStatusColor(this.message.toolStatus))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.getToolStatusBgColor(this.message.toolStatus))
              .borderRadius(5)
          }

          if (this.getToolInputSummary(this.message.toolName || '', this.message.toolInput || {})) {
            Text(this.getToolInputSummary(this.message.toolName || '', this.message.toolInput || {}))
              .fontSize(11)
              .fontColor(Theme.TextTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.getToolResultLineCount()) {
          Text(this.getToolResultLineCount())
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }

        if (this.getDiffStatText()) {
          Text(this.getDiffStatText())
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(Theme.AccentGreen)
        }

        this.ToolStatusIcon()

        if (this.isExpandable()) {
          SymbolGlyph(this.isExpanded() ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(10)
            .fontColor([Theme.TextSecondary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      if (this.isExpanded() && this.isExpandable()) {
        Divider()
          .color('rgba(255,255,255,0.1)')
          .width('100%')

        Column({ space: 8 }) {
          if (this.message.toolName === 'Bash' && this.getBashCommand()) {
            Column({ space: 4 }) {
              Text('COMMAND')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)
              Text('$ ' + this.getBashCommand())
                .fontSize(11)
                .fontColor(Theme.TextPrimary)
                .fontFamily('monospace')
                .width('100%')
                .padding(10)
                .borderRadius(6)
                .backgroundColor('#1C1C1E')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          if ((this.message.toolName === 'Write' || this.message.toolName === 'Edit') &&
            this.getToolFilePath() && this.message.toolStatus === 'completed') {
            FileAttachmentBubble({
              filePath: this.getToolFilePath(),
              onImageTap: this.onFileTap
            })
          }

          if (this.message.toolResult) {
            Column({ space: 4 }) {
              Text(this.message.toolName === 'Edit' || this.message.toolName === 'Write' ? 'DIFF / OUTPUT' : 'OUTPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              if (this.message.images && this.message.images.length > 0) {
                ForEach(this.message.images, (img: MessageImage, idx: number) => {
                  Image('data:' + img.mediaType + ';base64,' + img.data)
                    .width('100%')
                    .constraintSize({ maxHeight: 300 })
                    .objectFit(ImageFit.Contain)
                    .borderRadius(8)
                })
              }

              MarkdownRenderer({
                content: this.truncateToolResult(),
                onLinkClick: this.onLinkClick
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .backgroundColor('rgba(32, 33, 36, 0.92)')
    .borderRadius(10)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
    .onClick(() => {
      if (this.isExpandable()) {
        this.onToggle(this.message.id)
      }
    })
  }

  @Builder ToolStatusIcon() {
    if (this.message.toolStatus === 'running') {
      LoadingProgress()
        .width(14)
        .height(14)
        .color(Theme.AccentBlue)
    } else if (this.message.toolStatus === 'completed') {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(14)
        .fontColor([Theme.SuccessColor])
    } else if (this.message.toolStatus === 'failed') {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(14)
        .fontColor([Theme.ErrorColor])
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 错误消息气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct ErrorBubble {
  @Prop message: Message
  @Link activeCopyMessageId: string
  onCopy: (text: string) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(16)
          .fontColor([Theme.ErrorColor])
        Text('错误')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.ErrorColor)
      }

      if (this.message.content) {
        Text(this.message.content)
          .fontSize(13)
          .fontColor(Theme.TextSecondary)
      }

      if (this.activeCopyMessageId === this.message.id) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(12)
            .fontColor([Theme.TextPrimary])
          Text('复制')
            .fontSize(11)
            .fontColor(Theme.TextPrimary)
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(Theme.GlassBackground)
        .borderRadius(12)
        .border({ width: 0.5, color: Theme.GlassBorder })
        .onClick(() => {
          this.onCopy(this.message.content)
          this.activeCopyMessageId = ''
        })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Theme.ErrorColor + '20')
    .borderRadius(10)
    .border({ width: 0.5, color: Theme.ErrorColor + '40' })
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
}

// ─────────────────────────────────────────────────────────────
// 系统消息气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct SystemBubble {
  @Prop message: Message

  build() {
    Row() {
      Text(this.message.content || '系统消息')
        .fontSize(12)
        .fontColor(Theme.TextTertiary)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }
}

// ─────────────────────────────────────────────────────────────
// 任务列表气泡
// ─────────────────────────────────────────────────────────────

@Component
export struct TaskSummaryBubble {
  @Prop message: Message

  build() {
    if (this.message.tasks && this.message.tasks.length > 0) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.AccentBlue])
          Text('任务')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
        }

        Column({ space: 4 }) {
          ForEach(this.message.tasks, (task: TaskItem, ti: number) => {
            Row({ space: 6 }) {
              if (task.status === 'completed') {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(12)
                  .fontColor([Theme.SuccessColor])
              } else if (task.status === 'in_progress') {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(12)
                  .fontColor([Theme.AccentBlue])
              } else if (task.status === 'failed') {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(12)
                  .fontColor([Theme.ErrorColor])
              } else {
                SymbolGlyph($r('sys.symbol.circle'))
                  .fontSize(12)
                  .fontColor([Theme.TextTertiary])
              }

              Text(task.content)
                .fontSize(12)
                .fontColor(task.status === 'completed' ? Theme.TextTertiary : Theme.TextPrimary)
                .decoration(task.status === 'completed' ? { type: TextDecorationType.LineThrough } : undefined)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (task: TaskItem, ti: number) => `tsk-${ti}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF18')
      .borderRadius(10)
    }
  }
}
