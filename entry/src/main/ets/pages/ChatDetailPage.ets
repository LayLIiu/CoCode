/**
 * 对话详情页 - 实时消息收发
 * 与 iOS 端完全一致的聊天体验
 */

import { Theme } from '../common/Theme'
import { Message, SessionStatus, ModelInfo, WSMessage, TaskItem, TaskStatus } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { sessionStore } from '../stores/SessionStore'
import { apiService } from '../services/APIService'
import { MarkdownRenderer } from '../components/MarkdownRenderer'
import { PixelMascot, MascotStatus, getMascotColorForSession } from '../components/PixelMascot'
import router from '@ohos.router'
import pasteboard from '@ohos.pasteboard'

// 斜杠命令定义
class SlashCommand {
  name: string = ''
  description: string = ''
  example: string = ''
}

// 工具图标映射（与 iOS 端一致）
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

function getToolIcon(toolName: string): ToolIconInfo {
  switch (toolName) {
    case 'Bash':
      return new ToolIconInfo($r('sys.symbol.gearshape'), 'Terminal', Theme.AccentGreen)
    case 'Read':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Read file', Theme.AccentBlue)
    case 'Write':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Write file', Theme.AccentOrange)
    case 'Edit':
      return new ToolIconInfo($r('sys.symbol.square_and_pencil'), 'Edit file', Theme.WarningColor)
    case 'Glob':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search files', Theme.AccentPurple)
    case 'Grep':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Search content', Theme.AccentPurple)
    case 'Agent':
      return new ToolIconInfo($r('sys.symbol.person_fill'), 'Agent', Theme.AccentBlue)
    case 'WebSearch':
      return new ToolIconInfo($r('sys.symbol.magnifyingglass'), 'Web search', Theme.AccentBlue)
    case 'WebFetch':
      return new ToolIconInfo($r('sys.symbol.doc_text'), 'Web fetch', Theme.AccentBlue)
    case 'Skill':
      return new ToolIconInfo($r('sys.symbol.star_fill'), 'Skill', Theme.WarningColor)
    default:
      return new ToolIconInfo($r('sys.symbol.gearshape'), toolName, Theme.TextSecondary)
  }
}

@Entry
@Component
struct ChatDetailPage {
  @State messages: Message[] = []
  @State inputText: string = ''
  @State conversationTitle: string = '对话'
  @State sessionId: string = ''
  @State chatStatus: SessionStatus = 'idle'
  @State showMenu: boolean = false
  @State showModelSelector: boolean = false
  @State showSlashCommands: boolean = false
  @State models: ModelInfo[] = []
  @State currentModel: string = ''
  @State isLoadingModels: boolean = false
  @State expandedThinkingIds: Set<string> = new Set()
  @State expandedToolIds: Set<string> = new Set()
  @State showCopyToast: boolean = false
  @State copyToastText: string = ''
  @State showCustomInput: boolean = false
  @State customInputText: string = ''
  @State activeQuestionMessageId: string = ''

  // 流式文本本地缓冲（与 iOS 端一致）
  @State streamingText: string = ''
  @State streamingThinking: string = ''
  private inTextBlock: boolean = false
  private inThinkingBlock: boolean = false

  // 消息去重
  private recentlySentMessages: Set<string> = new Set()

  // 复制按钮
  @State activeCopyMessageId: string = ''

  // thinking 自动展开/合上（与 iOS 一致：最新 thinking 自动展开，新工具/内容出现后自动合上）
  private latestThinkingId: string = ''

  // 强制重绘计数器（ArkTS @State 不追踪嵌套对象属性变更）
  @State messageUpdateCounter: number = 0

  // "最新消息"浮动按钮
  @State showNewMessageButton: boolean = false
  @State userIsViewingHistory: boolean = false

  // 输入栏收缩动画
  @State animationProgress: number = 0

  // Token 使用量
  @State tokenUsage: number = 0
  @State contextUsage: number = 0

  // 工作中计时（与 iOS StreamingStatusView 一致）
  @State elapsedSeconds: number = 0
  @State mascotScale: number = 1.0
  private workTimer: number = -1

  // 分页加载
  @State displayedMessageCount: number = 50
  @State isLoadingMore: boolean = false

  // 标题栏动态模糊（滚动时背景渐变透明）
  @State scrollOffset: number = 0
  private readonly blurThreshold: number = 30

  private scroller: Scroller = new Scroller()

  // 斜杠命令列表
  private slashCommands: SlashCommand[] = [
    { name: '/compact', description: '压缩对话上下文', example: '/compact' },
    { name: '/cost', description: '显示token使用量', example: '/cost' },
    { name: '/clear', description: '清除当前对话', example: '/clear' },
    { name: '/config', description: '查看当前配置', example: '/config' },
    { name: '/doctor', description: '诊断问题', example: '/doctor' },
    { name: '/init', description: '初始化CLAUDE.md', example: '/init' },
    { name: '/permissions', description: '权限设置', example: '/permissions' },
    { name: '/pr-comments', description: 'PR评论', example: '/pr-comments' },
    { name: '/release', description: '发布相关', example: '/release' },
    { name: '/review', description: '代码审查', example: '/review' },
    { name: '/terminal-setup', description: '终端设置', example: '/terminal-setup' },
    { name: '/vim', description: 'Vim模式', example: '/vim' }
  ]

  aboutToAppear(): void {
    this.getRouterParams()
    this.loadMessages()
    this.setupCallbacks()
  }

  aboutToDisappear(): void {
    this.stopWorkTimer()
    sessionStore.setCurrentSession(null)
  }

  private getRouterParams(): void {
    const params = router.getParams() as Record<string, string>
    if (params) {
      if (params['sessionId']) {
        this.sessionId = params['sessionId'] as string
        sessionStore.setCurrentSession(this.sessionId)
      }
      if (params['title']) {
        this.conversationTitle = params['title'] as string
      }
    }
  }

  private async loadMessages(): Promise<void> {
    await sessionStore.loadMessages(this.sessionId)
    const msgs = sessionStore.messages.get(this.sessionId)
    if (msgs) {
      this.messages = msgs
    }
    this.scrollToBottom()
  }

  private setupCallbacks(): void {
    sessionStore.onMessagesChanged = (sid: string) => {
      if (sid === this.sessionId) {
        const msgs = sessionStore.messages.get(this.sessionId)
        if (msgs) {
          this.messages = msgs
        }
        // 查看历史时不强制滚动，避免打断用户
        if (!this.userIsViewingHistory) {
          this.scrollToBottom()
        }
      }
    }

    sessionStore.onStatusChanged = (sid: string, status: SessionStatus) => {
      if (sid === this.sessionId) {
        this.chatStatus = status
      }
    }

    sessionStore.onRawMessage = (sid: string, msg: WSMessage) => {
      if (sid === this.sessionId) {
        this.handleStreamingMessage(msg)
      }
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  // 标题栏动态模糊：根据滚动位置计算背景透明度
  private getTitleBarBackgroundColor(): string {
    const progress = Math.min(this.scrollOffset / this.blurThreshold, 1.0)
    const alpha = 1.0 - progress * 0.3
    return `rgba(18, 18, 18, ${alpha})`
  }

  // 标题栏动态模糊：根据滚动位置返回模糊样式
  private getTitleBarBlurStyle(): BlurStyle {
    return this.scrollOffset > this.blurThreshold ? BlurStyle.COMPONENT_THICK : BlurStyle.COMPONENT_REGULAR
  }

  // 加载模型列表
  private async loadModels(): Promise<void> {
    if (this.models.length > 0) return

    this.isLoadingModels = true
    try {
      const response = await apiService.getModels()
      this.models = response.models || []
      const current = await apiService.getCurrentModel()
      this.currentModel = current.id
    } catch (e) {
      console.error(`[ChatDetailPage] Load models error: ${e}`)
    }
    this.isLoadingModels = false
  }

  // 选择模型
  private async selectModel(modelId: string): Promise<void> {
    try {
      await apiService.setCurrentModel(modelId)
      this.currentModel = modelId
      this.showModelSelector = false
      this.showMenu = false
    } catch (e) {
      console.error(`[ChatDetailPage] Set model error: ${e}`)
    }
  }

  // 选择斜杠命令
  private selectSlashCommand(cmd: string): void {
    this.inputText = cmd + ' '
    this.showSlashCommands = false
    this.showMenu = false
  }

  // 获取工具输入摘要
  private getToolInputSummary(toolName: string, input: Record<string, Object>): string {
    if (toolName === 'Bash') {
      const cmd = input['command']
      if (typeof cmd === 'string') {
        return cmd.length > 50 ? cmd.substring(0, 50) + '...' : cmd
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

  // MARK: - 剪贴板

  private copyToClipboard(text: string): void {
    this.copyToastText = '已复制'
    this.showCopyToast = true
    setTimeout(() => {
      this.showCopyToast = false
    }, 1500)

    try {
      const systemPasteboard = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      systemPasteboard.setData(pasteData)
    } catch (e) {
      console.error(`[ChatDetailPage] pasteboard error: ${e}`)
    }
  }

  // MARK: - 流式消息处理（本地 buffering，与 iOS 一致）

  private handleStreamingMessage(msg: WSMessage): void {
    switch (msg.type) {
      case 'content_start':
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.chatStatus = 'streaming'
          this.startWorkTimer()
        }
        if (msg.blockType === 'text') {
          this.inTextBlock = true
          this.streamingText = ''
        }
        break

      case 'content_delta':
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.chatStatus = 'streaming'
          this.startWorkTimer()
        }
        if (msg.text) {
          this.streamingText += msg.text
          // 流式文本实时滚动
          if (!this.userIsViewingHistory) {
            this.scrollToBottom()
          }
        }
        break

      case 'thinking':
        if (this.chatStatus === 'idle' || this.chatStatus === 'completed') {
          this.chatStatus = 'thinking'
          this.startWorkTimer()
        }
        if (!this.inThinkingBlock) {
          this.inThinkingBlock = true
          this.streamingThinking = ''
        }
        if (msg.text) {
          this.streamingThinking += msg.text
          if (!this.userIsViewingHistory) {
            this.scrollToBottom()
          }
        }
        break

      case 'tool_use_complete':
        this.flushStreamingBuffers()
        this.inTextBlock = false
        this.inThinkingBlock = false
        this.chatStatus = 'tool_executing'
        // 新工具出现 → 合上最新 thinking（与 iOS 一致）
        this.collapseLatestThinking()
        break

      case 'tool_result':
        break

      case 'message_complete':
        this.flushStreamingBuffers()
        this.inTextBlock = false
        this.inThinkingBlock = false
        this.chatStatus = 'completed'
        this.stopWorkTimer()
        if (msg.used) {
          this.tokenUsage = msg.used
        }
        if (!this.userIsViewingHistory) {
          this.scrollToBottom()
        }
        // 消息完成 → 合上最新 thinking
        this.collapseLatestThinking()
        break

      case 'status':
        break

      case 'permission_request':
        this.flushStreamingBuffers()
        this.chatStatus = 'permission_pending'
        break

      case 'question':
      case 'questions':
        this.flushStreamingBuffers()
        this.chatStatus = 'question_pending'
        break

      case 'user_message_echo':
        if (msg.content) {
          let contentString = ''
          if (typeof msg.content === 'string') {
            contentString = msg.content
          } else {
            contentString = JSON.stringify(msg.content)
          }
          if (this.recentlySentMessages.has(contentString)) {
            this.recentlySentMessages.delete(contentString)
          }
        }
        break

      case 'token_usage':
        if (msg.percentage) {
          this.contextUsage = msg.percentage
        }
        break
    }
  }

  private flushStreamingBuffers(): void {
    // 先 flush 文本：文本出现时合上最新 thinking
    if (this.streamingText) {
      const trimmed = this.streamingText.trim()
      const shouldHide = trimmed.startsWith('[{') &&
        (trimmed.includes('"tool_use_id"') || trimmed.includes('"tool_result"'))

      if (!shouldHide) {
        const textMsg: Message = {
          id: 'assistant-' + Date.now(),
          type: 'assistant',
          content: this.streamingText,
          timestamp: new Date().toISOString()
        }
        sessionStore.addMessage(this.sessionId, textMsg)

        // 文本出现 → 合上最新 thinking（与 iOS 一致）
        if (this.latestThinkingId) {
          const newSet = new Set(this.expandedThinkingIds)
          newSet.delete(this.latestThinkingId)
          this.expandedThinkingIds = newSet
          this.latestThinkingId = ''
        }
      }
      this.streamingText = ''
    }

    // 再 flush thinking：自动展开最新 thinking，合上旧 thinking
    if (this.streamingThinking) {
      const thinkId = 'thinking-' + Date.now()
      const thinkMsg: Message = {
        id: thinkId,
        type: 'thinking',
        content: this.streamingThinking,
        timestamp: new Date().toISOString()
      }
      sessionStore.addMessage(this.sessionId, thinkMsg)

      // 自动展开最新 thinking，同时合上旧的
      const newSet = new Set(this.expandedThinkingIds)
      if (this.latestThinkingId) {
        newSet.delete(this.latestThinkingId)
      }
      newSet.add(thinkId)
      this.expandedThinkingIds = newSet
      this.latestThinkingId = thinkId

      this.streamingThinking = ''
    }
  }

  // HdsNavigation 菜单项
  private menus: Array<HdsNavigationBadgeIconOptions> = [
    {
      content: {
        icon: $r('sys.symbol.ellipsis_circle'),
        action: () => {
          this.showMenu = !this.showMenu
        }
      }
    }
  ]

  build() {
    Stack() {
      HdsNavigation() {
        // 消息列表
        List({ scroller: this.scroller }) {
          // 顶部占位
          ListItem() {
            Row().width('100%').height(8)
          }

        // 查看历史时：加载更多 + 消息计数（在列表顶部）
        if (this.hasMoreMessages()) {
          ListItem() {
            Column({ space: 2 }) {
              Row({ space: 8 }) {
                if (this.isLoadingMore) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color(Theme.TextSecondary)
                } else {
                  SymbolGlyph($r('sys.symbol.arrow_up'))
                    .fontSize(10)
                    .fontColor([Theme.TextSecondary])
                }
                Text('加载更早消息')
                  .fontSize(12)
                  .fontColor(Theme.TextSecondary)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ left: 8, right: 8, top: 8, bottom: 4 })
              .onClick(() => {
                this.loadMoreMessages()
              })

              Text(`已显示 ${this.displayedMessageCount}/${this.messages.length} 条`)
                .fontSize(10)
                .fontColor(Theme.TextTertiary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 2, bottom: 8 })
            }
          }
        }

        ForEach(this.getVisibleMessages(), (message: Message) => {
          ListItem() {
            this.MessageBubble(message)
          }
        }, (message: Message) => {
          // key 包含交互状态，确保权限/问答操作后 ForEach 重建组件
          if (message.type === 'permission_request') {
            return message.id + '_' + (message.isPermissionHandled ? 'done' : 'pending')
          }
          if (message.type === 'question') {
            return message.id + '_' + (message.isQuestionAnswered ? 'done' : 'pending')
          }
          return message.id
        })

        // 流式文本实时渲染（AI 逐字输出）
        if (this.streamingText) {
          ListItem() {
            this.StreamingTextBubble()
          }
        }

        // 流式思考实时渲染
        if (this.streamingThinking) {
          ListItem() {
            this.StreamingThinkingBubble()
          }
        }

        // AI 工作状态指示器（吉祥物动画，在流式内容后面）
        if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
          this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
          this.chatStatus === 'question_pending') {
          ListItem() {
            this.StreamingIndicator()
          }
        }

        // 底部留白（给悬浮输入框留空间，消息可滚入输入框下方）
        ListItem() {
          Row().width('100%').height(120)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onScrollIndex((start: number, end: number) => {
        // 滚动时关闭复制按钮
        if (this.activeCopyMessageId) {
          this.activeCopyMessageId = ''
        }
        // 与 iOS 一致：判断用户是否在最新消息位置
        // iOS 在倒序列表顶部放 anchor 检测，非倒序列表中检查最后一条消息是否可见
        const visibleMsgs = this.getVisibleMessages()
        const beforeMsgCount = (this.hasMoreMessages() ? 1 : 0) +
          ((this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
            this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
            this.chatStatus === 'question_pending') ? 1 : 0)
        const lastMsgIndex = beforeMsgCount + (visibleMsgs.length > 0 ? visibleMsgs.length - 1 : 0)
        // 结尾留白 2 项（消息数量提示 + 底部留白），给一点余量
        const totalItems = beforeMsgCount + visibleMsgs.length + 2

        if (end >= lastMsgIndex || end >= totalItems - 2) {
          // 用户看到了最后一条消息 → 在最新消息位置
          if (this.showNewMessageButton) {
            this.showNewMessageButton = false
            this.userIsViewingHistory = false
            this.animationProgress = 0
          }
        } else {
          // 用户向上滚动查看历史
          if (!this.showNewMessageButton) {
            this.showNewMessageButton = true
            this.userIsViewingHistory = true
          }
        }
      })
      .onDidScroll((xOffset: number, yOffset: number) => {
        if (yOffset !== this.scrollOffset) {
          this.scrollOffset = yOffset
        }
      })
      }
      .titleBar({
        content: {
          title: {
            mainTitle: this.conversationTitle,
          },
          menu: { value: this.menus },
        },
        style: {
          scrollEffectOpts: {
            enableScrollEffect: false,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
          },
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: false,
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(false)
      .backgroundColor('#121214')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 工作状态行（标题栏下方独立浮动容器）
      if (this.chatStatus !== 'idle' && this.chatStatus !== 'completed') {
        Row({ space: 6 }) {
          LoadingProgress()
            .width(10)
            .height(10)
            .color(this.getStatusColor())
          Text(this.getStatusText())
            .fontSize(11)
            .fontColor(this.getStatusColor())
          if (this.elapsedSeconds > 0) {
            Text(this.formatElapsed(this.elapsedSeconds))
              .fontSize(10)
              .fontColor(Theme.TextTertiary)
          }
          if (this.contextUsage > 0) {
            Text(`(${this.contextUsage}%)`)
              .fontSize(9)
              .fontColor(Theme.TextTertiary)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .position({ x: 0, y: 90 })
        .zIndex(5)
      }

      // 任务面板
      this.TaskBarView()

      // "最新消息"悬浮按钮（独立定位，不影响输入框位置）
      if (this.showNewMessageButton) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(14)
            .fontColor([Theme.AccentOrange])
            .scale({ x: this.mascotScale, y: this.mascotScale })
          Text('最新消息')
            .fontSize(11)
            .fontColor(Theme.TextPrimary)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('rgba(255,255,255,0.08)')
        .borderRadius(18)
        .border({ width: 0.5, color: 'rgba(255,255,255,0.15)' })
        .position({ x: '50%', y: '100%' })
        .translate({ x: '-50%', y: -130 })
        .zIndex(3)
        .onClick(() => {
          this.showNewMessageButton = false
          this.userIsViewingHistory = false
          this.animationProgress = 0
          this.scrollToBottom()
        })
      }

      // 底部悬浮输入框
      Column() {
        this.InputAreaContent()
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: Theme.SpacingLG })
      .backgroundColor(Color.Transparent)
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .zIndex(2)
      .opacity(this.userIsViewingHistory ? 0.7 : 1.0)
      .animation({ duration: 300, curve: Curve.EaseInOut })

    // 弹出菜单
      if (this.showMenu) {
        this.MenuPopup()
      }

      // 模型选择器
      if (this.showModelSelector) {
        this.ModelSelectorPopup()
      }

      // 斜杠命令
      if (this.showSlashCommands) {
        this.SlashCommandsPopup()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }

  // 标题栏状态行（与 iOS 一致：状态指示器 + 状态文字 + 上下文用量）
  @Builder
  TitleStatusView() {
    Row({ space: 4 }) {
      if (this.chatStatus !== 'idle' && this.chatStatus !== 'completed') {
        LoadingProgress()
          .width(10)
          .height(10)
          .color(this.getStatusColor())
      }
      Text(this.getStatusText())
        .fontSize(10)
        .fontColor(this.getStatusColor())
      if (this.contextUsage > 0) {
        Text(`(${this.contextUsage}%)`)
          .fontSize(9)
          .fontColor(Theme.TextTertiary)
      }
    }
  }

  @Builder
  StreamingIndicator() {
    Row() {
      Row({ space: 6 }) {
        // 像素吉祥物 — 根据工作状态实时变化
        PixelMascot({
          mascotSize: 27,
          status: this.getMascotStatus(),
          bodyColor: getMascotColorForSession(this.sessionId)
        })

        // 状态文字
        Text(this.getStatusText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        // 已用时间
        if (this.elapsedSeconds > 0) {
          Text(this.formatElapsed(this.elapsedSeconds))
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }

        // Token 数
        if (this.tokenUsage > 0) {
          Text(`· ↓ ${this.tokenUsage}`)
            .fontSize(10)
            .fontColor(Theme.TextTertiary)
        }
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(18)
      .border({
        width: 0.5,
        color: Theme.GlassBorder
      })

      Blank()
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingXS })
  }

  // 映射 chatStatus 到 MascotStatus
  private getMascotStatus(): MascotStatus {
    switch (this.chatStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return MascotStatus.PROCESSING
      case 'permission_pending':
      case 'question_pending':
        return MascotStatus.WAITING_APPROVAL
      case 'completed':
        return MascotStatus.COMPLETED
      default:
        return MascotStatus.IDLE
    }
  }

  // 获取可见消息（分页）
  private getVisibleMessages(): Message[] {
    if (this.messages.length <= this.displayedMessageCount) {
      return this.messages
    }
    return this.messages.slice(this.messages.length - this.displayedMessageCount)
  }

  private hasMoreMessages(): boolean {
    return this.messages.length > this.displayedMessageCount
  }

  private loadMoreMessages(): void {
    if (this.isLoadingMore) return
    this.isLoadingMore = true
    setTimeout(() => {
      const increment = 30
      const newCount = Math.min(this.displayedMessageCount + increment, this.messages.length)
      this.displayedMessageCount = newCount
      this.isLoadingMore = false
    }, 100)
  }

  @Builder
  MessageBubble(message: Message) {
    Column() {
      Row() {
        if (message.type === 'user') {
          Blank().layoutWeight(1)
        }

        if (message.type === 'user') {
          this.UserBubble(message)
        } else if (message.type === 'assistant') {
          this.AssistantBubble(message)
        } else if (message.type === 'thinking') {
          this.ThinkingBubble(message)
        } else if (message.type === 'tool_use') {
          this.ToolUseBubble(message)
        } else if (message.type === 'tool_result') {
          this.ToolResultBubble(message)
        } else if (message.type === 'permission_request') {
          this.PermissionBubble(message)
        } else if (message.type === 'question') {
          this.QuestionBubble(message)
        }

        if (message.type !== 'user') {
          Blank().layoutWeight(1)
        }
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  @Builder
  UserBubble(message: Message) {
    Column({ space: 4 }) {
      Text(message.content)
        .fontSize(15)
        .fontColor(Theme.TextPrimary)
        .lineHeight(22)

      if (this.activeCopyMessageId === message.id) {
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
          this.copyToClipboard(message.content)
          this.activeCopyMessageId = ''
        })
      }
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor('rgba(255,255,255,0.12)')
    .borderRadius(18)
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.activeCopyMessageId === message.id) {
            this.activeCopyMessageId = ''
          } else {
            this.activeCopyMessageId = message.id
          }
        })
    )
  }

  @Builder
  AssistantBubble(message: Message) {
    Column({ space: 4 }) {
      if (this.shouldHideContent(message.content)) {
        // 隐藏工具调用 JSON
      } else {
        MarkdownRenderer({ content: message.content })
      }

      if (this.activeCopyMessageId === message.id) {
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
          this.copyToClipboard(message.content)
          this.activeCopyMessageId = ''
        })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(18)
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.activeCopyMessageId === message.id) {
            this.activeCopyMessageId = ''
          } else {
            this.activeCopyMessageId = message.id
          }
        })
    )
  }

  // 流式文本气泡（实时渲染 AI 输出）
  @Builder
  StreamingTextBubble() {
    Row() {
      Column() {
        MarkdownRenderer({ content: this.streamingText })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor('rgba(255,255,255,0.08)')
      .borderRadius(18)
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  // 流式思考气泡（实时渲染 thinking 输出）
  @Builder
  StreamingThinkingBubble() {
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
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        Scroll() {
          Text(this.streamingThinking)
            .fontSize(11)
            .fontColor(Theme.TextSecondary)
            .fontFamily('monospace')
            .width('100%')
        }
        .height(Math.max(60, Math.min(200, this.streamingThinking.split('\n').length * 20)))
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, bottom: 10 })
      }
      .width('100%')
      .backgroundColor('rgba(255,255,255,0.04)')
      .borderRadius(10)
      .border({ width: 0.5, color: 'rgba(255,255,255,0.1)' })
    }
    .width('100%')
    .margin({ bottom: Theme.SpacingMD })
  }

  // 隐藏工具调用 JSON 格式的内容
  private shouldHideContent(content: string): boolean {
    const trimmed = content.trim()
    if (!trimmed.startsWith('[{')) return false
    return trimmed.includes('"tool_use_id"') || trimmed.includes('"tool_result"')
  }

  private copyMessage(text: string): void {
    this.copyToClipboard(text)
  }

  @Builder
  ThinkingBubble(message: Message) {
    Column({ space: 0 }) {
      // Header - 点击展开/折叠
      Row({ space: 8 }) {
        // 思考图标
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(12)
          .fontColor([Theme.AccentOrange])

        Text('thinking')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        // 折叠时显示摘要
        if (!this.expandedThinkingIds.has(message.id) && message.content) {
          Text(this.getThinkingSummary(message.content))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        if (this.expandedThinkingIds.has(message.id)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(9)
            .fontColor([Theme.TextTertiary])
        } else {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(9)
            .fontColor([Theme.TextTertiary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        this.toggleThinking(message.id)
      })

      // 展开内容
      if (this.expandedThinkingIds.has(message.id) && message.content) {
        Scroll() {
          Row({ space: 0 }) {
            Text(message.content)
              .fontSize(11)
              .fontColor(Theme.TextSecondary)
              .fontFamily('monospace')
              .layoutWeight(1)

            // 流式输出时显示光标
            if (message.isStreaming) {
              Column()
                .width(2)
                .height(12)
                .backgroundColor(Theme.TextTertiary)
                .borderRadius(1)
                .margin({ left: 2 })
            }
          }
          .width('100%')
        }
        .height(Math.max(100, Math.min(400, message.content ? message.content.split('\n').length * 22 : 200)))
        .scrollBar(BarState.Off)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor('rgba(255,255,255,0.02)')
      }
    }
    .width('100%')
    .backgroundColor('rgba(255,255,255,0.04)')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.1)'
    })
  }

  // 思考摘要
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

  private toggleThinking(id: string): void {
    const newSet = new Set(this.expandedThinkingIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedThinkingIds = newSet
  }

  // 合上最新 thinking（与 iOS 一致：新工具或内容出现后自动合上）
  private collapseLatestThinking(): void {
    if (this.latestThinkingId) {
      const newSet = new Set(this.expandedThinkingIds)
      newSet.delete(this.latestThinkingId)
      this.expandedThinkingIds = newSet
      this.latestThinkingId = ''
    }
  }

  @Builder
  ToolUseBubble(message: Message) {
    Column({ space: 0 }) {
      // Header
      Row({ space: 8 }) {
        // 图标
        Column() {
          SymbolGlyph(getToolIcon(message.toolName || 'Tool').symbol)
            .fontSize(12)
            .fontColor([getToolIcon(message.toolName || 'Tool').color])
        }
        .width(24)
        .height(24)
        .backgroundColor(getToolIcon(message.toolName || 'Tool').color + '20')
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)

        // 工具名
        Text(getToolIcon(message.toolName || 'Tool').label.toUpperCase())
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextSecondary)

        // 摘要
        if (!this.expandedToolIds.has(message.id)) {
          Text(this.getToolInputSummary(message.toolName || '', message.toolInput || {}))
            .fontSize(11)
            .fontColor(Theme.TextTertiary)
            .maxLines(1)
            .layoutWeight(1)
        }

        Blank()

        // 状态图标
        this.ToolStatusIcon(message.toolStatus)

        // 展开箭头
        if (this.isToolExpandable(message.toolName)) {
          if (this.expandedToolIds.has(message.id)) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(10)
              .fontColor([Theme.TextSecondary])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(10)
              .fontColor([Theme.TextSecondary])
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        if (this.isToolExpandable(message.toolName)) {
          this.toggleTool(message.id)
        }
      })

      // 展开区域
      if (this.expandedToolIds.has(message.id)) {
        Divider()
          .color('rgba(255,255,255,0.1)')
          .width('100%')

        Column({ space: 8 }) {
          // INPUT
          if (message.toolInput) {
            Column({ space: 4 }) {
              Text('INPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              Text(this.formatToolInput(message.toolInput))
                .fontSize(11)
                .fontColor(Theme.TextPrimary)
                .fontFamily('monospace')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // OUTPUT
          if (message.toolResult) {
            Column({ space: 4 }) {
              Text('OUTPUT')
                .fontSize(9)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.TextSecondary)

              MarkdownRenderer({ content: message.toolResult.length > 2000 ?
                message.toolResult.substring(0, 2000) + '...' : message.toolResult })
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
    .backgroundColor('rgba(255,255,255,0.06)')
    .borderRadius(10)
    .border({
      width: 0.5,
      color: 'rgba(255,255,255,0.12)'
    })
  }

  @Builder
  ToolStatusIcon(status?: string) {
    if (status === 'running') {
      LoadingProgress()
        .width(12)
        .height(12)
        .color(Theme.PrimaryColor)
    } else if (status === 'completed') {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(12)
        .fontColor([Theme.SuccessColor])
    } else if (status === 'failed') {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(12)
        .fontColor([Theme.ErrorColor])
    } else {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(10)
        .fontColor([Theme.TextTertiary])
    }
  }

  private isToolExpandable(toolName?: string): boolean {
    if (!toolName) return false
    return ['Edit', 'Write', 'Bash', 'Read', 'Grep', 'WebFetch'].indexOf(toolName) >= 0
  }

  private toggleTool(id: string): void {
    const newSet = new Set(this.expandedToolIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    this.expandedToolIds = newSet
  }

  private formatToolInput(input: Record<string, Object>): string {
    const lines: string[] = []
    const keys = Object.keys(input).sort()
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i]
      const value = input[key]
      if (typeof value === 'string') {
        const str = value as string
        if (str.length > 100) {
          lines.push(`${key}: "${str.substring(0, 100)}..."`)
        } else {
          lines.push(`${key}: "${str}"`)
        }
      } else if (typeof value === 'number') {
        lines.push(`${key}: ${value}`)
      } else if (typeof value === 'boolean') {
        lines.push(`${key}: ${value}`)
      } else if (value !== null && value !== undefined) {
        lines.push(`${key}: ${JSON.stringify(value)}`)
      }
    }
    return lines.join('\n')
  }


  // 工具结果气泡（独立显示，与 iOS toolResultBubble 一致）
  @Builder
  ToolResultBubble(message: Message) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(12)
          .fontColor([Theme.TextSecondary])

        Text('结果')
          .fontSize(Theme.FontTiny)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TextSecondary)

        Blank()

        if (message.toolStatus === 'completed') {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(12)
            .fontColor([Theme.SuccessColor])
        } else if (message.toolStatus === 'failed') {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(12)
            .fontColor([Theme.ErrorColor])
        }
      }
      .width('100%')

      if (message.toolResult) {
        MarkdownRenderer({ content: message.toolResult })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('rgba(255,255,255,0.08)')
    .borderRadius(12)
  }

  @Builder
  PermissionBubble(message: Message) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.lock_shield_fill'))
          .fontSize(20)
          .fontColor([Theme.AccentOrange])

        Text('权限请求')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
      }

      if (message.toolName) {
        Text('工具: ' + message.toolName)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      if (message.permissionDescription) {
        Text(message.permissionDescription)
          .fontSize(Theme.FontCaption)
          .fontColor(Theme.TextSecondary)
      }

      if (!message.isPermissionHandled) {
        Row({ space: 12 }) {
          Button('拒绝')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextPrimary)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              if (message.permissionId) {
                sessionStore.sendPermissionResponse(message.permissionId, false)
                message.isPermissionHandled = true
                message.permissionResult = false
                this.messageUpdateCounter++
              }
            })

          Button('允许')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextOnPrimary)
            .backgroundColor(Theme.PrimaryColor)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              if (message.permissionId) {
                sessionStore.sendPermissionResponse(message.permissionId, true)
                message.isPermissionHandled = true
                message.permissionResult = true
                this.messageUpdateCounter++
              }
            })
        }
        .width('100%')
      } else {
        Row({ space: 4 }) {
          if (message.permissionResult) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([Theme.SuccessColor])
          } else {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(14)
              .fontColor([Theme.ErrorColor])
          }
          Text(message.permissionResult ? '已允许' : '已拒绝')
            .fontSize(Theme.FontCaption)
            .fontColor(message.permissionResult ? Theme.SuccessColor : Theme.ErrorColor)
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  QuestionBubble(message: Message) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle_fill'))
          .fontSize(20)
          .fontColor([Theme.AccentPurple])

        Text('请选择')
          .fontSize(Theme.FontBody)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
      }

      Text(message.content)
        .fontSize(Theme.FontCaption)
        .fontColor(Theme.TextSecondary)

      if (!message.isQuestionAnswered && message.options && message.options.length > 0) {
        Column({ space: 8 }) {
          ForEach(message.options, (option: string, index: number) => {
            Button(option)
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextPrimary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(8)
              .width('100%')
              .onClick(() => {
                if (message.questionId) {
                  sessionStore.sendQuestionResponse(message.questionId, option)
                  message.isQuestionAnswered = true
                  message.selectedAnswer = option
                  this.messageUpdateCounter++
                }
              })
          }, (option: string, index: number) => `option-${index}`)

          // 自定义输入（与 iOS 一致）
          if (this.showCustomInput && this.activeQuestionMessageId === message.id) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '输入自定义回答...', text: this.customInputText })
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Theme.BackgroundTertiary)
                .borderRadius(8)
                .fontSize(Theme.FontCaption)
                .fontColor(Theme.TextPrimary)
                .onChange((value: string) => {
                  this.customInputText = value
                })
                .onSubmit(() => {
                  if (this.customInputText.trim() && message.questionId) {
                    sessionStore.sendQuestionResponse(message.questionId, this.customInputText.trim())
                    message.isQuestionAnswered = true
                    message.selectedAnswer = this.customInputText.trim()
                    this.messageUpdateCounter++
                    this.showCustomInput = false
                    this.customInputText = ''
                  }
                })

              Button('发送')
                .fontSize(Theme.FontTiny)
                .fontColor(Theme.TextOnPrimary)
                .backgroundColor(Theme.PrimaryColor)
                .borderRadius(8)
                .height(36)
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  if (this.customInputText.trim() && message.questionId) {
                    sessionStore.sendQuestionResponse(message.questionId, this.customInputText.trim())
                    message.isQuestionAnswered = true
                    message.selectedAnswer = this.customInputText.trim()
                    this.messageUpdateCounter++
                    this.showCustomInput = false
                    this.customInputText = ''
                  }
                })
            }
            .width('100%')
          } else {
            Button('自定义输入...')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .backgroundColor(Theme.BackgroundTertiary)
              .borderRadius(8)
              .width('100%')
              .onClick(() => {
                this.showCustomInput = true
                this.activeQuestionMessageId = message.id
                this.customInputText = ''
              })
          }
        }
        .width('100%')
      } else if (message.selectedAnswer) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(14)
            .fontColor([Theme.SuccessColor])
          Text(message.selectedAnswer)
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.SuccessColor)
        }
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
    .backgroundColor(Theme.BackgroundSecondary)
    .borderRadius(Theme.RadiusMedium)
  }

  @Builder
  InputAreaContent() {
    Row({ space: 10 }) {
      // 菜单按钮 - 液态玻璃
      Column() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([Theme.TextSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor('#40FFFFFF')
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 2 })
      .borderRadius(18)
      .borderWidth(1)
      .borderColor('#80FFFFFF')
      .outline({ width: 1, color: '#1A000000', radius: 18 })
      .linearGradient({ angle: 180, colors: [['#10FFFFFF', 0.0], ['#00FFFFFF', 0.3]] })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showMenu = !this.showMenu
        this.showModelSelector = false
        this.showSlashCommands = false
      })

      // 输入框 - 液态玻璃，多行自适应高度（往上增长）
      TextArea({ placeholder: '发送消息...', text: this.inputText })
        .layoutWeight(1)
        .constraintSize({ minHeight: 36, maxHeight: 120 })
        .backgroundColor('#40FFFFFF')
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 2 })
        .borderRadius(18)
        .borderWidth(1)
        .borderColor('#80FFFFFF')
        .outline({ width: 1, color: '#1A000000', radius: 18 })
        .linearGradient({ angle: 180, colors: [['#10FFFFFF', 0.0], ['#00FFFFFF', 0.3]] })
        .fontColor(Theme.TextPrimary)
        .placeholderColor('rgba(255,255,255,0.3)')
        .fontSize(Theme.FontBody)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onChange((value: string) => {
          this.inputText = value
        })

      // 发送按钮 - 液态玻璃（无输入时），有输入时高亮
      Column() {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(16)
          .fontColor([this.inputText ? Theme.TextPrimary : Theme.TextSecondary])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.inputText ? Theme.PrimaryColor : '#40FFFFFF')
      .backgroundBlurStyle(this.inputText ? BlurStyle.NONE : BlurStyle.COMPONENT_REGULAR)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 2 })
      .borderRadius(18)
      .borderWidth(this.inputText ? 0 : 1)
      .borderColor(this.inputText ? Color.Transparent : '#80FFFFFF')
      .outline(this.inputText ? undefined : { width: 1, color: '#1A000000', radius: 18 })
      .linearGradient(this.inputText ? undefined : { angle: 180, colors: [['#10FFFFFF', 0.0], ['#00FFFFFF', 0.3]] })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.sendMessage()
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
  }

  // 菜单弹出
  @Builder
  MenuPopup() {
    Column() {
      Column({ space: 4 }) {
        // 模型选择器
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.waveform'))
            .fontSize(20)
            .fontColor([Theme.PrimaryColor])

          Text('模型选择器')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          if (this.currentModel) {
            Text(this.currentModel)
              .fontSize(Theme.FontTiny)
              .fontColor(Theme.TextTertiary)
          }

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showModelSelector = true
          this.loadModels()
        })

        // 斜杠命令
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(20)
            .fontColor([Theme.AccentPurple])

          Text('斜杠命令')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundSecondary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.showSlashCommands = true
        })
      }
      .width(200)
      .padding(Theme.SpacingSM)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .justifyContent(FlexAlign.End)
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: 80 })
    .onClick(() => {
      this.showMenu = false
    })
  }

  // 模型选择器弹出
  @Builder
  ModelSelectorPopup() {
    Column() {
      Column({ space: 12 }) {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
            .onClick(() => {
              this.showModelSelector = false
              this.showMenu = true
            })

          Text('选择模型')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(20)
        }
        .width('100%')
        .padding({ bottom: Theme.SpacingSM })

        if (this.isLoadingModels) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Theme.PrimaryColor)

            Text('加载中...')
              .fontSize(Theme.FontCaption)
              .fontColor(Theme.TextSecondary)
              .margin({ top: Theme.SpacingMD })
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
        } else if (this.models.length === 0) {
          Column() {
            Text('暂无可用模型')
              .fontSize(Theme.FontBody)
              .fontColor(Theme.TextSecondary)
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.models, (model: ModelInfo) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text(model.name || model.id)
                      .fontSize(Theme.FontBody)
                      .fontColor(Theme.TextPrimary)

                    if (model.description) {
                      Text(model.description)
                        .fontSize(Theme.FontTiny)
                        .fontColor(Theme.TextTertiary)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.currentModel === model.id) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(20)
                      .fontColor([Theme.PrimaryColor])
                  }
                }
                .width('100%')
                .padding(Theme.SpacingMD)
                .backgroundColor(this.currentModel === model.id ? Theme.PrimaryColorLight : Theme.BackgroundSecondary)
                .borderRadius(12)
                .onClick(() => {
                  this.selectModel(model.id)
                })
              }
            }, (model: ModelInfo) => model.id)
          }
          .width('100%')
          .height(Math.min(this.models.length * 80, 300))
          .scrollBar(BarState.Auto)
        }
      }
      .width('85%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(20)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showModelSelector = false
    })
  }

  // 斜杠命令弹出
  @Builder
  SlashCommandsPopup() {
    Column() {
      Column({ space: 12 }) {
        // 标题栏
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([Theme.TextPrimary])
            .onClick(() => {
              this.showSlashCommands = false
              this.showMenu = true
            })

          Text('斜杠命令')
            .fontSize(Theme.FontHeading)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TextPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Row().width(20)
        }
        .width('100%')
        .padding({ bottom: Theme.SpacingSM })

        List({ space: 8 }) {
          ForEach(this.slashCommands, (cmd: SlashCommand, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(cmd.name)
                    .fontSize(Theme.FontBody)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.TextPrimary)

                  Text(cmd.description)
                    .fontSize(Theme.FontTiny)
                    .fontColor(Theme.TextTertiary)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(Theme.SpacingMD)
              .backgroundColor(Theme.BackgroundSecondary)
              .borderRadius(12)
              .onClick(() => {
                this.selectSlashCommand(cmd.name)
              })
            }
          }, (cmd: SlashCommand, index: number) => `cmd-${index}`)
        }
        .width('100%')
        .height(Math.min(this.slashCommands.length * 70, 350))
        .scrollBar(BarState.Auto)
      }
      .width('85%')
      .padding(Theme.SpacingLG)
      .backgroundColor(Theme.BackgroundPrimary)
      .borderRadius(20)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showSlashCommands = false
    })
  }

  // MARK: - 任务面板（与 iOS SessionTaskBarView 一致）

  @Builder
  TaskBarView() {
    if (sessionStore.getCurrentTasks() && sessionStore.getCurrentTasks().length > 0 && !sessionStore.taskBarDismissed) {
      Column({ space: 0 }) {
        Divider()
          .color('rgba(255,255,255,0.08)')
          .width('100%')

        Column({ space: 0 }) {
          // 标题栏
          Row({ space: 8 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(13)
                .fontColor([Theme.AccentBlue])
            }
            .width(26)
            .height(26)
            .backgroundColor('rgba(10, 132, 255, 0.1)')
            .borderRadius(6)
            .justifyContent(FlexAlign.Center)

            Text('任务')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TextPrimary)

            // 进度条
            Row() {
              Row()
                .width(this.getTaskProgress(sessionStore.getCurrentTasks()) + '%')
                .height('100%')
                .backgroundColor(this.areAllTasksCompleted(sessionStore.getCurrentTasks()) ? Theme.SuccessColor : Theme.AccentBlue)
                .borderRadius(2)
            }
            .width(120)
            .height(4)
            .backgroundColor('rgba(255,255,255,0.1)')
            .borderRadius(2)

            Text(this.getCompletedTaskCount(sessionStore.getCurrentTasks()) + '/' + sessionStore.getCurrentTasks().length)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor(Theme.TextSecondary)

            Blank()

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(11)
              .fontColor([Theme.TextSecondary])
              .rotate({ angle: sessionStore.taskBarExpanded ? 0 : 180 })

            if (this.areAllTasksCompleted(sessionStore.getCurrentTasks())) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(10)
                .fontColor([Theme.TextSecondary])
                .onClick(() => {
                  sessionStore.dismissTaskBar()
                })
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick(() => {
            sessionStore.toggleTaskBarExpanded()
          })

          // 展开任务列表
          if (sessionStore.taskBarExpanded) {
            Divider()
              .color('rgba(255,255,255,0.05)')
              .width('100%')

            Scroll() {
              Column({ space: 2 }) {
                ForEach(sessionStore.getCurrentTasks(), (task: TaskItem) => {
                  this.TaskItemRow(task)
                }, (task: TaskItem) => task.id)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            }
            .height(Math.min(sessionStore.getCurrentTasks().length * 50, 200))
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .backgroundColor('rgba(255,255,255,0.03)')
        .margin({ bottom: 8 })
      }
      .width('100%')
    }
  }

  @Builder
  TaskItemRow(task: TaskItem) {
    Row({ space: 8 }) {
      // 状态图标
      if (task.status === 'in_progress') {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(Theme.AccentBlue)
      } else {
        SymbolGlyph(this.getTaskStatusIcon(task.status))
          .fontSize(12)
          .fontColor([this.getTaskStatusColor(task.status)])
      }

      // 内容
      Column({ space: 2 }) {
        Row({ space: 4 }) {
          Text(`#${task.id}`)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(Theme.TextTertiary)
          Text(task.content)
            .fontSize(12)
            .fontColor(task.status === 'completed' ? Theme.TextSecondary : Theme.TextPrimary)
            .decoration(task.status === 'completed' ?
              { type: TextDecorationType.LineThrough, color: Theme.TextSecondary } :
              undefined)
        }

        if (task.status === 'in_progress' && task.activeForm) {
          Row({ space: 4 }) {
            Row()
              .width(5)
              .height(5)
              .backgroundColor(Theme.AccentOrange)
              .borderRadius(2.5)
            Text(task.activeForm)
              .fontSize(10)
              .fontColor(Theme.AccentOrange)
          }
        }

        if (task.owner) {
          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.person_fill'))
              .fontSize(8)
              .fontColor([Theme.TextTertiary])
            Text(task.owner)
              .fontSize(10)
              .fontColor(Theme.TextTertiary)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4, left: 4, right: 4 })
    .backgroundColor(task.status === 'in_progress' ? 'rgba(10, 132, 255, 0.06)' : Color.Transparent)
    .borderRadius(4)
  }

  private getTaskProgress(tasks: TaskItem[]): number {
    const completed = tasks.filter(t => t.status === 'completed').length
    return tasks.length > 0 ? Math.round((completed / tasks.length) * 100) : 0
  }

  private getCompletedTaskCount(tasks: TaskItem[]): number {
    return tasks.filter(t => t.status === 'completed').length
  }

  private areAllTasksCompleted(tasks: TaskItem[]): boolean {
    return tasks.length > 0 && tasks.every(t => t.status === 'completed')
  }

  private getTaskStatusIcon(status: TaskStatus): Resource {
    switch (status) {
      case 'completed': return $r('sys.symbol.checkmark_circle_fill')
      case 'failed': return $r('sys.symbol.xmark_circle_fill')
      default: return $r('sys.symbol.clock')
    }
  }

  private getTaskStatusColor(status: TaskStatus): ResourceColor {
    switch (status) {
      case 'completed': return Theme.SuccessColor
      case 'failed': return Theme.ErrorColor
      default: return Theme.TextTertiary
    }
  }

  private startWorkTimer(): void {
    if (this.workTimer >= 0) return
    this.elapsedSeconds = 0
    this.workTimer = setInterval(() => {
      this.elapsedSeconds++
    }, 1000)
    // 启动吉祥物慢速脉冲动画
    this.mascotScale = 0.85
    animateTo({
      duration: 3000,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.mascotScale = 1.15
    })
  }

  private stopWorkTimer(): void {
    if (this.workTimer >= 0) {
      clearInterval(this.workTimer)
      this.workTimer = -1
    }
  }

  private formatElapsed(seconds: number): string {
    if (seconds < 60) return `${seconds}s`
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return `${m}m ${s}s`
  }

  private getStatusText(): string {
    switch (this.chatStatus) {
      case 'idle': return '空闲'
      case 'thinking': return '思考中...'
      case 'streaming': return '工作中...'
      case 'tool_executing': return '执行中...'
      case 'permission_pending': return '等待权限'
      case 'question_pending': return '等待回答'
      case 'completed': return '已完成'
      default: return ''
    }
  }

  private getStatusColor(): ResourceColor {
    switch (this.chatStatus) {
      case 'thinking':
      case 'streaming':
      case 'tool_executing':
        return Theme.AccentGreen
      case 'permission_pending':
        return Theme.AccentOrange
      case 'question_pending':
        return Theme.AccentPurple
      case 'completed':
        return Theme.SuccessColor
      default:
        return Theme.TextSecondary
    }
  }

  private sendMessage(): void {
    if (!this.inputText.trim()) return

    const content = this.inputText.trim()
    this.inputText = ''

    // 去重：记录最近发送的消息
    this.recentlySentMessages.add(content)
    this.userIsViewingHistory = false

    sessionStore.sendMessage(content)

    // 重置流式缓冲区
    this.streamingText = ''
    this.streamingThinking = ''
    this.inTextBlock = false
    this.inThinkingBlock = false
    this.latestThinkingId = ''

    this.chatStatus = 'thinking'
    this.startWorkTimer()

    this.scrollToBottom()
  }
}
