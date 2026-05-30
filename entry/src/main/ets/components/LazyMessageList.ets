/**
 * LazyMessageList - 虚拟化消息列表
 * 使用 LazyForEach 优化长对话性能
 */

import { Theme } from '../common/Theme'
import { Message } from '../models/Models'
import { UserBubble, AssistantBubble, ThinkingBubble, ToolUseBubble, ErrorBubble, SystemBubble, TaskSummaryBubble, StreamingThinkingBubble } from './MessageBubbles'

// ─────────────────────────────────────────────────────────────
// 数据源实现
// ─────────────────────────────────────────────────────────────

interface MessageDataSource {
  totalCount(): number
  getData(index: number): Message
  registerDataChangeListener(listener: DataChangeListener): void
  unregisterDataChangeListener(listener: DataChangeListener): void
}

interface DataChangeListener {
  onDataReloaded(): void
  onDataAdd(index: number): void
  onDataChange(index: number): void
  onDataDelete(index: number): void
  onDataMove(from: number, to: number): void
}

export class MessageListDataSource implements MessageDataSource {
  private messages: Message[] = []
  private listeners: DataChangeListener[] = []

  constructor(messages: Message[] = []) {
    this.messages = messages
  }

  totalCount(): number {
    return this.messages.length
  }

  getData(index: number): Message {
    return this.messages[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter(l => l !== listener)
  }

  // 更新消息列表
  updateMessages(messages: Message[]): void {
    this.messages = messages
    this.notifyReload()
  }

  // 添加消息
  addMessage(message: Message): void {
    this.messages.push(message)
    this.listeners.forEach(l => l.onDataAdd(this.messages.length - 1))
  }

  // 更新特定消息
  updateMessage(index: number, message: Message): void {
    if (index >= 0 && index < this.messages.length) {
      this.messages[index] = message
      this.listeners.forEach(l => l.onDataChange(index))
    }
  }

  private notifyReload(): void {
    this.listeners.forEach(l => l.onDataReloaded())
  }
}

// ─────────────────────────────────────────────────────────────
// 消息项渲染器
// ─────────────────────────────────────────────────────────────

class MessageItemGenerator {
  private activeCopyMessageId: string = ''
  private expandedThinkingIds: Set<string> = new Set()
  private expandedToolIds: Set<string> = new Set()
  private onCopy: (text: string) => void = () => {}
  private onTranslate: (content: string) => void = () => {}
  private onLinkClick: (url: string) => void = () => {}
  private onToggleThinking: (id: string) => void = () => {}
  private onToggleTool: (id: string) => void = () => {}
  private onFileTap: (src: string, alt: string, name: string) => void = () => {}

  setActiveCopyMessageId(id: string): void {
    this.activeCopyMessageId = id
  }

  setExpandedThinkingIds(ids: Set<string>): void {
    this.expandedThinkingIds = ids
  }

  setExpandedToolIds(ids: Set<string>): void {
    this.expandedToolIds = ids
  }

  setCallbacks(callbacks: {
    onCopy: (text: string) => void
    onTranslate: (content: string) => void
    onLinkClick: (url: string) => void
    onToggleThinking: (id: string) => void
    onToggleTool: (id: string) => void
    onFileTap: (src: string, alt: string, name: string) => void
  }): void {
    this.onCopy = callbacks.onCopy
    this.onTranslate = callbacks.onTranslate
    this.onLinkClick = callbacks.onLinkClick
    this.onToggleThinking = callbacks.onToggleThinking
    this.onToggleTool = callbacks.onToggleTool
    this.onFileTap = callbacks.onFileTap
  }

  generateItem(message: Message): void {
    // 根据消息类型渲染不同的气泡
    // 这里返回 void，实际渲染由 LazyForEach 的 itemGenerator 处理
  }
}

// ─────────────────────────────────────────────────────────────
// 虚拟化消息列表组件
// ─────────────────────────────────────────────────────────────

@Component
export struct LazyMessageList {
  @Prop messages: Message[] = []
  @Link activeCopyMessageId: string
  @Link expandedThinkingIds: Set<string>
  @Link expandedToolIds: Set<string>
  @Prop streamingThinking: string = ''
  @Prop isStreamingThinkingExpanded: boolean = false

  // 回调
  onCopy: (text: string) => void = () => {}
  onTranslate: (content: string) => void = () => {}
  onLinkClick: (url: string) => void = () => {}
  onToggleThinking: (id: string) => void = () => {}
  onToggleTool: (id: string) => void = () => {}
  onFileTap: (src: string, alt: string, name: string) => void = () => {}
  onScrollToBottom: () => void = () => {}

  private scroller: Scroller = new Scroller()
  private dataSource: MessageListDataSource = new MessageListDataSource()

  aboutToAppear(): void {
    this.dataSource.updateMessages(this.messages)
  }

  aboutToDisappear(): void {
    // 清理资源
  }

  // 更新消息
  updateMessages(messages: Message[]): void {
    this.dataSource.updateMessages(messages)
  }

  // 滚动到底部
  scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom)
  }

  build() {
    List({ scroller: this.scroller }) {
      // 流式思考气泡
      if (this.streamingThinking) {
        ListItem() {
          StreamingThinkingBubble({
            content: this.streamingThinking,
            isExpanded: this.isStreamingThinkingExpanded
          })
        }
      }

      // 消息列表
      LazyForEach(this.dataSource, (message: Message) => {
        ListItem() {
          this.MessageContainer(message)
        }
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }, (message: Message) => message.id)

      // 底部占位
      ListItem() {
        Column()
          .width('100%')
          .height(150)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onScrollIndex((start: number, end: number) => {
      // 滚动事件处理
    })
  }

  @Builder MessageContainer(message: Message) {
    Column() {
      Row() {
        if (message.type === 'user') {
          Blank().layoutWeight(1)
        }

        this.MessageContent(message)

        if (message.type !== 'user') {
          Blank().layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  @Builder MessageContent(message: Message) {
    if (message.type === 'user') {
      UserBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onTranslate: this.onTranslate,
        onCopy: this.onCopy
      })
    } else if (message.type === 'assistant') {
      AssistantBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onLinkClick: this.onLinkClick,
        onTranslate: this.onTranslate,
        onCopy: this.onCopy
      })
    } else if (message.type === 'thinking') {
      ThinkingBubble({
        message: message,
        expandedIds: this.expandedThinkingIds,
        onToggle: this.onToggleThinking
      })
    } else if (message.type === 'tool_use') {
      ToolUseBubble({
        message: message,
        expandedToolIds: this.expandedToolIds,
        onToggle: this.onToggleTool,
        onFileTap: this.onFileTap,
        onLinkClick: this.onLinkClick
      })
    } else if (message.type === 'error') {
      ErrorBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onCopy: this.onCopy
      })
    } else if (message.type === 'system_notification' || message.type === 'system') {
      SystemBubble({ message: message })
    } else if (message.type === 'task_list') {
      TaskSummaryBubble({ message: message })
    } else {
      // 默认渲染
      Text(message.content || '')
        .fontSize(14)
        .fontColor(Theme.TextSecondary)
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 带分页加载的虚拟列表
// ─────────────────────────────────────────────────────────────

@Component
export struct PagedLazyMessageList {
  @Prop allMessages: Message[] = []
  @Prop displayedCount: number = 50
  @Link activeCopyMessageId: string
  @Link expandedThinkingIds: Set<string>
  @Link expandedToolIds: Set<string>

  @State isLoadingMore: boolean = false

  // 回调
  onLoadMore: () => void = () => {}
  onCopy: (text: string) => void = () => {}
  onTranslate: (content: string) => void = () => {}
  onLinkClick: (url: string) => void = () => {}
  onToggleThinking: (id: string) => void = () => {}
  onToggleTool: (id: string) => void = () => {}

  private scroller: Scroller = new Scroller()

  private getVisibleMessages(): Message[] {
    if (this.allMessages.length <= this.displayedCount) {
      return this.allMessages
    }
    return this.allMessages.slice(this.allMessages.length - this.displayedCount)
  }

  private hasMoreMessages(): boolean {
    return this.allMessages.length > this.displayedCount
  }

  build() {
    List({ scroller: this.scroller }) {
      // 加载更多提示
      if (this.hasMoreMessages()) {
        ListItem() {
          Row({ space: 8 }) {
            if (this.isLoadingMore) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(Theme.TextSecondary)
            }
            Text('上滑加载更早消息')
              .fontSize(12)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 16, bottom: 8 })
        }
      }

      // 消息列表
      ForEach(this.getVisibleMessages(), (message: Message) => {
        ListItem() {
          this.MessageContainer(message)
        }
      }, (message: Message) => message.id)

      // 底部占位
      ListItem() {
        Column()
          .width('100%')
          .height(150)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onScrollIndex((start: number, end: number) => {
      // 滚动到顶部时加载更多
      if (start <= 2 && this.hasMoreMessages() && !this.isLoadingMore) {
        this.isLoadingMore = true
        this.onLoadMore()
        setTimeout(() => {
          this.isLoadingMore = false
        }, 300)
      }
    })
  }

  @Builder MessageContainer(message: Message) {
    Column() {
      Row() {
        if (message.type === 'user') {
          Blank().layoutWeight(1)
        }

        this.MessageContent(message)

        if (message.type !== 'user') {
          Blank().layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  @Builder MessageContent(message: Message) {
    if (message.type === 'user') {
      UserBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onTranslate: this.onTranslate,
        onCopy: this.onCopy
      })
    } else if (message.type === 'assistant') {
      AssistantBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onLinkClick: this.onLinkClick,
        onTranslate: this.onTranslate,
        onCopy: this.onCopy
      })
    } else if (message.type === 'thinking') {
      ThinkingBubble({
        message: message,
        expandedIds: this.expandedThinkingIds,
        onToggle: this.onToggleThinking
      })
    } else if (message.type === 'tool_use') {
      ToolUseBubble({
        message: message,
        expandedToolIds: this.expandedToolIds,
        onToggle: this.onToggleTool
      })
    } else if (message.type === 'error') {
      ErrorBubble({
        message: message,
        activeCopyMessageId: this.activeCopyMessageId,
        onCopy: this.onCopy
      })
    } else if (message.type === 'system_notification' || message.type === 'system') {
      SystemBubble({ message: message })
    } else if (message.type === 'task_list') {
      TaskSummaryBubble({ message: message })
    }
  }

  scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom)
  }
}

// ─────────────────────────────────────────────────────────────
// 导出便捷方法
// ─────────────────────────────────────────────────────────────

export function createMessageDataSource(messages: Message[]): MessageListDataSource {
  return new MessageListDataSource(messages)
}
