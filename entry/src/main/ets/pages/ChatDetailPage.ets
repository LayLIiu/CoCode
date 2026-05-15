/**
 * 对话详情页 - 实时消息收发
 * 与 iOS 端完全一致的聊天体验
 */

import { Theme } from '../common/Theme'
import { Message, Session, SessionStatus, ModelInfo, WSMessage, TaskItem, TaskStatus, AttachmentRef } from '../models/Models'
import { HdsNavigation, ScrollEffectType, HdsNavigationBadgeIconOptions, HdsNavigationTitleMode } from '@hms.hds.hdsBaseComponent'
import { hdsMaterial } from '@hms.hds.hdsMaterial'
import { sessionStore } from '../stores/SessionStore'
import { authStore } from '../stores/AuthStore'
import { apiService } from '../services/APIService'
import { MarkdownRenderer } from '../components/MarkdownRenderer'
import { PixelMascot, MascotStatus, getMascotColorForSession, getMascotTypeForProvider } from '../components/PixelMascot'
import { HdsMiniBarButton } from '../components/HdsMiniBarButton'
import { HdsGlassInput } from '../components/HdsGlassInput'
import router from '@ohos.router'
import pasteboard from '@ohos.pasteboard'
import vibrator from '@ohos.vibrator'
import photoViewPicker from '@ohos.file.picker'
import fileIo from '@ohos.file.fs'
import util from '@ohos.util'

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
  @State showSheet: boolean = false
  @State sheetType: string = '' // 'model' or 'slash'
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

  // 附件（图片发送）
  @State pendingAttachments: AttachmentRef[] = []
  // 附件动作 Sheet 复用 showSheet + sheetType='attachment'

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

  // 用户触控追踪：手指在屏幕上时不自动滚动
  @State isUserTouchingList: boolean = false

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
  @State isMessagesLoaded: boolean = false
  @State isListReady: boolean = false

  // 标题栏动态模糊（滚动时背景渐变透明）
  @State scrollOffset: number = 0
  private readonly blurThreshold: number = 30

  private scroller: Scroller = new Scroller()

  // 流式 thinking 自动滚动
  private streamingThinkingScroller: Scroller = new Scroller()
  private thinkingScrollTimer: number = -1

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
    // 恢复输入框草稿
    const draft = sessionStore.inputDrafts.get(this.sessionId)
    if (draft) {
      this.inputText = draft
    }
  }

  aboutToDisappear(): void {
    // 保存输入框草稿
    if (this.inputText) {
      sessionStore.inputDrafts.set(this.sessionId, this.inputText)
    } else {
      sessionStore.inputDrafts.delete(this.sessionId)
    }
    this.stopWorkTimer()
    if (this.thinkingScrollTimer !== -1) {
      clearTimeout(this.thinkingScrollTimer)
      this.thinkingScrollTimer = -1
    }
    this.removeCallbacks()
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
      // 初始显示最后100条
      this.displayedMessageCount = Math.min(100, this.messages.length)
    }
    // 倒序列表默认就在最新消息位置，无需scrollTo
    this.isMessagesLoaded = true
    this.isListReady = true
  }

  private messagesChangedListener = (sid: string) => {
    if (sid === this.sessionId) {
      const msgs = sessionStore.messages.get(this.sessionId)
      if (msgs) {
        this.messages = msgs
      }
      // 查看历史或用户触控时不强制滚动，避免打断用户
      if (!this.userIsViewingHistory && !this.isUserTouchingList) {
        this.scrollToBottom()
      }
    }
  }

  private statusChangedListener = (sid: string, status: SessionStatus) => {
    if (sid === this.sessionId) {
      this.chatStatus = status
    }
  }

  private rawMessageListener = (sid: string, msg: WSMessage) => {
    if (sid === this.sessionId) {
      this.handleStreamingMessage(msg)
    }
  }

  private setupCallbacks(): void {
    sessionStore.addMessagesChangedListener(this.messagesChangedListener)
    sessionStore.addStatusChangedListener(this.statusChangedListener)
    sessionStore.addRawMessageListener(this.rawMessageListener)
  }

  private removeCallbacks(): void {
    sessionStore.removeMessagesChangedListener(this.messagesChangedListener)
    sessionStore.removeStatusChangedListener(this.statusChangedListener)
    sessionStore.removeRawMessageListener(this.rawMessageListener)
  }

  private scrollToBottom(): void {
    // 倒序列表：最新消息在顶部（视觉底部），scrollEdge(Top) 就是回到最新消息
    this.scroller.scrollEdge(Edge.Top)
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
      this.showSheet = false
      this.showMenu = false
    } catch (e) {
      console.error(`[ChatDetailPage] Set model error: ${e}`)
    }
  }

  // 选择斜杠命令
  private selectSlashCommand(cmd: string): void {
    this.inputText = cmd + ' '
    this.showSheet = false
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
          // 流式文本实时滚动：仅当用户未查看历史且未触控时
          if (!this.userIsViewingHistory && !this.isUserTouchingList) {
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
          if (!this.userIsViewingHistory && !this.isUserTouchingList) {
            this.scrollToBottom()
          }
          // 流式 thinking 自动滚动到底部（根据内容长度控制速度）
          if (!this.isUserTouchingList) {
            this.scheduleThinkingScroll(msg.text.length)
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
        if (!this.userIsViewingHistory && !this.isUserTouchingList) {
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
        this.vibrateAlert()
        break

      case 'question':
      case 'questions':
        this.flushStreamingBuffers()
        this.chatStatus = 'question_pending'
        this.vibrateAlert()
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
    // 先 flush thinking：自动展开最新 thinking，合上旧 thinking
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

    // 再 flush 文本：thinking 应在 text 之前
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
        // 消息列表 — 倒序+翻转：默认就在"底部"（最新消息），无需scrollTo
        List({ scroller: this.scroller }) {
          // 顶部留白（翻转后视觉在底部，给悬浮输入框留空间）
          ListItem() {
            Row().width('100%').height(120)
          }
          .rotate({ angle: 180 })

          // 流式文本实时渲染（翻转后视觉在消息列表最前面=最新位置）
          if (this.streamingText) {
            ListItem() {
              this.StreamingTextBubble()
            }
            .rotate({ angle: 180 })
          }

          // 流式思考实时渲染
          if (this.streamingThinking) {
            ListItem() {
              this.StreamingThinkingBubble()
            }
            .rotate({ angle: 180 })
          }

          // AI 工作状态指示器（吉祥物动画）
          if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
            this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
            this.chatStatus === 'question_pending') {
            ListItem() {
              this.StreamingIndicator()
            }
            .rotate({ angle: 180 })
          }

          // 消息倒序排列（最新在前=视觉底部）
          ForEach(this.getVisibleMessages().reverse(), (message: Message) => {
            ListItem() {
              this.MessageBubble(message)
            }
            .rotate({ angle: 180 })
          }, (message: Message) => {
            if (message.type === 'permission_request') {
              return message.id + '_' + (message.isPermissionHandled ? 'done' : 'pending')
            }
            if (message.type === 'question') {
              return message.id + '_' + (message.isQuestionAnswered ? 'done' : 'pending')
            }
            return message.id
          })

          // 加载更多历史提示（翻转后视觉在顶部）
          if (this.hasMoreMessages()) {
            ListItem() {
              Column({ space: 2 }) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color(Theme.TextSecondary)
                  Text('下滑加载更早消息')
                    .fontSize(12)
                    .fontColor(Theme.TextSecondary)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ left: 8, right: 8, top: 8, bottom: 4 })

                Text(`已显示 ${this.displayedMessageCount}/${this.messages.length} 条`)
                  .fontSize(10)
                  .fontColor(Theme.TextTertiary)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 2, bottom: 8 })
              }
            }
            .rotate({ angle: 180 })
          }

          // 底部占位（翻转后视觉在顶部）
          ListItem() {
            Row().width('100%').height(8)
          }
          .rotate({ angle: 180 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .rotate({ angle: 180 })  // 整体翻转，使列表默认在最新消息位置
        .onScrollIndex((start: number, end: number) => {
          // 翻转后：滚到底部=视觉顶部=加载更多历史
          const totalItems = this.getListItemCount()
          if (end >= totalItems - 1 && this.hasMoreMessages() && !this.isLoadingMore) {
            this.loadMoreMessages()
          }
          // 翻转后：start=0 表示在列表顶部=视觉底部=最新消息
          if (start === 0) {
            // 在最新消息位置
            if (this.showNewMessageButton) {
              this.showNewMessageButton = false
              this.userIsViewingHistory = false
              this.animationProgress = 0
            }
          } else {
            // 向上滚动查看历史
            if (!this.showNewMessageButton && start > 2) {
              this.showNewMessageButton = true
              this.userIsViewingHistory = true
            }
          }
        })
        .onDidScroll((xOffset: number, yOffset: number) => {
          // 翻转后滚动方向反转
          if (-yOffset !== this.scrollOffset) {
            this.scrollOffset = -yOffset
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isUserTouchingList = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            // 手指抬起后延迟重置，等惯性滑动结束
            setTimeout(() => {
              this.isUserTouchingList = false
            }, 600)
          }
        })
        }
        .opacity(this.isMessagesLoaded ? 1.0 : 0.0)
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

      // 工作状态行 & 连接指示器（标题栏下方独立浮动容器）
      Column() {
        // 连接方式指示
        Row({ space: 4 }) {
          SymbolGlyph(this.getConnectionIcon())
            .fontSize(9)
            .fontColor([this.getConnectionColor()])
          Text(this.getConnectionLabel())
            .fontSize(9)
            .fontColor(Theme.TextTertiary)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 0 })

        // 工作状态
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
        }
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
      .position({ x: 0, y: 88 })
      .zIndex(5)

      // 任务面板
      this.TaskBarView()

      // 底部悬浮输入框（包含最新消息按钮）
      Column({ space: 8 }) {
        // "最新消息"按钮 - 跟随输入框移动
        if (this.showNewMessageButton) {
          Row() {
            HdsMiniBarButton({
              barWidth: 100,
              barHeight: 32,
              contentPadding: 6,
              maskColor: 'rgba(255,255,255,0.15)',
              barBottomMargin: 0,
              onButtonClick: () => {
                this.showNewMessageButton = false
                this.userIsViewingHistory = false
                this.animationProgress = 0
                this.scrollToBottom()
              }
            }) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrow_down'))
                  .fontSize(12)
                  .fontColor([Theme.TextSecondary])
                Text('最新消息')
                  .fontSize(11)
                  .fontColor(Theme.TextPrimary)
              }
            }
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }

        this.InputAreaContent()
      }
      .width('100%')
      .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG, bottom: 28 })
      .backgroundColor(Color.Transparent)
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
      .zIndex(2)
      .opacity(this.userIsViewingHistory ? 0.7 : 1.0)
      .animation({ duration: 300, curve: Curve.EaseInOut })
      .clip(false)  // 禁用裁切，让按钮形变效果可以超出边界

    // 菜单气泡 - 从按钮左下角扩散
      if (this.showMenu) {
        this.MenuBubble()
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .clip(false)  // 禁用裁切，让按钮形变效果可以超出边界
    .bindSheet($$this.showSheet, this.sheetType === 'model' ? this.ModelSelectorSheet() : this.sheetType === 'attachment' ? this.AttachmentActionSheet() : this.SlashCommandsSheet(), {
      height: this.sheetType === 'attachment' ? 200 : 480,
      backgroundColor: '#1C1C1E',
      dragBar: true,
      showClose: false,
      blurStyle: BlurStyle.COMPONENT_THICK
    })
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
          bodyColor: getMascotColorForSession(this.sessionId),
          mascotType: getMascotTypeForProvider(this.getSessionProviderId())
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

  private getSessionProviderId(): string {
    const session = sessionStore.sessions.find((s: Session) => s.id === this.sessionId)
    return session?.providerId || ''
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

  // 计算 List 总项数（用于 onScrollIndex）
  private getListItemCount(): number {
    let count = 2 // 顶部留白 + 底部占位
    count += this.getVisibleMessages().length
    if (this.streamingText) count++
    if (this.streamingThinking) count++
    if (this.chatStatus === 'thinking' || this.chatStatus === 'streaming' ||
      this.chatStatus === 'tool_executing' || this.chatStatus === 'permission_pending' ||
      this.chatStatus === 'question_pending') count++
    if (this.hasMoreMessages()) count++
    return count
  }

  private loadMoreMessages(): void {
    if (this.isLoadingMore) return
    this.isLoadingMore = true
    setTimeout(() => {
      const increment = 100
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

        Scroll(this.streamingThinkingScroller) {
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

  // 流式 thinking 自动滚动（根据新增内容长度控制速度）
  private scheduleThinkingScroll(deltaLength: number): void {
    if (this.thinkingScrollTimer !== -1) {
      clearTimeout(this.thinkingScrollTimer)
    }
    // 速度策略：内容少时快速跟随，内容多时稍慢让用户能阅读
    // deltaLength 越大 → 延迟越长（给渲染时间）
    // 整体内容越长 → 滚动间隔稍长
    const totalLength = this.streamingThinking.length
    const baseDelay = Math.max(30, Math.min(150, deltaLength * 2))
    const contentFactor = Math.max(1, Math.min(3, totalLength / 2000))
    const delay = Math.round(baseDelay * contentFactor)

    this.thinkingScrollTimer = setTimeout(() => {
      try {
        this.streamingThinkingScroller.scrollEdge(Edge.Bottom)
      } catch (e) {
        // scroller 可能尚未绑定，忽略
      }
      this.thinkingScrollTimer = -1
    }, delay)
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
    Column({ space: 8 }) {
      // 附件预览 - 水平滚动缩略图
      if (this.pendingAttachments.length > 0) {
        this.AttachmentPreviewRow()
      }

      Row({ space: 8 }) {
        // 菜单按钮 - 沉浸光感浮动按钮
        HdsMiniBarButton({
          barWidth: 36,
          barHeight: 36,
          contentPadding: 4,
          iconResource: $r('sys.symbol.plus'),
          iconSize: 16,
          iconColor: [Theme.TextSecondary],
          maskColor: 'rgba(255,255,255,0.15)',
          barBottomMargin: 0,
          onButtonClick: () => {
            this.showMenu = !this.showMenu
            this.showSheet = false
          }
        })

        // 输入框 - 液态玻璃效果
        TextArea({ placeholder: this.pendingAttachments.length > 0 ? '添加描述或直接发送...' : '发送消息...', text: this.inputText })
          .layoutWeight(1)
          .constraintSize({ minHeight: 36, maxHeight: 120 })
          .backgroundColor('rgba(255,255,255,0.1)')
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .borderRadius(18)
          .fontColor(Theme.TextPrimary)
          .placeholderColor('rgba(255,255,255,0.3)')
          .fontSize(Theme.FontBody)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onChange((value: string) => {
            this.inputText = value
          })

        // 发送按钮 - 沉浸光感浮动按钮
        if (this.inputText || this.pendingAttachments.length > 0) {
          // 有内容：实心高亮按钮
          HdsMiniBarButton({
            barWidth: 36,
            barHeight: 36,
            contentPadding: 4,
            iconResource: $r('sys.symbol.arrow_up'),
            iconSize: 16,
            iconColor: [Theme.TextOnPrimary],
            maskColor: Theme.PrimaryColor,
            barBottomMargin: 0,
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
            onButtonClick: () => {
              this.sendMessage()
            }
          })
        } else {
          // 无内容：液态玻璃效果
          HdsMiniBarButton({
            barWidth: 36,
            barHeight: 36,
            contentPadding: 4,
            iconResource: $r('sys.symbol.arrow_up'),
            iconSize: 16,
            iconColor: [Theme.TextSecondary],
            maskColor: 'rgba(255,255,255,0.15)',
            barBottomMargin: 0,
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
            onButtonClick: () => {
              this.sendMessage()
            }
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .clip(false)
    }
    .width('100%')
  }

  @Builder
  AttachmentPreviewRow() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.pendingAttachments, (attachment: AttachmentRef, index: number) => {
          Stack() {
            // 缩略图
            Image('data:' + (attachment.mimeType || 'image/jpeg') + ';base64,' + attachment.data)
              .width(64)
              .height(64)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)

            // 删除按钮
            Column() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(8)
                .fontColor([Color.White])
            }
            .width(18)
            .height(18)
            .backgroundColor('rgba(0,0,0,0.6)')
            .borderRadius(9)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .position({ x: 0, y: 0 })
            .margin({ left: -4, top: -4 })
            .onClick(() => {
              const newList = [...this.pendingAttachments]
              newList.splice(index, 1)
              this.pendingAttachments = newList
            })

            // 文件名标签
            if (attachment.name) {
              Text(attachment.name)
                .fontSize(8)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(56)
                .textAlign(TextAlign.Center)
                .position({ x: 0, y: 0 })
                .margin({ left: 4, bottom: 4 })
            }
          }
          .width(64)
          .height(64)
        })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }
    .height(76)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  AttachmentActionSheet() {
    Column({ space: 0 }) {
      // 标题
      Text('发送图片')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TextPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: Theme.SpacingLG, bottom: Theme.SpacingLG })

      // 从相册选择
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(22)
          .fontColor([Theme.AccentBlue])

        Column({ space: 2 }) {
          Text('从相册选择')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Text('选择手机中的图片发送给 AI')
            .fontSize(Theme.FontCaption)
            .fontColor(Theme.TextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([Theme.TextTertiary])
      }
      .width('100%')
      .padding(Theme.SpacingMD)
      .backgroundColor(Theme.GlassBackground)
      .borderRadius(Theme.RadiusMedium)
      .border({ width: 0.5, color: Theme.GlassBorder })
      .onClick(() => {
        this.showSheet = false
        this.pickPhotoFromGallery()
      })
    }
    .width('100%')
    .padding({ left: Theme.SpacingLG, right: Theme.SpacingLG })
  }

  // 菜单气泡 - 从按钮左下角扩散
  @Builder
  MenuBubble() {
    Stack() {
      // 菜单卡片 - 磨砂背景，靠左下角
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.sheetType = 'model'
          this.showSheet = true
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
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.sheetType = 'slash'
          this.showSheet = true
        })

        // 发送图片
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(20)
            .fontColor([Theme.AccentBlue])

          Text('发送图片')
            .fontSize(Theme.FontBody)
            .fontColor(Theme.TextPrimary)

          Blank()

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([Theme.TextTertiary])
        }
        .width('100%')
        .padding(Theme.SpacingMD)
        .backgroundColor(Theme.BackgroundTertiary)
        .borderRadius(12)
        .onClick(() => {
          this.showMenu = false
          this.sheetType = 'attachment'
          this.showSheet = true
        })
      }
      .width(220)
      .padding(Theme.SpacingSM)
      .backgroundColor(Theme.BackgroundSecondary)
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.3)', offsetY: 4 })
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      // 扩散动画：从左下角缩放 + 渐显
      .transition(TransitionEffect.scale({ x: 0.3, y: 0.3 }).animation({ duration: 250, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .alignContent(Alignment.BottomStart)
    .padding({ left: Theme.SpacingLG, bottom: 85 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
    .onClick(() => {
      this.showMenu = false
    })
  }

  // 模型选择器 Sheet（底部弹出）
  @Builder
  ModelSelectorSheet() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('选择模型')
          .fontSize(Theme.FontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
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
              .backgroundColor(this.currentModel === model.id ? Theme.PrimaryColorLight : Theme.BackgroundTertiary)
              .borderRadius(12)
              .onClick(() => {
                this.selectModel(model.id)
              })
            }
          }, (model: ModelInfo) => model.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding(Theme.SpacingLG)
  }

  // 斜杠命令 Sheet — 与模型选择器完全一致的布局
  @Builder
  SlashCommandsSheet() {
    Column({ space: 12 }) {
      // 标题栏
      Row() {
        Text('斜杠命令')
          .fontSize(Theme.FontHeading)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TextPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ bottom: Theme.SpacingSM })

      List({ space: 8 }) {
        ForEach(this.slashCommands, (cmd: SlashCommand) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(cmd.name)
                  .fontSize(Theme.FontBody)
                  .fontColor(Theme.TextPrimary)

                Text(cmd.description)
                  .fontSize(Theme.FontTiny)
                  .fontColor(Theme.TextTertiary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(Theme.SpacingMD)
            .backgroundColor(Theme.BackgroundTertiary)
            .borderRadius(12)
            .onClick(() => {
              this.selectSlashCommand(cmd.name)
            })
          }
        }, (cmd: SlashCommand) => cmd.name)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .padding(Theme.SpacingLG)
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
    if (this.workTimer !== -1) return
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

  // 等待用户操作时振动提醒
  private vibrateAlert(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 300
      }, {
        id: 0,
        usage: 'alarm'
      })
    } catch (e) {
      // 振动失败忽略，不影响功能
    }
  }

  private stopWorkTimer(): void {
    if (this.workTimer !== -1) {
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

  // MARK: - 连接指示

  private getConnectionIcon(): Resource {
    const profile = authStore.activeProfile
    if (!profile) return $r('sys.symbol.questionmark_circle')
    switch (profile.type) {
      case 'lan': return $r('sys.symbol.gearshape')
      case 'pgy': return $r('sys.symbol.questionmark_circle')
      case 'tunnel': return $r('sys.symbol.square_and_pencil')
      default: return $r('sys.symbol.questionmark_circle')
    }
  }

  private getConnectionLabel(): string {
    const profile = authStore.activeProfile
    if (!profile) return '未连接'
    switch (profile.type) {
      case 'lan': return `${profile.name} · 局域网`
      case 'pgy': return `${profile.name} · 蒲公英`
      case 'tunnel': return `${profile.name} · 隧道`
      default: return profile.name
    }
  }

  private getConnectionColor(): ResourceColor {
    const profile = authStore.activeProfile
    if (!profile) return Theme.ErrorColor
    switch (profile.type) {
      case 'lan': return Theme.AccentGreen
      case 'pgy': return Theme.AccentBlue
      case 'tunnel': return Theme.AccentOrange
      default: return Theme.TextSecondary
    }
  }

  private sendMessage(): void {
    const hasAttachments = this.pendingAttachments.length > 0
    if (!this.inputText.trim() && !hasAttachments) return

    const content = this.inputText.trim() || (hasAttachments ? ' ' : '')
    const attachments = hasAttachments ? [...this.pendingAttachments] : undefined
    this.pendingAttachments = []
    this.inputText = ''
    sessionStore.inputDrafts.delete(this.sessionId)

    // 去重：记录最近发送的消息
    if (content.trim()) {
      this.recentlySentMessages.add(content)
      if (this.recentlySentMessages.size > 100) {
        // 清除旧条目：转数组去前50个再转回Set
        const arr = Array.from(this.recentlySentMessages)
        this.recentlySentMessages = new Set(arr.slice(-50))
      }
    }
    this.userIsViewingHistory = false

    sessionStore.sendMessage(content, attachments)

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

  // MARK: - 附件处理

  /**
   * 从相册选择图片
   */
  private async pickPhotoFromGallery(): Promise<void> {
    try {
      const picker = new photoViewPicker.PhotoViewPicker()
      const result = await picker.select()
      const uris = result['photoUris'] || result['uri']
      if (!uris) {
        console.error('[ChatDetailPage] No photo selected')
        return
      }
      if (uris.length > 0) {
        await this.loadAttachmentFromUri(uris[0])
      }
    } catch (e) {
      console.error(`[ChatDetailPage] Pick photo error: ${e}`)
    }
  }

  /**
   * 从 URI 读取图片文件并转为 base64 附件
   */
  private async loadAttachmentFromUri(uri: string): Promise<void> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)

      // 限制 10MB
      if (stat.size > 10 * 1024 * 1024) {
        console.error('[ChatDetailPage] File too large, max 10MB')
        fileIo.closeSync(file)
        return
      }

      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)

      const base64 = this.bufferToBase64(buf)

      const name = uri.split('/').pop() || 'photo.jpg'
      const mimeType = this.guessMimeType(name)

      this.pendingAttachments = [...this.pendingAttachments, {
        type: 'image',
        name: name,
        data: base64,
        mimeType: mimeType
      }]
    } catch (e) {
      console.error(`[ChatDetailPage] Load attachment error: ${e}`)
    }
  }

  /**
   * ArrayBuffer 转 base64
   */
  private bufferToBase64(buf: ArrayBuffer): string {
    const uint8Arr = new Uint8Array(buf)
    let binary = ''
    for (let i = 0; i < uint8Arr.length; i++) {
      binary += String.fromCharCode(uint8Arr[i])
    }
    // ArkTS 不支持 btoa，用 Uint8Array 转 base64 的替代方案
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(uint8Arr)
  }

  /**
   * 根据文件名猜测 MIME 类型
   */
  private guessMimeType(fileName: string): string {
    const ext = fileName.toLowerCase().split('.').pop() || ''
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg'
      case 'png':
        return 'image/png'
      case 'gif':
        return 'image/gif'
      case 'webp':
        return 'image/webp'
      case 'heic':
      case 'heif':
        return 'image/heic'
      case 'bmp':
        return 'image/bmp'
      default:
        return 'image/jpeg'
    }
  }
}
